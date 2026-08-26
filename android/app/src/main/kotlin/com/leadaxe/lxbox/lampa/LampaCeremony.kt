package com.leadaxe.lxbox.lampa

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout

/**
 * Full-screen connect overlays live on the Activity content view — the same
 * layout as Lampa's `activity_main.xml` — so the shield can fly across the
 * whole screen instead of being clipped to the 248dp dock PlatformView.
 */
internal object LampaCeremony {
    private var overlay: ShieldLaunchOverlayView? = null
    private var frost: FrostOverlayView? = null
    private var host: ViewGroup? = null

    fun overlay(): ShieldLaunchOverlayView? = overlay
    fun frost(): FrostOverlayView? = frost

    fun attach(context: Context) {
        val activity = context.findActivity() ?: return
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        if (host === root && overlay?.parent === root && frost?.parent === root) return
        detach()
        host = root
        // Above Flutter canvas so cracks are visible; below the flying shield.
        // Power PlatformView uses Hybrid Composition and stays interactive.
        val frostView = FrostOverlayView(activity).apply {
            elevation = 48f
            translationZ = 48f
            visibility = View.GONE // cracks disabled for now
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val overlayView = ShieldLaunchOverlayView(activity).apply {
            elevation = 64f
            translationZ = 64f
            visibility = View.GONE
            isClickable = false
            isFocusable = false
        }
        val lp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        root.addView(frostView, lp)
        root.addView(overlayView, lp)
        overlay = overlayView
        frost = frostView
    }

    fun detach() {
        overlay?.cancel()
        frost?.melt()
        (overlay?.parent as? ViewGroup)?.removeView(overlay)
        (frost?.parent as? ViewGroup)?.removeView(frost)
        overlay = null
        frost = null
        host = null
    }

    /** Keep shield flight above frost; never raise frost over the power button. */
    fun bringToFront() {
        if (overlay?.isPlaying != true) return
        overlay?.let { host?.bringChildToFront(it) }
    }

    /** Hide Activity-level overlays while Flutter pushes other screens. */
    fun setVisible(visible: Boolean) {
        frost?.visibility = View.GONE
        frost?.pause()
        if (!visible) {
            overlay?.pause()
            overlay?.visibility = View.GONE
            return
        }
        // Idle overlay must stay GONE — a full-screen VISIBLE view over
        // FlutterView forces an extra compositor layer and kills frame rate.
        if (overlay?.isPlaying == true) {
            overlay?.visibility = View.VISIBLE
            overlay?.resume()
        } else {
            overlay?.visibility = View.GONE
        }
    }

    fun onHostHidden() {
        frost?.pause()
        frost?.visibility = View.GONE
        overlay?.pause()
        overlay?.visibility = View.GONE
    }

    fun onHostVisible() {
        if (overlay?.isPlaying == true) {
            overlay?.visibility = View.VISIBLE
            overlay?.resume()
        }
    }
}

internal tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
