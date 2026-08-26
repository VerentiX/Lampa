package com.leadaxe.lxbox.lampa

import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.sin

/**
 * Urban Хоттабыч (photo reference): bald head, heavy silvery-white beard that
 * starts full at the jaw and tapers to a long point, forest-green zip hoodie
 * with white drawstrings / inner hood, bronze dragon vessel at the chest.
 *
 * Local coords: origin at upper chest; +Y down. Sized for the shield cradle.
 */
object HottabychFace {

    private val hoodiePath = Path()
    private val hoodInnerPath = Path()
    private val beardPath = Path()
    private val mustachePath = Path()
    private val vesselPath = Path()
    private val headOval = RectF()
    private val tmpArc = RectF()

    private fun withAlpha(rgb: Int, alpha: Int): Int = (alpha shl 24) or (rgb and 0xFFFFFF)

    fun draw(
        canvas: Canvas,
        reveal: Float,
        wink: Float,
        alpha: Float,
        fill: Paint,
        stroke: Paint,
        glow: Paint
    ) {
        if (reveal <= 0.02f || alpha <= 0.02f) return

        val r = reveal.coerceIn(0f, 1f)
        val a = (255 * alpha * (0.4f + r * 0.6f)).toInt().coerceIn(0, 255)
        val lift = (1f - r) * 30f
        val bob = sin(r * 2.8f) * 1.8f * r
        val scale = (0.46f + r * 0.54f) * (0.9f + r * 0.1f)

        canvas.save()
        canvas.translate(0f, lift + bob - 2f)
        canvas.scale(scale, scale)

        // Soft lift haze (no cartoon sparkles).
        glow.shader = RadialGradient(
            0f, 18f, 36f,
            intArrayOf(0x66C8B070.toInt(), 0x228A7040.toInt(), 0x00000000),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP
        )
        glow.alpha = (a * r * 0.35f).toInt().coerceIn(0, 255)
        canvas.drawCircle(0f, 16f, 34f, glow)
        glow.shader = null

        // —— Forest-green zip hoodie torso ——
        hoodiePath.reset()
        hoodiePath.moveTo(-30f, 8f)
        hoodiePath.cubicTo(-34f, 0f, -32f, -10f, -20f, -14f)
        hoodiePath.lineTo(-11f, -8f)
        hoodiePath.lineTo(11f, -8f)
        hoodiePath.lineTo(20f, -14f)
        hoodiePath.cubicTo(32f, -10f, 34f, 0f, 30f, 8f)
        hoodiePath.cubicTo(32f, 30f, 20f, 44f, 0f, 46f)
        hoodiePath.cubicTo(-20f, 44f, -32f, 30f, -30f, 8f)
        hoodiePath.close()
        fill.shader = LinearGradient(
            -26f, -12f, 26f, 46f,
            intArrayOf(0xFF3A4A30.toInt(), 0xFF2A3624.toInt(), 0xFF1A2216.toInt()),
            floatArrayOf(0f, 0.4f, 1f),
            Shader.TileMode.CLAMP
        )
        fill.alpha = a
        canvas.drawPath(hoodiePath, fill)
        fill.shader = null

        // White inner hood collar (visible under green).
        hoodInnerPath.reset()
        hoodInnerPath.moveTo(-17f, -10f)
        hoodInnerPath.cubicTo(-22f, -20f, -10f, -26f, 0f, -26f)
        hoodInnerPath.cubicTo(10f, -26f, 22f, -20f, 17f, -10f)
        hoodInnerPath.cubicTo(12f, -5f, -12f, -5f, -17f, -10f)
        hoodInnerPath.close()
        fill.color = withAlpha(0xF4F4F0, a)
        canvas.drawPath(hoodInnerPath, fill)

        // White drawstrings hanging on the chest.
        stroke.strokeWidth = 2.0f
        stroke.strokeCap = Paint.Cap.ROUND
        stroke.color = withAlpha(0xF0F0EC, a)
        canvas.drawLine(-7f, -6f, -9f, 22f, stroke)
        canvas.drawLine(7f, -6f, 9f, 22f, stroke)
        fill.color = withAlpha(0xE8E8E4, a)
        canvas.drawCircle(-9f, 24f, 2.2f, fill)
        canvas.drawCircle(9f, 24f, 2.2f, fill)

        // Zipper.
        stroke.strokeWidth = 1.4f
        stroke.color = withAlpha(0x8A9080, (a * 0.9f).toInt())
        canvas.drawLine(0f, -5f, 0f, 38f, stroke)

        // —— Bald head (slightly oval, weathered tan) ——
        headOval.set(-16f, -38f, 16f, -4f)
        fill.shader = RadialGradient(
            -4f, -26f, 20f,
            intArrayOf(0xFFF0C8A0.toInt(), 0xFFD4A078.toInt(), 0xFFB88860.toInt()),
            floatArrayOf(0f, 0.55f, 1f),
            Shader.TileMode.CLAMP
        )
        fill.alpha = a
        canvas.drawOval(headOval, fill)
        fill.shader = null

        // Ears.
        fill.color = withAlpha(0xD4A078, a)
        canvas.drawOval(-19.5f, -26f, -14f, -14f, fill)
        canvas.drawOval(14f, -26f, 19.5f, -14f, fill)

        // Serious brows — heavy, almost flat.
        stroke.strokeWidth = 2.8f
        stroke.color = withAlpha(0x4A3A30, a)
        canvas.drawLine(-12f, -22f, -2.5f, -23f, stroke)
        canvas.drawLine(2.5f, -23f, 12f, -22f, stroke)

        // Deep-set eyes — left eye winks with a smooth lid squash (not a hard snap).
        val winkAmt = wink.coerceIn(0f, 1f)
        val leftOpen = (1f - winkAmt).coerceIn(0.08f, 1f)

        // Right eye stays open.
        fill.color = withAlpha(0xFFF8F0, a)
        canvas.drawOval(3.5f, -20f, 12f, -11f, fill)
        fill.color = withAlpha(0x1A1410, a)
        canvas.drawCircle(7.6f, -15.2f, 2.15f, fill)

        // Left eye: squash vertically as the lid closes.
        val eyeCx = -7.75f
        val eyeCy = -15.5f
        canvas.save()
        canvas.scale(1f, leftOpen, eyeCx, eyeCy)
        fill.color = withAlpha(0xFFF8F0, a)
        canvas.drawOval(-12f, -20f, -3.5f, -11f, fill)
        if (leftOpen > 0.28f) {
            fill.color = withAlpha(0x1A1410, (a * leftOpen).toInt().coerceIn(0, 255))
            canvas.drawCircle(eyeCx, eyeCy + 0.3f, 2.15f, fill)
        }
        canvas.restore()

        // Soft lid line grows with the wink.
        if (winkAmt > 0.08f) {
            stroke.strokeWidth = 2.2f + 0.8f * winkAmt
            stroke.strokeCap = Paint.Cap.ROUND
            stroke.color = withAlpha(0x3A2A20, ((a * (0.35f + 0.65f * winkAmt)).toInt()))
            canvas.drawLine(-12f, eyeCy, -3.5f, eyeCy, stroke)
            // Upper lid shadow when almost closed.
            if (winkAmt > 0.55f) {
                stroke.strokeWidth = 3.2f
                stroke.color = withAlpha(0x2A1C14, ((a * (winkAmt - 0.55f) / 0.45f).toInt().coerceIn(0, 255)))
                canvas.drawLine(-11.5f, eyeCy - 1.2f, -4f, eyeCy - 1.2f, stroke)
            }
        }

        // Strong nose.
        stroke.strokeWidth = 1.7f
        stroke.color = withAlpha(0xA87850, a)
        canvas.drawLine(0.5f, -16f, -2f, -7f, stroke)
        canvas.drawLine(-2f, -7f, 3f, -6.5f, stroke)

        // Full white mustache (wide, connected to beard).
        mustachePath.reset()
        mustachePath.moveTo(-14f, -4f)
        mustachePath.cubicTo(-12f, -9f, -5f, -8f, 0f, -5.5f)
        mustachePath.cubicTo(5f, -8f, 12f, -9f, 14f, -4f)
        mustachePath.cubicTo(10f, 1f, 4f, 0.5f, 0f, -0.5f)
        mustachePath.cubicTo(-4f, 0.5f, -10f, 1f, -14f, -4f)
        mustachePath.close()
        fill.color = withAlpha(0xF2F2EE, a)
        canvas.drawPath(mustachePath, fill)

        // Long thick silver-white beard: full at jaw → long taper (photo silhouette).
        beardPath.reset()
        beardPath.moveTo(-15f, -2f)
        beardPath.cubicTo(-20f, 8f, -16f, 22f, -10f, 34f)
        beardPath.cubicTo(-6f, 44f, -2f, 52f, 0f, 58f)
        beardPath.cubicTo(2f, 52f, 6f, 44f, 10f, 34f)
        beardPath.cubicTo(16f, 22f, 20f, 8f, 15f, -2f)
        beardPath.cubicTo(8f, 6f, -8f, 6f, -15f, -2f)
        beardPath.close()
        fill.shader = LinearGradient(
            0f, -2f, 0f, 58f,
            intArrayOf(0xFFF7F7F4.toInt(), 0xFFE6E6E2.toInt(), 0xFFC8C8C2.toInt()),
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP
        )
        fill.alpha = a
        canvas.drawPath(beardPath, fill)
        fill.shader = null

        // Side cheek whiskers — makes the beard read wider like the photo.
        fill.color = withAlpha(0xEEEEEA, (a * 0.9f).toInt())
        canvas.drawOval(-18f, -2f, -10f, 12f, fill)
        canvas.drawOval(10f, -2f, 18f, 12f, fill)

        // Closed serious mouth under mustache.
        stroke.strokeWidth = 1.4f
        stroke.color = withAlpha(0x6A5040, (a * 0.65f).toInt())
        canvas.drawLine(-3.5f, 0.5f, 3.5f, 0.5f, stroke)

        // Bronze dragon vessel held at mid-chest.
        if (r > 0.55f) {
            val va = ((a * (r - 0.55f) / 0.45f)).toInt().coerceIn(0, 255)
            vesselPath.reset()
            vesselPath.addOval(RectF(-8f, 26f, 8f, 38f), Path.Direction.CW)
            fill.shader = RadialGradient(
                -2f, 30f, 10f,
                intArrayOf(0xFFC4A050.toInt(), 0xFF8B6914.toInt(), 0xFF5A4010.toInt()),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP
            )
            fill.alpha = va
            canvas.drawPath(vesselPath, fill)
            fill.shader = null

            // Dragon-like curved handles.
            stroke.strokeWidth = 1.8f
            stroke.color = withAlpha(0xB8943A, va)
            tmpArc.set(-14f, 22f, -2f, 36f)
            canvas.drawArc(tmpArc, 200f, 150f, false, stroke)
            tmpArc.set(2f, 22f, 14f, 36f)
            canvas.drawArc(tmpArc, 190f, 150f, false, stroke)

            // Hands gripping the vessel (simple blocks).
            fill.color = withAlpha(0xC89870, va)
            canvas.drawRoundRect(RectF(-14f, 30f, -7f, 38f), 2f, 2f, fill)
            canvas.drawRoundRect(RectF(7f, 30f, 14f, 38f), 2f, 2f, fill)
        }

        canvas.restore()
    }
}
