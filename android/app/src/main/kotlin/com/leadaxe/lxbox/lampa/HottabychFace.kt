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
 * Urban Хоттабыч from the reference still: bald head, long pointed white
 * goatee, olive zip hoodie over a white hood layer. Local coords: origin at
 * upper chest; +Y down. Sized to fit inside the split-shield cradle.
 */
object HottabychFace {

    private val hoodiePath = Path()
    private val whiteHoodPath = Path()
    private val beardPath = Path()
    private val mustachePath = Path()
    private val headOval = RectF()

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
        val a = (255 * alpha * (0.35f + r * 0.65f)).toInt().coerceIn(0, 255)
        val lift = (1f - r) * 34f
        val bob = sin(r * 3.2f) * 2.2f * r
        val scale = (0.42f + r * 0.58f) * (0.88f + r * 0.12f)

        canvas.save()
        canvas.translate(0f, lift + bob - 4f)
        canvas.scale(scale, scale)

        // Soft amber smoke while rising (keeps ceremony magic without turban).
        glow.shader = RadialGradient(
            0f, 22f, 40f,
            intArrayOf(0x88FFE8A0.toInt(), 0x33C8A060.toInt(), 0x00000000),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP
        )
        glow.alpha = (a * r * 0.45f).toInt().coerceIn(0, 255)
        canvas.drawCircle(0f, 20f, 38f, glow)
        glow.shader = null

        // Shoulders / olive zip hoodie body.
        hoodiePath.reset()
        hoodiePath.moveTo(-28f, 10f)
        hoodiePath.cubicTo(-32f, 4f, -30f, -6f, -18f, -10f)
        hoodiePath.lineTo(-10f, -6f)
        hoodiePath.lineTo(10f, -6f)
        hoodiePath.lineTo(18f, -10f)
        hoodiePath.cubicTo(30f, -6f, 32f, 4f, 28f, 10f)
        hoodiePath.cubicTo(30f, 28f, 18f, 40f, 0f, 42f)
        hoodiePath.cubicTo(-18f, 40f, -30f, 28f, -28f, 10f)
        hoodiePath.close()
        fill.shader = LinearGradient(
            -24f, -8f, 24f, 42f,
            intArrayOf(0xFF3D4A2E.toInt(), 0xFF2F3A24.toInt(), 0xFF1E2618.toInt()),
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP
        )
        fill.alpha = a
        canvas.drawPath(hoodiePath, fill)
        fill.shader = null

        // White inner hoodie peek (hood rim + zipper placket).
        whiteHoodPath.reset()
        whiteHoodPath.moveTo(-16f, -8f)
        whiteHoodPath.cubicTo(-20f, -18f, -8f, -22f, 0f, -22f)
        whiteHoodPath.cubicTo(8f, -22f, 20f, -18f, 16f, -8f)
        whiteHoodPath.cubicTo(12f, -4f, -12f, -4f, -16f, -8f)
        whiteHoodPath.close()
        fill.color = withAlpha(0xF2F2F0, a)
        canvas.drawPath(whiteHoodPath, fill)

        // Zipper line.
        stroke.strokeWidth = 1.5f
        stroke.strokeCap = Paint.Cap.ROUND
        stroke.color = withAlpha(0x9AA090, (a * 0.85f).toInt())
        canvas.drawLine(0f, -4f, 0f, 36f, stroke)

        // Bald head.
        headOval.set(-15f, -34f, 15f, -2f)
        fill.shader = RadialGradient(
            -3f, -22f, 18f,
            intArrayOf(0xFFFFE0B8.toInt(), 0xFFE8B888.toInt(), 0xFFD4A06A.toInt()),
            floatArrayOf(0f, 0.55f, 1f),
            Shader.TileMode.CLAMP
        )
        fill.alpha = a
        canvas.drawOval(headOval, fill)
        fill.shader = null

        // Ears (slight).
        fill.color = withAlpha(0xE8B888, a)
        canvas.drawOval(-18f, -22f, -13f, -12f, fill)
        canvas.drawOval(13f, -22f, 18f, -12f, fill)

