package com.santiagortega.pixelcarplayer

import android.content.Context
import android.graphics.Bitmap
import android.media.AudioManager
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent

/**
 * Car side fallback: follows whatever media session is active on the head unit itself and emits
 * `localMedia` events (on change, and every second while playing).
 */
object LocalMediaWatch : MediaSessionWatcher.Listener {
    private const val PERIOD_MS = 1000L
    private const val COALESCE_MS = 50L

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    @Volatile private var watcher: MediaSessionWatcher? = null

    private var artSource: Bitmap? = null
    private var artJpeg: ByteArray? = null

    @Synchronized
    fun start(context: Context): Boolean {
        if (watcher != null) return true
        val t = HandlerThread("pcp-local-media").also { it.start() }
        val h = Handler(t.looper)
        thread = t
        handler = h
        val w = MediaSessionWatcher(context, null, h, this)
        watcher = w
        h.post {
            w.start()
            emitSoon()
            h.postDelayed(periodic, PERIOD_MS)
        }
        return MediaListenerService.hasAccess(context)
    }

    @Synchronized
    fun stop() {
        val w = watcher ?: return
        val h = handler
        watcher = null
        handler = null
        h?.removeCallbacksAndMessages(null)
        h?.post {
            w.stop()
            artSource = null
            artJpeg = null
        }
        thread?.quitSafely()
        thread = null
    }

    /** Executes [action] on the local session; falls back to media key events. */
    fun command(context: Context, action: String, positionMs: Long?): Boolean {
        val c = watcher?.controller ?: MediaSessionWatcher.pickAny(context)
        if (c != null && MediaSessionWatcher.execute(c, action, positionMs)) return true
        val key = when (action) {
            "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "toggle" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> return false
        }
        return try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val now = SystemClock.uptimeMillis()
            am.dispatchMediaKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, key, 0))
            am.dispatchMediaKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_UP, key, 0))
            true
        } catch (e: Exception) {
            Log.w(TAG, "media key dispatch failed", e)
            false
        }
    }

    // ---- listener (watcher thread)

    override fun onSessionChanged(packageName: String?) = emitSoon()
    override fun onMetadataChanged(meta: TrackMeta?) = emitSoon()
    override fun onPlaybackChanged(snap: PlaybackSnap?) = emitSoon()
    override fun onArtChanged(art: Bitmap?) = emitSoon()

    private val emitRunnable = Runnable { emit() }

    private val periodic = object : Runnable {
        override fun run() {
            val w = watcher ?: return
            if (w.playback()?.playing == true) emit()
            handler?.postDelayed(this, PERIOD_MS)
        }
    }

    private fun emitSoon() {
        val h = handler ?: return
        h.removeCallbacks(emitRunnable)
        h.postDelayed(emitRunnable, COALESCE_MS)
    }

    private fun emit() {
        val w = watcher ?: return
        val c = w.controller
        val t = w.track
        val p = w.playback()
        val bmp = w.art
        if (bmp !== artSource) {
            artSource = bmp
            artJpeg = bmp?.let { ArtUtils.toJpeg(it) }
        }
        EventHub.post(
            mapOf(
                "type" to "localMedia",
                "package" to c?.packageName,
                "title" to (t?.title ?: ""),
                "artist" to (t?.artist ?: ""),
                "album" to (t?.album ?: ""),
                "durationMs" to (t?.durationMs ?: 0L),
                "playing" to (p?.playing ?: false),
                "positionMs" to (p?.positionMs ?: 0L),
                "art" to artJpeg,
            )
        )
    }
}
