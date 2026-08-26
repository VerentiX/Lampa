package com.leadaxe.lxbox.lampa

import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import com.leadaxe.lxbox.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class LampaPowerViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        LampaPowerPlatformView(context, messenger, viewId, args as? Map<*, *>)
}

/**
 * Dock only (glow + button + shield). Flying shield + frost live on the
 * Activity content view so they are not clipped to this 248dp platform view.
 * No spinning loading ring — Lampa connect ceremony does not use one.
 */
private class LampaPowerPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    args: Map<*, *>?,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val root = FrameLayout(context)
    private val glow = View(context)
    private val button = FrameLayout(context)
    private val content = FrameLayout(context)
    private val shield = ShieldDockView(context)
    private val channel = MethodChannel(messenger, "com.leadaxe.lxbox/lampa_power/$viewId")

    private var connected = args?.get("connected") == true
    private var connecting = args?.get("connecting") == true
    private var animate = args?.get("animate") != false
    private var ceremonyActive = false
    private var shieldSeated = connected && !connecting
    private var lastConnected: Boolean? = if (connected) true else if (connecting) false else false

    init {
        root.clipChildren = false
        root.clipToPadding = false
        glow.setBackgroundResource(R.drawable.bg_power_glow)
        glow.alpha = if (shieldSeated && animate) 1f else 0f
        root.addView(glow, frame(248, 248, Gravity.CENTER))

        button.setBackgroundResource(
            if (shieldSeated) R.drawable.bg_power_btn_connected else R.drawable.bg_power_btn_inactive
        )
        button.elevation = dp(14).toFloat()
        button.isClickable = true
        button.setOnClickListener { channel.invokeMethod("tap", null) }

        content.setPadding(dp(10), dp(10), dp(10), dp(10))
        content.addView(shield, frameMatch())
        button.addView(content, frameMatch())
        root.addView(button, frame(192, 192, Gravity.CENTER))

        shield.setPowered(shieldSeated, animate = false)
        channel.setMethodCallHandler(this)
        LampaCeremony.attach(context)
        applyVisual(initial = true)
    }

    override fun getView(): View = root

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> {
                connecting = call.argument<Boolean>("connecting") == true
                connected = call.argument<Boolean>("connected") == true
                animate = call.argument<Boolean>("animate") != false
                applyVisual(initial = false)
                result.success(null)
            }
            "pause" -> {
                freezeIdle()
                LampaCeremony.onHostHidden()
                result.success(null)
            }
            "resume" -> {
                LampaCeremony.onHostVisible()
                result.success(null)
            }
            "hideOverlays" -> {
                LampaCeremony.setVisible(false)
                result.success(null)
            }
            "showOverlays" -> {
                LampaCeremony.setVisible(true)
                if (animate) LampaCeremony.bringToFront()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun applyVisual(initial: Boolean) {
        if (!animate) {
            cancelCeremony()
            seat(connected, flip = !initial && lastConnected != connected)
            lastConnected = connected
            return
        }

        when {
            connecting -> {
                if (!ceremonyActive && lastConnected != true) {
                    playCeremony()
                } else if (!ceremonyActive) {
                    cancelCeremony()
                    shield.setPowered(false, animate = false)
                    button.setBackgroundResource(R.drawable.bg_power_btn_inactive)
                    glow.animate().cancel()
                    glow.alpha = 0.45f
                }
            }
            connected -> {
                if (ceremonyActive) {
                    if (shieldSeated) seatConnectedLook()
                } else {
                    val changed = lastConnected != true
                    if (changed && !shieldSeated) {
                        playFlip(powered = true)
                    } else {
                        seat(true, flip = false)
                    }
                }
            }
            else -> {
                // Disconnect must stay light: the old soft-settle + 3D flip stack
                // stuttered on Hybrid Composition when stopping the VPN.
                if (ceremonyActive || LampaCeremony.overlay()?.isPlaying == true) {
                    cancelCeremony()
                }
                val changed = lastConnected == true
                if (changed) {
                    playDisconnect()
                } else {
                    seat(false, flip = false)
                }
            }
        }
        lastConnected = when {
            connecting -> false
            connected -> true
            else -> false
        }
    }

    private fun playCeremony() {
        val overlay = LampaCeremony.overlay() ?: return
        if (ceremonyActive || overlay.isPlaying) return
        ceremonyActive = true
        shieldSeated = false
        shield.setPowered(false, animate = false)
        shield.alpha = 1f
        button.clearAnimation()
        button.setBackgroundResource(R.drawable.bg_power_btn_inactive)
        button.alpha = 1f
        glow.animate().cancel()
        glow.alpha = 0.45f
        LampaCeremony.bringToFront()
        overlay.play(
            button,
            onImpact = {
                shieldSeated = true
                root.post {
                    if (!shieldSeated) return@post
                    seatConnectedLook()
                    shield.setPowered(true, animate = false)
                    punch()
                }
                root.postDelayed({
                    if (!shieldSeated || !animate) return@postDelayed
                    // Frost overlay stays disabled (LampaCeremony) — skip freeze work.
                }, 200L)
            },
            onEnd = {
                ceremonyActive = false
                if (!shieldSeated) {
                    shieldSeated = true
                    seatConnectedLook()
                    shield.setPowered(true, animate = false)
                }
                if (connected) freezeIdle()
            },
        )
    }

    private fun cancelCeremony() {
        val overlay = LampaCeremony.overlay()
        if (overlay?.isPlaying == true || ceremonyActive) overlay?.cancel()
        ceremonyActive = false
        shield.animate().cancel()
        shield.alpha = 1f
        shieldSeated = connected
        shield.setPowered(connected, animate = false)
        button.setBackgroundResource(
            if (connected) R.drawable.bg_power_btn_connected else R.drawable.bg_power_btn_inactive
        )
        if (!connected) {
            freezeIdle()
            glow.animate().alpha(0f).setDuration(260L).start()
        }
    }

    private fun seat(on: Boolean, flip: Boolean) {
        shieldSeated = on
        if (flip) {
            playFlip(powered = on)
            return
        }
        shield.setPowered(on, animate = false)
        button.setBackgroundResource(
            if (on) R.drawable.bg_power_btn_connected else R.drawable.bg_power_btn_inactive
        )
        glow.animate().cancel()
        glow.alpha = if (on && animate) 1f else 0f
        freezeIdle()
    }

    private fun seatConnectedLook() {
        button.setBackgroundResource(R.drawable.bg_power_btn_connected)
        glow.animate().cancel()
        glow.animate().alpha(1f).setDuration(180L).start()
    }

    private fun playFlip(powered: Boolean, onSettled: (() -> Unit)? = null) {
        content.animate().cancel()
        content.cameraDistance = 12_000f * root.resources.displayMetrics.density
        content.animate()
            .rotationY(90f)
            .setDuration(170L)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction {
                shield.setPowered(powered, animate = false)
                button.setBackgroundResource(
                    if (powered) R.drawable.bg_power_btn_connected
                    else R.drawable.bg_power_btn_inactive
                )
                glow.animate().cancel()
                glow.animate().alpha(if (powered && animate) 1f else 0f).setDuration(180L).start()
                content.rotationY = -90f
                content.animate()
                    .rotationY(0f)
                    .setDuration(190L)
                    .setInterpolator(DecelerateInterpolator())
                    .withEndAction {
                        content.rotationY = 0f
                        onSettled?.invoke()
                    }
                    .start()
            }
            .start()
    }

    private fun punch() {
        button.clearAnimation()
        button.animate().cancel()
        glow.animate().cancel()
        glow.alpha = 1f
        button.scaleX = 0.92f
        button.scaleY = 0.92f
        button.animate()
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(140L)
            .setInterpolator(DecelerateInterpolator())
            .start()
    }

    /** Fast off transition — no competing ViewPropertyAnimator stacks. */
    private fun playDisconnect() {
        content.animate().cancel()
        button.animate().cancel()
        glow.animate().cancel()
        content.rotationY = 0f
        button.scaleX = 1f
        button.scaleY = 1f
        shieldSeated = false
        shield.setPowered(false, animate = true)
        button.setBackgroundResource(R.drawable.bg_power_btn_inactive)
        glow.animate().alpha(0f).setDuration(200L).start()
        button.animate()
            .scaleX(0.96f)
            .scaleY(0.96f)
            .setDuration(90L)
            .withEndAction {
                button.animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(160L)
                    .setInterpolator(DecelerateInterpolator())
                    .start()
            }
            .start()
    }

    private fun freezeIdle() {
        button.clearAnimation()
        button.animate().cancel()
        glow.animate().cancel()
        content.animate().cancel()
        shield.animate().cancel()
        button.scaleX = 1f
        button.scaleY = 1f
        content.rotationY = 0f
        shield.pauseMotion()
    }

    private fun frame(w: Int, h: Int, gravity: Int) =
        FrameLayout.LayoutParams(dp(w), dp(h), gravity)

    private fun frameMatch() =
        FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )

    private fun dp(value: Int) = (value * root.resources.displayMetrics.density).toInt()

    override fun dispose() {
        channel.setMethodCallHandler(null)
        cancelCeremony()
        LampaCeremony.detach()
    }
}