        // Brows — serious, almost flat.
        stroke.strokeWidth = 2.4f
        stroke.color = withAlpha(0x5A4638, a)
        canvas.drawLine(-11f, -18f, -3f, -19f, stroke)
        canvas.drawLine(3f, -19f, 11f, -18f, stroke)

        // Eyes.
        fill.color = withAlpha(0xFFFFFF, a)
        canvas.drawOval(-11f, -16f, -3f, -8f, fill)
        canvas.drawOval(3f, -16f, 11f, -8f, fill)
        fill.color = withAlpha(0x2C2118, a)
        if (wink > 0.35f) {
            stroke.strokeWidth = 2.3f
            stroke.color = withAlpha(0x2C2118, a)
            canvas.drawLine(-11f, -12f, -3f, -12f, stroke)
        } else {
            canvas.drawCircle(-7f, -11.5f, 2.0f, fill)
        }
        canvas.drawCircle(7f, -11.5f, 2.0f, fill)

        // Nose hint.
        stroke.strokeWidth = 1.6f
        stroke.color = withAlpha(0xB88860, a)
        canvas.drawLine(0f, -12f, -1.5f, -5f, stroke)
        canvas.drawLine(-1.5f, -5f, 2f, -4.5f, stroke)

        // Mustache — wide, matching the still.
        mustachePath.reset()
        mustachePath.moveTo(-12f, -2f)
        mustachePath.cubicTo(-10f, -6f, -4f, -5f, 0f, -3f)
        mustachePath.cubicTo(4f, -5f, 10f, -6f, 12f, -2f)
        mustachePath.cubicTo(8f, 2f, 3f, 1f, 0f, 0f)
        mustachePath.cubicTo(-3f, 1f, -8f, 2f, -12f, -2f)
        mustachePath.close()
        fill.color = withAlpha(0xF5F5F2, a)
        canvas.drawPath(mustachePath, fill)

        // Long pointed white goatee (the signature silhouette).
        beardPath.reset()
        beardPath.moveTo(-7f, 0f)
        beardPath.cubicTo(-9f, 10f, -6f, 24f, -2f, 40f)
        beardPath.cubicTo(-1f, 46f, 0f, 52f, 0f, 56f)
        beardPath.cubicTo(0f, 52f, 1f, 46f, 2f, 40f)
        beardPath.cubicTo(6f, 24f, 9f, 10f, 7f, 0f)
        beardPath.cubicTo(4f, 4f, -4f, 4f, -7f, 0f)
        beardPath.close()
        fill.shader = LinearGradient(
            0f, 0f, 0f, 56f,
            intArrayOf(0xFFF8F8F5.toInt(), 0xFFEAEAE6.toInt(), 0xFFD8D8D2.toInt()),
            floatArrayOf(0f, 0.55f, 1f),
            Shader.TileMode.CLAMP
        )
        fill.alpha = a
        canvas.drawPath(beardPath, fill)
        fill.shader = null

        // Closed mouth line under mustache — calm, not cartoon smile.
        stroke.strokeWidth = 1.5f
        stroke.color = withAlpha(0x8A7060, (a * 0.7f).toInt())
        canvas.drawLine(-4f, 1.5f, 4f, 1.5f, stroke)

        // Tiny bronze vessel hint at the bottom of the hoodie (readable at dock scale).
        if (r > 0.65f) {
            val va = ((a * (r - 0.65f) / 0.35f)).toInt().coerceIn(0, 255)
            fill.color = withAlpha(0x8B6914, va)
            canvas.drawOval(-6f, 28f, 6f, 36f, fill)
            stroke.strokeWidth = 1.3f
            stroke.color = withAlpha(0xC4A35A, va)
            canvas.drawArc(RectF(-9f, 26f, -2f, 34f), 200f, 140f, false, stroke)
            canvas.drawArc(RectF(2f, 26f, 9f, 34f), 200f, 140f, false, stroke)
        }

        canvas.restore()
    }
}
