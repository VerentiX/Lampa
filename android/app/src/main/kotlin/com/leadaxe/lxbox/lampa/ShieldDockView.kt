package com.leadaxe.lxbox.lampa

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import kotlin.math.min

/**
 * Power-button face: dense tech bay with empty shield cradle when off;
 * armored seated shield + live gears when on.
 *
 * Loading progress is shown by the outer [power_loading_ring] ImageView — not here.
 */
class ShieldDockView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val shieldPath = Path()
    private val dockShieldPath = Path()
    private val crestBase = Path()
    private val crestPath = Path()
    private val tmpMatrix = Matrix()

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private var powered = false
    private var powerBlend = 0f
    private var blendAnimator: ValueAnimator? = null

    private val dens by lazy { resources.displayMetrics.density }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        buildShield()
        buildCrest()
    }

    val isPowered: Boolean get() = powered

    fun setPowered(on: Boolean, animate: Boolean = true) {
        if (powered == on && (!animate || (on && powerBlend > 0.98f) || (!on && powerBlend < 0.02f))) {
            powered = on
            powerBlend = if (on) 1f else 0f
            invalidate()
            return
        }
        powered = on
        blendAnimator?.cancel()
        if (!animate) {
            powerBlend = if (on) 1f else 0f
            invalidate()
            return
        }
        val from = powerBlend
        val to = if (on) 1f else 0f
        blendAnimator = ValueAnimator.ofFloat(from, to).apply {
            duration = if (on) 420L else 280L
            addUpdateListener {
                powerBlend = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    fun pauseMotion() {
        blendAnimator?.pause()
    }

    fun resumeMotion() {
        blendAnimator?.resume()
    }

    override fun onDetachedFromWindow() {
        blendAnimator?.cancel()
        blendAnimator = null
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width * 0.5f
        val cy = height * 0.5f
        val r = min(width, height) * 0.49f
        if (r < 2f) return

        val on = powerBlend.coerceIn(0f, 1f)
        val off = 1f - on
        val pulse = 0.82f + 0.18f * on

        drawBayPlate(canvas, cx, cy, r, on)
        drawBezel(canvas, cx, cy, r, on, pulse)
        drawShieldFace(canvas, cx, cy, r, on, off, pulse)
        drawActiveEnergyRing(canvas, cx, cy, r, on, pulse)
    }

    /** Clean lit ring when online — one stroke, no busy sparks. */
    private fun drawActiveEnergyRing(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        r: Float,
        on: Float,
        pulse: Float
    ) {
        if (on < 0.05f) return
        val radius = r * 0.86f
        strokePaint.strokeWidth = 2.6f * dens
        strokePaint.color = (0x00A8FFE8) or
            (((120 + (40 * pulse).toInt()) * on).toInt().coerceIn(0, 255) shl 24)
        canvas.drawCircle(cx, cy, radius, strokePaint)
    }

    private fun drawBayPlate(canvas: Canvas, cx: Float, cy: Float, r: Float, on: Float) {
        fillPaint.shader = null
        fillPaint.color = if (on > 0.4f) 0xFF143848.toInt() else 0xFF161E2C.toInt()
        fillPaint.alpha = 255
        canvas.drawCircle(cx, cy, r, fillPaint)
    }

    private fun drawBezel(canvas: Canvas, cx: Float, cy: Float, r: Float, on: Float, pulse: Float) {
        strokePaint.strokeWidth = 2.2f * dens
        strokePaint.color = if (on > 0.4f) {
            (0x00A8FFE8) or (((140 + (30 * pulse).toInt()).coerceIn(0, 255)) shl 24)
        } else {
            (0x00C8E8FF) or (90 shl 24)
        }
        canvas.drawCircle(cx, cy, r * 0.94f, strokePaint)
    }

    private fun drawShieldFace(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        r: Float,
        on: Float,
        off: Float,
        pulse: Float
    ) {
        val socketScale = (r * 0.82f) / 108f
        dockShieldPath.set(shieldPath)
        tmpMatrix.reset()
        tmpMatrix.setScale(socketScale, socketScale)
        tmpMatrix.postTranslate(cx, cy)
        dockShieldPath.transform(tmpMatrix)

        fillPaint.shader = null
        fillPaint.color = 0xFF0C141E.toInt()
        fillPaint.alpha = 255
        canvas.drawPath(dockShieldPath, fillPaint)

        if (off > 0.04f) {
            strokePaint.strokeWidth = 2.0f * dens
            strokePaint.color = (0x00B8E0FF) or (((120 * off).toInt().coerceIn(0, 255)) shl 24)
            canvas.drawPath(dockShieldPath, strokePaint)
            canvas.save()
            canvas.scale(0.78f, 0.78f, cx, cy)
            strokePaint.strokeWidth = 1.4f * dens
            strokePaint.color = (0x00B8E0FF) or (((55 * off).toInt().coerceIn(0, 255)) shl 24)
            canvas.drawPath(dockShieldPath, strokePaint)
            canvas.restore()
        }

        if (on > 0.02f) {
            fillPaint.shader = LinearGradient(
                cx - r * 0.22f, cy - r * 0.48f,
                cx + r * 0.18f, cy + r * 0.46f,
                intArrayOf(0xFFFAFFFE.toInt(), 0xFF7FE8D4.toInt(), 0xFF2F7AA8.toInt()),
                floatArrayOf(0f, 0.42f, 1f),
                Shader.TileMode.CLAMP
            )
            fillPaint.alpha = (255 * on).toInt()
            canvas.drawPath(dockShieldPath, fillPaint)

            fillPaint.shader = LinearGradient(
                cx, cy - r * 0.46f,
                cx, cy - r * 0.02f,
                intArrayOf(0xAAFFFFFF.toInt(), 0x00FFFFFF),
                floatArrayOf(0f, 1f),
                Shader.TileMode.CLAMP
            )
            fillPaint.alpha = (170 * on).toInt()
            canvas.drawPath(dockShieldPath, fillPaint)

            canvas.save()
            canvas.scale(0.78f, 0.78f, cx, cy)
            strokePaint.strokeWidth = 1.6f * dens
            strokePaint.color = (0x00FFFFFF) or (((110 * on).toInt().coerceIn(0, 255)) shl 24)
            canvas.drawPath(dockShieldPath, strokePaint)
            canvas.restore()

            canvas.save()
            canvas.translate(cx, cy + r * 0.04f)
            canvas.scale(socketScale * 0.58f, socketScale * 0.58f)
            // No perpetual wink on the docked face — that looked like a stuck eye.
            HottabychFace.draw(
                canvas,
                reveal = 1f,
                wink = 0f,
                alpha = on,
                fill = fillPaint,
                stroke = strokePaint,
                glow = glowPaint
            )
            canvas.restore()

            strokePaint.strokeWidth = 2.6f * dens
            strokePaint.color = (0x00F5FCFF) or (((220 * on).toInt().coerceIn(0, 255)) shl 24)
            canvas.drawPath(dockShieldPath, strokePaint)
        }
    }

    private fun buildShield() {
        shieldPath.reset()
        shieldPath.moveTo(0f, -54f)
        shieldPath.cubicTo(20f, -54f, 41f, -48f, 42f, -26f)
        shieldPath.lineTo(42f, 2f)
        shieldPath.cubicTo(42f, 24f, 24f, 46f, 0f, 58f)
        shieldPath.cubicTo(-24f, 46f, -42f, 24f, -42f, 2f)
        shieldPath.lineTo(-42f, -26f)
        shieldPath.cubicTo(-41f, -48f, -20f, -54f, 0f, -54f)
        shieldPath.close()
    }

    private fun buildCrest() {
        crestBase.reset()
        crestBase.moveTo(-14f, -1f)
        crestBase.lineTo(-4f, 11f)
        crestBase.lineTo(16f, -13f)
        crestBase.lineTo(12f, -17f)
        crestBase.lineTo(-4f, 3f)
        crestBase.lineTo(-10f, -5f)
        crestBase.close()
    }
}
