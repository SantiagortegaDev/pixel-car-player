package com.santiagortega.pixelcarplayer

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothServerSocket
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.Closeable
import java.io.InputStream
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Phone side: foreground service that follows the music session and streams it to the car
 * screen over TCP (Wi-Fi) and RFCOMM (Bluetooth), plus a UDP discovery beacon.
 *
 * Threading: all session/link state lives on the `pcp-tx` HandlerThread ([worker]). Sockets have
 * their own threads (accept loops, one reader + one writer per client, beacon).
 */
class TransmitterService : Service(), MediaSessionWatcher.Listener {

    companion object {
        private const val ACTION_START = "com.santiagortega.pixelcarplayer.TX_START"
        private const val ACTION_STOP = "com.santiagortega.pixelcarplayer.TX_STOP"
        private const val EXTRA_SOURCE = "sourcePackage"
        private const val EXTRA_ANY = "anySource"
        private const val CHANNEL_ID = "pcp_transmitter"
        private const val NOTIFICATION_ID = 47321
        private const val PREFS = "pcp_native"
        const val DEFAULT_SOURCE = "com.spotify.music"

        private const val PING_INTERVAL_MS = 10_000L
        private const val CLIENT_TIMEOUT_MS = 30_000L
        private const val STATE_INTERVAL_MS = 5_000L
        private const val BEACON_INTERVAL_MS = 2_000L
        private const val MAX_QUEUE = 256

        @Volatile
        var instance: TransmitterService? = null
            private set

        /** Starts (or retargets) the service. [sourcePackage] null = any music app. */
        fun start(context: Context, sourcePackage: String?): Boolean = try {
            val intent = Intent(context, TransmitterService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_ANY, sourcePackage == null)
                .putExtra(EXTRA_SOURCE, sourcePackage)
            ContextCompat.startForegroundService(context, intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Cannot start TransmitterService", e)
            false
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, TransmitterService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "stopService failed", e)
            }
        }

        fun status(): Map<String, Any?> = instance?.lastStatus ?: idleStatus()

