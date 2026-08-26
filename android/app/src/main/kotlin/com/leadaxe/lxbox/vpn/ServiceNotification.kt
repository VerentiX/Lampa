package com.leadaxe.lxbox.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.leadaxe.lxbox.R

class ServiceNotification(private val service: Service) {
    companion object {
        private const val CHANNEL_ID = "boxvpn_vpn_channel"
        private const val NOTIFICATION_ID = 1

        fun createChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    L10n.str(
                        ctx,
                        R.string.vpn_notification_channel_name,
                        L10n.str(ctx, R.string.app_name),
                    ),
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description =
                        L10n.str(ctx, R.string.notification_channel_description)
                    setShowBadge(false)
                    lightColor = android.graphics.Color.DKGRAY
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                }
                BoxApplication.notificationManager.createNotificationChannel(channel)
            }
        }
    }

    private var largeIcon: Bitmap? = null

    init {
        createChannel(service)
    }

    private fun buildNotification(title: String, text: String)
        : android.app.Notification {
        val openIntent = service.packageManager
            .getLaunchIntentForPackage(service.packageName)
        val pendingIntent = if (openIntent != null) {
            PendingIntent.getActivity(
                service, 0, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        val body = text.ifBlank {
            L10n.str(service, R.string.status_connected)
        }
        val builder = NotificationCompat.Builder(service, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_lampa)
            .setLargeIcon(appIcon())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)

        if (pendingIntent != null) builder.setContentIntent(pendingIntent)

        builder
            .addAction(
                0,
                L10n.str(service, R.string.notification_action_stop),
                broadcastPI(BoxVpnService.ACTION_STOP, 1),
            )
            .addAction(
                0,
                L10n.str(service, R.string.notification_action_reconnect),
                broadcastPI(BoxVpnService.ACTION_RECONNECT, 2),
            )
        return builder.build()
    }

    private fun appIcon(): Bitmap? {
        largeIcon?.let { return it }
        val drawable = ContextCompat.getDrawable(service, R.drawable.ic_lampa_app_icon)
            ?: return null
        val size = (64f * service.resources.displayMetrics.density).toInt().coerceAtLeast(128)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        largeIcon = bitmap
        return bitmap
    }

    private fun broadcastPI(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(action).setPackage(service.packageName)
        return PendingIntent.getBroadcast(
            service, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun show(title: String, text: String) {
        val notification = buildNotification(title, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            service.startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            service.startForeground(NOTIFICATION_ID, notification)
        }
    }

    fun stop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            service.stopForeground(true)
        }
    }
}
