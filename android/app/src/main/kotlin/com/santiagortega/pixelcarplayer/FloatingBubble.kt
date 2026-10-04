package com.santiagortega.pixelcarplayer

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Burbuja flotante (TYPE_APPLICATION_OVERLAY) con la portada recortada en forma de "cookie" y un
 * título en marquesina debajo. Tocar = volver a Pixel Car Player; mantener presionado y arrastrar =
 * moverla (la posición se guarda). Solo se muestra mientras la app no está al frente.
 * Todos los métodos de instancia: hilo principal.
 */
class FloatingBubble(private val ctx: Context) {

    companion object {
        private val main = Handler(Looper.getMainLooper())
        private val instances = java.util.concurrent.CopyOnWriteArrayList<FloatingBubble>()

        @Volatile private var title = ""
        @Volatile private var artist = ""
        @Volatile private var art: Bitmap? = null
        @Volatile private var playing = false
        @Volatile private var lastArtBytes: ByteArray? = null

        fun canDraw(ctx: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)

        /** Datos de la canción actual (desde Dart). Se guardan aunque la burbuja no exista. */
        fun setNowPlaying(title: String, artist: String, art: ByteArray?, playing: Boolean) {
            this.title = title
            this.artist = artist
            this.playing = playing
            if (art == null) {
                this.art = null
                lastArtBytes = null
            } else if (!art.contentEquals(lastArtBytes)) {
                lastArtBytes = art
                this.art = decode(art, 320)
            }
            main.post { instances.forEach { it.render() } }
        }

        private fun decode(bytes: ByteArray, maxPx: Int): Bitmap? = try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxPx && bounds.outHeight / (sample * 2) >= maxPx) sample *= 2
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (e: Exception) {
            Log.w(TAG, "bubble art decode failed", e)
            null
        }
    }

    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var root: LinearLayout? = null
    private var artView: CookieArtView? = null
    private var titleView: TextView? = null
    private var params: WindowManager.LayoutParams? = null
    private var attached = false
    private var sizeDp = 64
    private var opacity = 0.95f
    private var showTitle = true

    private fun dp(v: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, ctx.resources.displayMetrics).toInt()

    fun configure(sizeDp: Int, opacity: Float, showTitle: Boolean) {
        val rebuild = root == null || sizeDp != this.sizeDp || showTitle != this.showTitle
        this.sizeDp = sizeDp
        this.opacity = opacity
        this.showTitle = showTitle
        if (rebuild) {
            val wasAttached = attached
            remove()
            build()
            if (wasAttached) show()
        }
        root?.alpha = opacity
        render()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun build() {
        instances += this
        val sizePx = dp(sizeDp.toFloat())
        val layout = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            alpha = opacity
            setPadding(dp(4f), dp(4f), dp(4f), dp(4f))
        }
        val artV = CookieArtView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(sizePx, sizePx)
            elevation = dp(6f).toFloat()
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
        }
        layout.addView(artV)
        val titleV = TextView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams((sizePx * 1.7f).toInt(), LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(4f)
            }
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.MARQUEE
            marqueeRepeatLimit = -1
            isSelected = true
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setPadding(dp(6f), dp(2f), dp(6f), dp(2f))
            background = GradientDrawable().apply {
                cornerRadius = dp(10f).toFloat()
                setColor(0xB3000000.toInt())
            }
            visibility = if (showTitle) View.VISIBLE else View.GONE
        }
        layout.addView(titleV)

        val p = CarFeatures.prefs(ctx)
        val dm = ctx.resources.displayMetrics
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = p.getInt(CarFeatures.K_BUBBLE_X, dm.widthPixels - sizePx - dp(24f))
            y = p.getInt(CarFeatures.K_BUBBLE_Y, dm.heightPixels / 2 - sizePx / 2)
        }
        layout.setOnTouchListener(DragHandler(lp))
        root = layout
        artView = artV
        titleView = titleV
        params = lp
        clamp(lp)
    }

    fun show() {
        val r = root ?: return
        if (attached || !canDraw(ctx)) return
        try {
            wm.addView(r, params)
            attached = true
            render()
        } catch (e: Exception) {
            Log.w(TAG, "bubble addView failed", e)
        }
    }

    fun hide() {
        val r = root ?: return
        if (!attached) return
        try {
            wm.removeViewImmediate(r)
        } catch (e: Exception) {
            Log.d(TAG, "bubble removeView failed: ${e.message}")
        }
        attached = false
        artView?.setSpinning(false)
    }

    fun remove() {
        hide()
        instances -= this
        root = null
        artView = null
        titleView = null
    }

    private fun render() {
        artView?.apply {
            setArt(art)
            setSpinning(playing && attached)
        }
        titleView?.text = listOf(title, artist).filter { it.isNotBlank() }.joinToString(" · ")
            .ifEmpty { "Pixel Car Player" }
    }

    private fun clamp(lp: WindowManager.LayoutParams) {
        val dm = ctx.resources.displayMetrics
        val w = root?.width?.takeIf { it > 0 } ?: dp(sizeDp.toFloat() * 1.7f)
        val h = root?.height?.takeIf { it > 0 } ?: dp(sizeDp.toFloat() + 24f)
        lp.x = lp.x.coerceIn(0, (dm.widthPixels - w).coerceAtLeast(0))
        lp.y = lp.y.coerceIn(0, (dm.heightPixels - h).coerceAtLeast(0))
    }

    /** Tocar = abrir la app; mantener presionado y arrastrar = mover (sin pelear con toques accidentales). */
    private inner class DragHandler(private val lp: WindowManager.LayoutParams) : View.OnTouchListener {
        private val slop = ViewConfiguration.get(ctx).scaledTouchSlop
        private val longPress = ViewConfiguration.getLongPressTimeout().toLong()
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false
        private var moved = false
        private val armDrag = Runnable {
            dragging = true
            root?.animate()?.scaleX(1.08f)?.scaleY(1.08f)?.setDuration(120)?.start()
            root?.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        }

        override fun onTouch(v: View, e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX
                    downY = e.rawY
                    startX = lp.x
                    startY = lp.y
                    dragging = false
                    moved = false
                    main.postDelayed(armDrag, longPress)
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (!dragging && (abs(dx) > slop || abs(dy) > slop)) {
                        moved = true
                        main.removeCallbacks(armDrag)
                    }
                    if (dragging) {
                        lp.x = startX + dx.toInt()
                        lp.y = startY + dy.toInt()
                        clamp(lp)
                        if (attached) runCatching { wm.updateViewLayout(v, lp) }
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    main.removeCallbacks(armDrag)
                    if (dragging) {
                        root?.animate()?.scaleX(1f)?.scaleY(1f)?.setDuration(120)?.start()
                        CarFeatures.prefs(ctx).edit()
                            .putInt(CarFeatures.K_BUBBLE_X, lp.x)
                            .putInt(CarFeatures.K_BUBBLE_Y, lp.y)
                            .apply()
                    } else if (!moved && e.actionMasked == MotionEvent.ACTION_UP) {
                        v.performClick()
                        AppLauncher.bringToFront(ctx.applicationContext, CarFeatures.mainTaskId.takeIf { it != -1 })
                    }
                    dragging = false
                }
            }
            return true
        }
    }
}