        private fun idleStatus(): Map<String, Any?> = mapOf(
            "type" to "transmitterStatus",
            "running" to false,
            "port" to LinkProtocol.TCP_PORT,
            "ips" to NetUtils.localIps(),
            "clients" to emptyList<Map<String, Any?>>(),
            "session" to null,
            "lyricsStatus" to "none",
        )
    }

    // ------------------------------------------------------------------ fields

    @Volatile private var running = false
    private lateinit var workerThread: HandlerThread
    private lateinit var worker: Handler
    private lateinit var watcher: MediaSessionWatcher
    private val lyricsExec: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "pcp-lyrics").apply { isDaemon = true }
    }
    private val threads = mutableListOf<Thread>()
    @Volatile private var tcpServer: ServerSocket? = null
    @Volatile private var btServer: BluetoothServerSocket? = null
    private val clients = CopyOnWriteArrayList<Client>()

    private var sourcePackage: String? = DEFAULT_SOURCE

    // worker-thread state
    private var currentId: String? = null
    private var currentTrack: TrackMeta? = null
    private var trackMsg: String? = null
    private var artMsg: String? = null
    private var artBitmap: Bitmap? = null
    private var artHash: Int? = null
    private var lyricsMsg: String? = null
    private var lyricsStatus = "none"
    private var lyricsTransient = false
    private var lyricsPendingId: String? = null
    private var lastState: PlaybackSnap? = null
    private var lastStateSentAt = 0L
    private var lastPingAt = 0L
    private var lastIpsCheckAt = 0L
    private var lastIps: List<String> = emptyList()

    @Volatile var lastStatus: Map<String, Any?>? = null
        private set

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    // ------------------------------------------------------------------ lifecycle

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        workerThread = HandlerThread("pcp-tx").also { it.start() }
        worker = Handler(workerThread.looper)
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        sourcePackage = if (prefs.getBoolean("tx_any", false)) null
        else prefs.getString("tx_source", DEFAULT_SOURCE)
        watcher = MediaSessionWatcher(this, sourcePackage, worker, this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!goForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_START) {
            val any = intent.getBooleanExtra(EXTRA_ANY, false)
            val src = if (any) null else (intent.getStringExtra(EXTRA_SOURCE) ?: DEFAULT_SOURCE)
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putBoolean("tx_any", src == null).putString("tx_source", src).apply()
            if (src != sourcePackage) {
                sourcePackage = src
                worker.post {
                    watcher.targetPackage = src
                    watcher.refresh()
                    emitStatus()
                }
            }
        }
        if (!running) startEverything()
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "TransmitterService stopping")
        running = false
        instance = null
        try {
            tcpServer?.close()
        } catch (_: Exception) {
        }
        try {
            btServer?.close()
        } catch (_: Exception) {
        }
        threads.forEach { it.interrupt() }
        threads.clear()
        clients.forEach { it.close("service stopped") }
        clients.clear()
        lyricsExec.shutdownNow()
        worker.removeCallbacksAndMessages(null)
        worker.post { watcher.stop() }
        workerThread.quitSafely()
        releaseLocks()
        EventHub.post(idleStatus())
        super.onDestroy()
    }

    private fun startEverything() {
        Log.i(TAG, "TransmitterService starting (source=${sourcePackage ?: "any"})")
        running = true
        acquireLocks()
        worker.post {
            watcher.start()
            emitStatus()
        }
        worker.postDelayed(tick, 1000)
        spawn("pcp-tcp-server") { tcpLoop() }
        spawn("pcp-rfcomm-server") { rfcommLoop() }
        spawn("pcp-beacon") { beaconLoop() }
    }

    private fun spawn(name: String, body: () -> Unit) {
        val t = Thread({
            try {
                body()
            } catch (e: Throwable) {
                Log.e(TAG, "$name crashed", e)
            }
        }, name).apply { isDaemon = true }
        threads += t
        t.start()
    }

    // ------------------------------------------------------------------ foreground / notification

    private fun goForeground(): Boolean = try {
        createChannel()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(0), type)
        true
    } catch (e: Exception) {
        Log.e(TAG, "startForeground failed", e)
        false
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Transmisor al carro", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Mantiene la conexión con la pantalla del carro"
                setShowBadge(false)
            }
        )
    }

    private fun pendingFlags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

    private fun buildNotification(clientCount: Int): Notification {
        val stopIntent = PendingIntent.getService(
            this, 1, Intent(this, TransmitterService::class.java).setAction(ACTION_STOP), pendingFlags()
        )
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            pendingFlags()
        )
        val text = when (clientCount) {
            0 -> "Esperando la pantalla del carro…"
            1 -> "1 pantalla conectada"
            else -> "$clientCount pantallas conectadas"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_pcp)
            .setContentTitle("Transmitiendo a la pantalla del carro")
            .setContentText(text)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(0, "Detener", stopIntent)
            .build()
    }

    @SuppressLint("MissingPermission")
    private fun updateNotification(clientCount: Int) {
        try {
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, buildNotification(clientCount))
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted: the service keeps running anyway.
        } catch (e: Exception) {
            Log.w(TAG, "notify failed", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PixelCarPlayer:tx").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.w(TAG, "wake lock failed", e)
        }
        try {
            val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "PixelCarPlayer:tx").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.w(TAG, "wifi lock failed", e)
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (_: Exception) {
        }
        try {
            wifiLock?.takeIf { it.isHeld }?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        wifiLock = null
    }

    // ------------------------------------------------------------------ media callbacks (worker)

    override fun onSessionChanged(packageName: String?) {
        emitStatus()
    }

    override fun onMetadataChanged(meta: TrackMeta?) {
        if (meta == null || meta.isEmpty) {
            currentId = null
            currentTrack = null
            trackMsg = null
            artMsg = null
            artBitmap = null
            artHash = null
            lyricsMsg = null
            lyricsStatus = "none"
            lyricsTransient = false
            emitStatus()
            return
        }
        val id = LinkProtocol.trackId(meta.title, meta.artist, meta.album, meta.durationMs)
        currentTrack = meta
        if (id == currentId) {
            emitStatus()
            return
        }
        currentId = id
        trackMsg = LinkProtocol.track(id, meta)
        artMsg = null
        artBitmap = null
        artHash = null
        broadcast(trackMsg!!)
        // Art follows via onArtChanged (the watcher always re-announces it after a track change).
        sendStateIfChanged(force = true)
        requestLyrics(id, meta)
        emitStatus()
    }

    override fun onArtChanged(art: Bitmap?) {
        handleArt(art)
    }

    override fun onPlaybackChanged(snap: PlaybackSnap?) {
        val wasPlaying = lastState?.playing
        sendStateIfChanged(force = false)
        if (lastState?.playing != wasPlaying) emitStatus()
    }

    private fun handleArt(bmp: Bitmap?) {
        val id = currentId ?: return
        if (bmp == null || bmp === artBitmap) return
        artBitmap = bmp
        val jpeg = ArtUtils.toJpeg(bmp) ?: return
        val hash = jpeg.contentHashCode()
        if (hash == artHash && artMsg != null) return
        artHash = hash
        artMsg = LinkProtocol.art(id, jpeg)
        broadcast(artMsg!!)
    }

    private fun currentStateMsg(): Pair<String, PlaybackSnap> {
        val snap = watcher.playback() ?: PlaybackSnap(false, 0, 1.0, 0)
        return LinkProtocol.state(snap.playing, snap.positionMs, snap.speed) to snap
    }

    private fun sendStateIfChanged(force: Boolean) {
        val (msg, snap) = currentStateMsg()
        val prev = lastState
        val changed = force || prev == null || prev.playing != snap.playing || prev.speed != snap.speed ||
            run {
                val expected = if (prev.playing) {
                    prev.positionMs + ((snap.capturedAt - prev.capturedAt) * prev.speed).toLong()
                } else {
                    prev.positionMs
                }
                kotlin.math.abs(expected - snap.positionMs) > 1500
            }
        if (!changed) return
        lastState = snap
        lastStateSentAt = SystemClock.elapsedRealtime()
        broadcast(msg)
    }

    // ------------------------------------------------------------------ lyrics (worker)

    private fun requestLyrics(id: String, meta: TrackMeta) {
        LyricsFetcher.cached(id)?.let {
            setLyrics(id, it)
            return
        }
        lyricsStatus = "loading"
        lyricsTransient = false
        lyricsMsg = LinkProtocol.lyrics(id, "loading", false, emptyList())
        broadcast(lyricsMsg!!)
        if (lyricsPendingId == id) return
        lyricsPendingId = id
        try {
            lyricsExec.execute {
                val result = LyricsFetcher.fetch(id, meta.title, meta.artist, meta.album, meta.durationMs)
                if (running) {
                    worker.post {
                        if (lyricsPendingId == id) lyricsPendingId = null
                        if (currentId == id) setLyrics(id, result)
                    }
                }
            }
        } catch (e: Exception) {
            lyricsPendingId = null
            Log.w(TAG, "lyrics executor rejected", e)
        }
    }

    private fun setLyrics(id: String, r: LyricsResult) {
        lyricsStatus = r.status
        lyricsTransient = r.transientError
        lyricsMsg = LinkProtocol.lyrics(id, r.status, r.synced, r.lines)
        broadcast(lyricsMsg!!)
        emitStatus()
    }

    private fun retryLyricsIfNeeded() {
        val id = currentId ?: return
        val meta = currentTrack ?: return
        if (lyricsTransient && lyricsPendingId == null) requestLyrics(id, meta)
    }

    // ------------------------------------------------------------------ periodic tick (worker)

    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            val now = SystemClock.elapsedRealtime()
            if (now - lastPingAt >= PING_INTERVAL_MS) {
                lastPingAt = now
                broadcast(LinkProtocol.ping())
            }
            for (c in clients) {
                if (now - c.lastRx > CLIENT_TIMEOUT_MS) c.close("timeout")
            }
            if (lastState?.playing == true && now - lastStateSentAt >= STATE_INTERVAL_MS) {
                sendStateIfChanged(force = true)
            }
            if (now - lastIpsCheckAt >= 5000) {
                lastIpsCheckAt = now
                val ips = NetUtils.localIps()
                if (ips != lastIps) {
                    lastIps = ips
                    emitStatus()
                }
            }
            worker.postDelayed(this, 1000)
        }
    }

    // ------------------------------------------------------------------ status

    private fun emitStatus() {
        val c = watcher.controller
        val t = currentTrack
        val session = c?.let {
            mapOf(
                "package" to it.packageName,
                "title" to (t?.title ?: ""),
                "artist" to (t?.artist ?: ""),
                "playing" to MediaSessionWatcher.isPlaying(it.playbackState),
            )
        }
        val status = mapOf(
            "type" to "transmitterStatus",
            "running" to running,
            "port" to LinkProtocol.TCP_PORT,
            "ips" to lastIps.ifEmpty { NetUtils.localIps().also { lastIps = it } },
            "clients" to clients.filter { !it.closed }.map {
                mapOf("device" to it.device, "transport" to it.transport, "address" to it.address)
            },
            "session" to session,
            "lyricsStatus" to lyricsStatus,
        )
        if (status == lastStatus) return
        val prevClients = (lastStatus?.get("clients") as? List<*>)?.size
        lastStatus = status
        EventHub.post(status)
        val n = (status["clients"] as List<*>).size
        if (n != prevClients) updateNotification(n)
    }

    // ------------------------------------------------------------------ clients

    private fun broadcast(line: String) {
        for (c in clients) c.send(line)
    }

    private fun sendSnapshot(c: Client) {
        trackMsg?.let { c.send(it) }
        artMsg?.let { c.send(it) }
        c.send(currentStateMsg().first)
        lyricsMsg?.let { c.send(it) }
    }

    /** Called from accept threads. */
    private fun addClient(c: Client) {
        if (!running) {
            c.close("not running")
            return
        }
        Log.i(TAG, "Client connected: ${c.transport} ${c.address}")
        c.start()
        worker.post {
            clients += c
            c.send(LinkProtocol.hello(Build.MODEL ?: "Android", watcher.controller?.packageName ?: sourcePackage ?: ""))
            sendSnapshot(c)
            retryLyricsIfNeeded()
            emitStatus()
        }
    }

    private fun onClientClosed(c: Client) {
        if (clients.remove(c)) {
            Log.i(TAG, "Client disconnected: ${c.transport} ${c.address}")
        }
        emitStatus()
    }

    private fun onLine(c: Client, line: String) {
        val msg = LinkProtocol.parse(line) ?: return
        when (msg.optString("t")) {
            "hello" -> {
                val dev = msg.optString("device", "")
                if (dev.isNotBlank()) c.device = dev
                emitStatus()
            }
            "cmd" -> handleCmd(msg)
            "resync" -> {
                sendSnapshot(c)
                retryLyricsIfNeeded()
            }
            "pong" -> Unit
            else -> Unit // unknown messages are ignored (CONTRACT §1)
        }
    }

    private fun handleCmd(msg: JSONObject) {
        val action = msg.optString("action")
        val pos = if (msg.has("positionMs")) msg.optLong("positionMs") else null
        val ok = watcher.command(action, pos)
        Log.d(TAG, "cmd $action -> $ok")
        // Optimistic: push a state update shortly after the player reacts.
        worker.postDelayed({ sendStateIfChanged(force = false) }, 300)
    }

    /** One connected screen (TCP or RFCOMM). */
    private inner class Client(
        val transport: String,
        val address: String,
        private val input: InputStream,
        private val output: OutputStream,
        private val closeable: Closeable,
    ) {
        @Volatile var device: String = address
        @Volatile var lastRx: Long = SystemClock.elapsedRealtime()
        @Volatile var closed = false
            private set
        private val queue = LinkedBlockingQueue<String>()
        private val poison = "\u0000"

        fun start() {
            Thread({ readLoop() }, "pcp-client-r-$address").apply { isDaemon = true }.start()
            Thread({ writeLoop() }, "pcp-client-w-$address").apply { isDaemon = true }.start()
        }

        fun send(line: String) {
            if (closed) return
            if (queue.size >= MAX_QUEUE) {
                close("send backlog")
                return
            }
            queue.offer(line)
        }

        private fun readLoop() {
            try {
                BufferedReader(InputStreamReader(input, Charsets.UTF_8)).use { reader ->
                    while (!closed) {
                        val line = reader.readLine() ?: break
                        lastRx = SystemClock.elapsedRealtime()
                        if (line.isBlank()) continue
                        worker.post { if (!closed) onLine(this, line) }
                    }
                }
            } catch (e: Exception) {
                if (!closed) Log.d(TAG, "read ended for $address: ${e.message}")
            }
            close("eof")
        }

        private fun writeLoop() {
            try {
                val out = output.buffered()
                while (!closed) {
                    val line = queue.poll(30, TimeUnit.SECONDS) ?: continue
                    if (line === poison || closed) break
                    out.write(line.toByteArray(Charsets.UTF_8))
                    out.write('\n'.code)
                    if (queue.isEmpty()) out.flush()
                }
            } catch (e: Exception) {
                if (!closed) Log.d(TAG, "write failed for $address: ${e.message}")
            }
            close("write error")
        }

        fun close(reason: String) {
            if (closed) return
            closed = true
            Log.d(TAG, "closing $transport $address: $reason")
            queue.clear()
            queue.offer(poison)
            try {
                closeable.close()
            } catch (_: Exception) {
            }
            if (running) worker.post { onClientClosed(this) }
        }
    }

    // ------------------------------------------------------------------ servers

    private fun sleepWhileRunning(ms: Long): Boolean = try {
        Thread.sleep(ms)
        running
    } catch (_: InterruptedException) {
        false
    }

    private fun tcpLoop() {
        while (running) {
            try {
                ServerSocket().use { ss ->
                    ss.reuseAddress = true
                    ss.bind(InetSocketAddress(LinkProtocol.TCP_PORT))
                    tcpServer = ss
                    Log.i(TAG, "TCP server listening on ${LinkProtocol.TCP_PORT}")
                    while (running) {
                        val s = ss.accept()
                        try {
                            s.tcpNoDelay = true
                            s.keepAlive = true
                            addClient(
                                Client(
                                    "wifi", s.inetAddress?.hostAddress ?: "?",
                                    s.getInputStream(), s.getOutputStream(), s,
                                )
                            )
                        } catch (e: Exception) {
                            Log.w(TAG, "accept setup failed", e)
                            try {
                                s.close()
                            } catch (_: Exception) {
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                if (!running) break
                Log.w(TAG, "TCP server failed, restarting in 2 s: ${e.message}")
            } finally {
                tcpServer = null
            }
            if (!sleepWhileRunning(2000)) break
        }
    }

    @SuppressLint("MissingPermission")
    private fun rfcommLoop() {
        while (running) {
            val adapter = Bt.adapter(this)
            if (adapter == null) {
                Log.i(TAG, "No Bluetooth adapter; RFCOMM server disabled")
                return
            }
            val usable = try {
                Bt.hasConnectPermission(this) && adapter.isEnabled
            } catch (_: Exception) {
                false
            }
            if (!usable) {
                if (!sleepWhileRunning(10_000)) break
                continue
            }
            try {
                val ss = adapter.listenUsingInsecureRfcommWithServiceRecord(LinkProtocol.RFCOMM_NAME, Bt.uuid)
                btServer = ss
                Log.i(TAG, "RFCOMM server listening")
                ss.use {
                    while (running) {
                        val s = it.accept() ?: continue
                        val addr = try {
                            s.remoteDevice?.address ?: "bt"
                        } catch (_: Exception) {
                            "bt"
                        }
                        try {
                            addClient(Client("bt", addr, s.inputStream, s.outputStream, s))
                        } catch (e: Exception) {
                            Log.w(TAG, "RFCOMM client setup failed", e)
                            try {
                                s.close()
                            } catch (_: Exception) {
                            }
                        }
                    }
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "RFCOMM listen denied: ${e.message}")
            } catch (e: Exception) {
                if (!running) break
                Log.w(TAG, "RFCOMM server failed: ${e.message}")
            } finally {
                btServer = null
            }
            if (!sleepWhileRunning(5000)) break
        }
    }

    private fun beaconLoop() {
        val device = Build.MODEL ?: "Android"
        val payload = LinkProtocol.beacon(device).toByteArray(Charsets.UTF_8)
        while (running) {
            try {
                DatagramSocket().use { sock ->
                    sock.broadcast = true
                    while (running) {
                        for (addr in NetUtils.broadcastAddresses()) {
                            try {
                                sock.send(DatagramPacket(payload, payload.size, addr, LinkProtocol.BEACON_PORT))
                            } catch (_: Exception) {
                                // e.g. ENETUNREACH on an interface going down; ignore
                            }
                        }
                        if (!sleepWhileRunning(BEACON_INTERVAL_MS)) return
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "beacon socket failed: ${e.message}")
            }
            if (!sleepWhileRunning(BEACON_INTERVAL_MS)) break
        }
    }
}
