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
import android.support.v4.media.session.MediaControllerCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
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

/** One upcoming queue entry. v3: [id] = queueId, [art] = JPEG 96 px base64 (primeros 12). */
data class QueueEntry(val title: String, val artist: String, val id: Long? = null, val art: String? = null)

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
        /** The followed session's queue changed. */
        fun onQueueChanged() {}
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
    /** Carátulas de la cola (por URI): hilo aparte para no demorar la carátula principal. */
    private val queueArtLoader: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "pcp-qart").apply { isDaemon = true }
    }

    /** v3: MediaControllerCompat del controlador seguido (shuffle/repeat). Hilo [handler]. */
    private var compat: MediaControllerCompat? = null
    private var compatCb: MediaControllerCompat.Callback? = null
    private var lastActionsKey: String? = null

    /** queueId|título|artista → base64 ("" = sin carátula). LRU, solo hilo [handler]. */
    private val queueArt = object : LinkedHashMap<String, String>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>?) = size > 96
    }
    private val queueArtLoading = HashSet<String>()

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
        bindCompat(null)
        controller = null
        track = null
        art = null
        artUri = null
        artLoader.shutdownNow()
        queueArtLoader.shutdownNow()
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
        bindCompat(chosen)
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

        override fun onQueueChanged(queue: MutableList<MediaSession.QueueItem>?) {
            if (isCurrent()) listener.onQueueChanged()
        }

        override fun onSessionDestroyed() {
            callbacks.remove(c.sessionToken)?.let { (cc, cb) -> safeUnregister(cc, cb) }
            if (isCurrent()) {
                controller = null
                bindCompat(null)
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

    // ---------------------------------------------------------------- queue

    /** Upcoming tracks (after the active queue item if known, else whole queue), max [MAX_QUEUE_ITEMS]. */
    fun upcomingQueue(): List<QueueEntry> = try {
        val c = controller
        val queue = c?.queue
        if (c == null || queue == null) {
            emptyList()
        } else {
            val activeId = c.playbackState?.activeQueueItemId ?: MediaSession.QueueItem.UNKNOWN_ID.toLong()
            val idx = if (activeId == MediaSession.QueueItem.UNKNOWN_ID.toLong()) -1
            else queue.indexOfFirst { it?.queueId == activeId }
            queue.drop(idx + 1).mapNotNull { item ->
                val d = item?.description ?: return@mapNotNull null
                val title = d.title?.toString().orEmpty()
                val artist = d.subtitle?.toString().orEmpty()
                if (title.isBlank() && artist.isBlank()) null else Triple(item, title, artist)
            }.take(MAX_QUEUE_ITEMS).mapIndexed { i, (item, title, artist) ->
                val art = if (i < MAX_QUEUE_ART) queueArtFor(item, title, artist) else null
                QueueEntry(title, artist, item.queueId, art)
            }
        }
    } catch (e: Exception) {
        Log.w(TAG, "queue read failed", e)
        emptyList()
    }

    /** Carátula 96 px de un ítem de la cola (caché por queueId+título; URIs se cargan aparte). */
    private fun queueArtFor(item: MediaSession.QueueItem, title: String, artist: String): String? {
        val key = "${item.queueId}|$title|$artist"
        queueArt[key]?.let { return it.ifEmpty { null } }
        val d = item.description
        val bmp = try {
            d.iconBitmap
        } catch (_: Exception) {
            null
        }
        if (bmp != null) {
            val b64 = QueueArt.encode(bmp) ?: ""
            queueArt[key] = b64
            return b64.ifEmpty { null }
        }
        val uri = d.iconUri?.toString()?.takeIf { it.isNotBlank() }
        if (uri == null) {
            queueArt[key] = ""
            return null
        }
        if (queueArtLoading.add(key)) {
            try {
                queueArtLoader.execute {
                    val b64 = ArtUtils.loadUri(appContext, uri)?.let { QueueArt.encode(it) } ?: ""
                    handler.post {
                        queueArtLoading.remove(key)
                        if (!started) return@post
                        queueArt[key] = b64
                        if (b64.isNotEmpty()) listener.onQueueChanged()
                    }
                }
            } catch (e: Exception) {
                queueArtLoading.remove(key)
            }
        }
        return null
    }

    // ---------------------------------------------------------------- v3: compat / extras

    private fun bindCompat(c: MediaController?) {
        val old = compat
        val oldCb = compatCb
        if (old != null && oldCb != null) runCatching { old.unregisterCallback(oldCb) }
        compat = null
        compatCb = null
        lastActionsKey = null
        if (c == null) return
        try {
            val cc = MediaControllerCompat(appContext, MediaSessionCompat.Token.fromToken(c.sessionToken))
            val cb = object : MediaControllerCompat.Callback() {
                private fun changed() {
                    if (compat === cc) listener.onPlaybackChanged(playback())
                }

                override fun onShuffleModeChanged(shuffleMode: Int) = changed()
                override fun onRepeatModeChanged(repeatMode: Int) = changed()
                override fun onSessionReady() = changed()
            }
            cc.registerCallback(cb, handler)
            compat = cc
            compatCb = cb
        } catch (e: Exception) {
            Log.w(TAG, "MediaControllerCompat failed for ${c.packageName}", e)
        }
    }

    private fun customActions(st: PlaybackState?): List<Pair<String, String>> = try {
        st?.customActions.orEmpty().map { it.action.orEmpty() to (it.name?.toString() ?: "") }
    } catch (_: Exception) {
        emptyList()
    }

    /** Extras de `state` (v3) del controlador seguido. */
    fun extras(): StateExtras {
        val c = controller ?: return StateExtras(null, null, null, false, false, false)
        val cc = compat
        val sh = cc?.let { runCatching { it.shuffleMode }.getOrDefault(-1) } ?: -1
        val rp = cc?.let { runCatching { it.repeatMode }.getOrDefault(-1) } ?: -1
        val st = try {
            c.playbackState
        } catch (_: Exception) {
            null
        }
        val actions = st?.actions ?: 0L
        val custom = customActions(st)
        val like = MediaControls.detectLike(custom)
        logActions(c.packageName, custom, like)
        return StateExtras(
            shuffle = MediaControls.shuffleOf(sh),
            repeat = MediaControls.repeatOf(rp),
            liked = like.liked,
            canLike = like.canLike,
            canShuffle = (actions and PlaybackStateCompat.ACTION_SET_SHUFFLE_MODE) != 0L || sh != -1 ||
                MediaControls.findAction(custom, "shuffle") != null,
            canRepeat = (actions and PlaybackStateCompat.ACTION_SET_REPEAT_MODE) != 0L || rp != -1 ||
                MediaControls.findAction(custom, "repeat") != null,
        )
    }

    /** Registra en LinkDiag las acciones personalizadas cuando cambian (para afinar "me gusta"). */
    private fun logActions(pkg: String, custom: List<Pair<String, String>>, like: LikeInfo) {
        val key = pkg + custom.joinToString("|") { it.first }
        if (key == lastActionsKey) return
        lastActionsKey = key
        val list = custom.joinToString(", ") { (a, n) -> "$a ($n)" }.ifEmpty { "ninguna" }
        LinkDiag.log(
            "acciones personalizadas de $pkg: $list → me gusta: " +
                (like.likeAction ?: "-") + " / quitar: " + (like.unlikeAction ?: "-")
        )
    }

    // ---------------------------------------------------------------- transport

    /**
     * Executes a contract `cmd` action on the followed session. Returns false if no session.
     * v3: `shuffle` (alternar), `repeat` (off→all→one), `like` (acción personalizada), `skipToQueue`.
     */
    fun command(action: String, positionMs: Long?, queueId: Long? = null): Boolean {
        val c = controller ?: return false
        return try {
            when (action) {
                "shuffle" -> toggleShuffle(c)
                "repeat" -> cycleRepeat(c)
                "like" -> toggleLike(c)
                "skipToQueue" -> {
                    if (queueId == null) return false
                    c.transportControls.skipToQueueItem(queueId)
                    true
                }
                else -> execute(c, action, positionMs)
            }
        } catch (e: Exception) {
            Log.w(TAG, "command $action failed", e)
            LinkDiag.log("cmd $action falló: ${LinkDiag.errClass(e)}")
            false
        }
    }

    private fun toggleShuffle(c: MediaController): Boolean {
        val cc = compat
        val cur = cc?.let { runCatching { it.shuffleMode }.getOrDefault(-1) } ?: -1
        if (cc != null && cur != -1) {
            cc.transportControls.setShuffleMode(MediaControls.nextShuffle(cur))
            return true
        }
        MediaControls.findAction(customActions(c.playbackState), "shuffle")?.let {
            c.transportControls.sendCustomAction(it, null)
            return true
        }
        if (cc == null) return false
        cc.transportControls.setShuffleMode(PlaybackStateCompat.SHUFFLE_MODE_ALL)
        return true
    }

    private fun cycleRepeat(c: MediaController): Boolean {
        val cc = compat
        val cur = cc?.let { runCatching { it.repeatMode }.getOrDefault(-1) } ?: -1
        if (cc != null && cur != -1) {
            cc.transportControls.setRepeatMode(MediaControls.nextRepeat(cur))
            return true
        }
        MediaControls.findAction(customActions(c.playbackState), "repeat")?.let {
            c.transportControls.sendCustomAction(it, null)
            return true
        }
        if (cc == null) return false
        cc.transportControls.setRepeatMode(PlaybackStateCompat.REPEAT_MODE_ALL)
        return true
    }

    private fun toggleLike(c: MediaController): Boolean {
        val info = MediaControls.detectLike(customActions(c.playbackState))
        val action = info.actionToSend() ?: run {
            LinkDiag.log("cmd like: ${c.packageName} no expone acción de \"me gusta\"")
            return false
        }
        c.transportControls.sendCustomAction(action, null)
        return true
    }

    companion object {
        const val MAX_QUEUE_ITEMS = 20
        /** v3: carátulas solo para los primeros N ítems de la cola. */
        const val MAX_QUEUE_ART = 12

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
