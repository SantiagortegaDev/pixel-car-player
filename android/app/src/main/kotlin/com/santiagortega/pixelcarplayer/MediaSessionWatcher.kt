package com.santiagortega.pixelcarplayer

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Track metadata of the watched session. */
data class TrackMeta(
    val packageName: String,
    val title: String,
    val artist: String,
    val album: String,
    val durationMs: Long,
) {
    val isEmpty get() = title.isBlank() && artist.isBlank()
}

/** Playback snapshot; [positionMs] is the live (extrapolated) position at [capturedAt]. */
data class PlaybackSnap(
    val playing: Boolean,
    val positionMs: Long,
    val speed: Double,
    val stateCode: Int,
    val capturedAt: Long = SystemClock.elapsedRealtime(),
)

/**
 * Tracks the active media sessions (requires notification access) and follows the session of
 * [targetPackage] (or, when null, the first playing session, else the first one).
 *
 * All listener callbacks run on [handler]'s thread. Public methods should also be called on it,
 * except the read-only getters which are thread-safe enough for snapshots.
 */
class MediaSessionWatcher(
    context: Context,
    @Volatile var targetPackage: String?,
    private val handler: Handler,
    private val listener: Listener,
) {
    interface Listener {
        /** The followed session changed (null = none). Metadata/playback/art callbacks follow. */
        fun onSessionChanged(packageName: String?) {}
        fun onMetadataChanged(meta: TrackMeta?) {}
        fun onPlaybackChanged(snap: PlaybackSnap?) {}
        /** Album art for the current track changed (null = no art). */
        fun onArtChanged(art: Bitmap?) {}
        /** Notification access missing: sessions cannot be read (retried automatically). */
        fun onAccessDenied() {}
    }

    private val appContext = context.applicationContext
    private val sessionManager =
        appContext.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val component = MediaListenerService.componentName(appContext)
    private val artLoader: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "pcp-art").apply { isDaemon = true }
    }

    private var started = false
    private var listenerRegistered = false
    private val callbacks = HashMap<MediaSession.Token, Pair<MediaController, MediaController.Callback>>()

    @Volatile var controller: MediaController? = null
        private set
    @Volatile var track: TrackMeta? = null
        private set
    @Volatile var art: Bitmap? = null
        private set
    private var artUri: String? = null
    private var artGeneration = 0

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { list -> onSessions(list ?: emptyList()) }

    private val retryAccess = Runnable { start() }

    fun start() {
        started = true
        handler.removeCallbacks(retryAccess)
        try {
            if (!listenerRegistered) {
                sessionManager.addOnActiveSessionsChangedListener(sessionsListener, component, handler)
                listenerRegistered = true
            }
            onSessions(sessionManager.getActiveSessions(component))
        } catch (e: SecurityException) {
            Log.w(TAG, "No notification access yet; retrying in 3 s")
            listener.onAccessDenied()
            handler.postDelayed(retryAccess, 3000)
        } catch (e: Exception) {
            Log.e(TAG, "MediaSessionWatcher start failed", e)
            handler.postDelayed(retryAccess, 5000)
        }
    }

    fun stop() {
        started = false
        handler.removeCallbacks(retryAccess)
        if (listenerRegistered) {
            try {
                sessionManager.removeOnActiveSessionsChangedListener(sessionsListener)
            } catch (_: Exception) {
            }
            listenerRegistered = false
        }
        unregisterAll()
        controller = null
        track = null
        art = null
        artUri = null
        artLoader.shutdownNow()
    }

    /** Re-evaluates which session to follow (e.g. after [targetPackage] changed). */
    fun refresh() {
        if (!started) return
        try {
            onSessions(sessionManager.getActiveSessions(component))
        } catch (e: SecurityException) {
            listener.onAccessDenied()
        } catch (e: Exception) {
            Log.w(TAG, "refresh failed", e)
        }
    }

    // ---------------------------------------------------------------- sessions

    private fun onSessions(list: List<MediaController>) {
        if (!started) return
        // (Re)register a callback on every session so that, in "any app" mode, we notice when
        // another player starts playing.
        val tokens = list.map { it.sessionToken }.toSet()
        callbacks.keys.filter { it !in tokens }.forEach { key ->
            callbacks.remove(key)?.let { (c, cb) -> safeUnregister(c, cb) }
        }
        for (c in list) {
            val key = c.sessionToken
            if (callbacks.containsKey(key)) continue
            val cb = SessionCallback(c)
            try {
                c.registerCallback(cb, handler)
                callbacks[key] = c to cb
            } catch (e: Exception) {
                Log.w(TAG, "registerCallback failed for ${c.packageName}", e)
            }
        }
        select(callbacks.values.map { it.first })
    }

    private fun select(candidates: List<MediaController>) {
        val target = targetPackage
        val chosen = if (target != null) {
            candidates.firstOrNull { it.packageName == target }
        } else {
            candidates.firstOrNull { isPlaying(it.playbackState) } ?: run {
                // Keep following the current one if it is still alive, otherwise the first.
                val cur = controller
                candidates.firstOrNull { cur != null && it.sessionToken == cur.sessionToken }
                    ?: candidates.firstOrNull()
            }
        }
        val current = controller
        if (chosen?.sessionToken == current?.sessionToken) return
        controller = chosen
        Log.i(TAG, "Following session: ${chosen?.packageName}")
        listener.onSessionChanged(chosen?.packageName)
        updateMetadata(chosen?.metadata)
        listener.onPlaybackChanged(playback())
    }

    private fun unregisterAll() {
        callbacks.values.forEach { (c, cb) -> safeUnregister(c, cb) }
        callbacks.clear()
    }

    private fun safeUnregister(c: MediaController, cb: MediaController.Callback) {
        try {
            c.unregisterCallback(cb)
        } catch (_: Exception) {
        }
    }

    private inner class SessionCallback(private val c: MediaController) : MediaController.Callback() {
        private fun isCurrent() = controller?.sessionToken == c.sessionToken

        override fun onMetadataChanged(metadata: MediaMetadata?) {
            if (isCurrent()) updateMetadata(metadata)
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            if (isCurrent()) {
                listener.onPlaybackChanged(playback())
            }
            if (targetPackage == null && !isCurrent() && isPlaying(state)) {
                select(callbacks.values.map { it.first })
            }
        }

        override fun onSessionDestroyed() {
            callbacks.remove(c.sessionToken)?.let { (cc, cb) -> safeUnregister(cc, cb) }
            if (isCurrent()) {
                controller = null
                select(callbacks.values.map { it.first })
                if (controller == null) {
                    listener.onSessionChanged(null)
                    updateMetadata(null)
                    listener.onPlaybackChanged(null)
                }
            }
        }
    }

    // ---------------------------------------------------------------- metadata / art

    private fun updateMetadata(md: MediaMetadata?) {
        val c = controller
        val newTrack = if (md == null || c == null) null else TrackMeta(
            packageName = c.packageName,
            title = md.text(MediaMetadata.METADATA_KEY_TITLE)
                ?: md.text(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) ?: "",
            artist = md.text(MediaMetadata.METADATA_KEY_ARTIST)
                ?: md.text(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
                ?: md.text(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE) ?: "",
            album = md.text(MediaMetadata.METADATA_KEY_ALBUM) ?: "",
            durationMs = md.getLong(MediaMetadata.METADATA_KEY_DURATION).coerceAtLeast(0),
        )
        val trackChanged = newTrack != track
        if (trackChanged) {
            track = newTrack
            listener.onMetadataChanged(newTrack)
        }
        // Art is always (re)announced after a track change so listeners can attach it to the
        // new track, even when the bitmap/URI is the same as the previous track's.
        updateArt(md, force = trackChanged)
    }

    private fun updateArt(md: MediaMetadata?, force: Boolean) {
        val inline = md?.let {
            it.bitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                ?: it.bitmap(MediaMetadata.METADATA_KEY_ART)
                ?: it.bitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        }
        if (inline != null) {
            artGeneration++
            artUri = null
            if (inline !== art || force) {
                art = inline
                listener.onArtChanged(inline)
            }
            return
        }
        val uri = md?.let {
            it.text(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
                ?: it.text(MediaMetadata.METADATA_KEY_ART_URI)
                ?: it.text(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI)
        }?.takeIf { it.isNotBlank() }
        if (uri == null) {
            artGeneration++
            artUri = null
            if (art != null || force) {
                art = null
                listener.onArtChanged(null)
            }
            return
        }
        if (uri == artUri) { // already loaded / loading
            if (force && art != null) listener.onArtChanged(art)
            return
        }
        artUri = uri
        val generation = ++artGeneration
        // Clear stale art from the previous track while the new one loads.
        if (art != null || force) {
            art = null
            listener.onArtChanged(null)
        }
        try {
            artLoader.execute {
                val bmp = ArtUtils.loadUri(appContext, uri)
                handler.post {
                    if (started && generation == artGeneration && bmp != null) {
                        art = bmp
                        listener.onArtChanged(bmp)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "art loader rejected task", e)
        }
    }

    // ---------------------------------------------------------------- playback

    fun playback(): PlaybackSnap? {
        val c = controller ?: return null
        val st = c.playbackState ?: return PlaybackSnap(false, 0, 1.0, PlaybackState.STATE_NONE)
        return snapOf(st, track?.durationMs ?: 0)
    }

    // ---------------------------------------------------------------- transport

    /** Executes a contract `cmd` action on the followed session. Returns false if no session. */
    fun command(action: String, positionMs: Long?): Boolean {
        val c = controller ?: return false
        return execute(c, action, positionMs)
    }

    companion object {
        fun isPlaying(st: PlaybackState?): Boolean = when (st?.state) {
            PlaybackState.STATE_PLAYING,
            PlaybackState.STATE_BUFFERING,
            PlaybackState.STATE_FAST_FORWARDING,
            PlaybackState.STATE_REWINDING,
            PlaybackState.STATE_SKIPPING_TO_NEXT,
            PlaybackState.STATE_SKIPPING_TO_PREVIOUS,
            PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM,
            PlaybackState.STATE_CONNECTING -> true
            else -> false
        }

        fun snapOf(st: PlaybackState, durationMs: Long): PlaybackSnap {
            val now = SystemClock.elapsedRealtime()
            val playing = st.state == PlaybackState.STATE_PLAYING
            val speed = st.playbackSpeed.toDouble().let { if (it == 0.0 && playing) 1.0 else it }
            var pos = st.position
            if (playing && st.lastPositionUpdateTime > 0) {
                pos += ((now - st.lastPositionUpdateTime) * speed).toLong()
            }
            if (pos < 0) pos = 0
            if (durationMs > 0 && pos > durationMs) pos = durationMs
            return PlaybackSnap(
                playing = isPlaying(st),
                positionMs = pos,
                speed = if (speed == 0.0) 1.0 else speed,
                stateCode = st.state,
                capturedAt = now,
            )
        }

        fun execute(c: MediaController, action: String, positionMs: Long?): Boolean = try {
            val tc = c.transportControls
            when (action) {
                "play" -> tc.play()
                "pause" -> tc.pause()
                "toggle" -> if (isPlaying(c.playbackState)) tc.pause() else tc.play()
                "next" -> tc.skipToNext()
                "previous" -> tc.skipToPrevious()
                "seek" -> tc.seekTo((positionMs ?: 0).coerceAtLeast(0))
                else -> return false
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "transport $action failed", e)
            false
        }

        /** One-shot lookup: first playing session, else first. Null without notification access. */
        fun pickAny(context: Context): MediaController? = try {
            val mgr = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val list = mgr.getActiveSessions(MediaListenerService.componentName(context))
            list.firstOrNull { isPlaying(it.playbackState) } ?: list.firstOrNull()
        } catch (e: Exception) {
            null
        }

        private fun MediaMetadata.text(key: String): String? =
            try {
                getString(key)?.takeIf { it.isNotBlank() } ?: getText(key)?.toString()?.takeIf { it.isNotBlank() }
            } catch (_: Exception) {
                null
            }

        private fun MediaMetadata.bitmap(key: String): Bitmap? =
            try {
                getBitmap(key)
            } catch (_: Exception) {
                null
            }
    }
}