/** Portada recortada como "cookie" (círculo festoneado de 9 lóbulos, estilo Material You); gira al sonar. */
private class CookieArtView(ctx: Context) : View(ctx) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF2A2A30.toInt() }
    private val note = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFE0E0E8.toInt() }
    private val path = Path()
    private val matrix = Matrix()
    private var bitmap: Bitmap? = null
    private var angle = 0f
    private var animator: ValueAnimator? = null

    fun setArt(b: Bitmap?) {
        if (b === bitmap) return
        bitmap = b
        paint.shader = b?.let { BitmapShader(it, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP) }
        updateShaderMatrix()
        invalidate()
    }

    fun setSpinning(on: Boolean) {
        if (on == (animator != null)) return
        if (on) {
            animator = ValueAnimator.ofFloat(0f, 360f).apply {
                duration = 24_000
                repeatCount = ValueAnimator.INFINITE
                interpolator = LinearInterpolator()
                addUpdateListener {
                    angle = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        } else {
            animator?.cancel()
            animator = null
        }
    }

    override fun onDetachedFromWindow() {
        setSpinning(false)
        super.onDetachedFromWindow()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        buildPath(w, h)
        updateShaderMatrix()
    }

    private fun buildPath(w: Int, h: Int) {
        path.reset()
        val cx = w / 2f
        val cy = h / 2f
        val r = min(w, h) / 2f
        val lobes = 9
        val steps = 180
        for (i in 0..steps) {
            val t = (i.toDouble() / steps) * Math.PI * 2
            val rr = r * (0.93 + 0.07 * cos(lobes * t))
            val x = cx + (rr * cos(t)).toFloat()
            val y = cy + (rr * sin(t)).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
    }

    private fun updateShaderMatrix() {
        val b = bitmap ?: return
        val shader = paint.shader ?: return
        if (width == 0 || height == 0) return
        val scale = maxOf(width.toFloat() / b.width, height.toFloat() / b.height)
        matrix.reset()
        matrix.setScale(scale, scale)
        matrix.postTranslate((width - b.width * scale) / 2f, (height - b.height * scale) / 2f)
        shader.setLocalMatrix(matrix)
    }

    override fun onDraw(canvas: Canvas) {
        canvas.save()
        canvas.rotate(angle, width / 2f, height / 2f)
        if (bitmap != null) {
            canvas.drawPath(path, paint)
        } else {
            canvas.drawPath(path, bg)
            // Nota musical simple como marcador.
            val s = min(width, height) / 100f
            canvas.drawCircle(width / 2f - 8 * s, height / 2f + 14 * s, 10 * s, note)
            canvas.drawRect(width / 2f, height / 2f - 26 * s, width / 2f + 4 * s, height / 2f + 14 * s, note)
            canvas.drawRect(width / 2f, height / 2f - 26 * s, width / 2f + 18 * s, height / 2f - 18 * s, note)
        }
        canvas.restore()
    }
}
