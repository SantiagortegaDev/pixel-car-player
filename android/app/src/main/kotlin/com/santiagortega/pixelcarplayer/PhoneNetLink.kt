package com.santiagortega.pixelcarplayer

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.SystemClock
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Lado celular del enlace v2 (CONTRACT §1 "v2 — enlace bidireccional"), sobre Wi-Fi:
 *
 * - **Beacon** `beacon` (UDP 47322) cada 2 s por un socket enlazado a cada red Wi-Fi
 *   (`Network.bindSocket`) hacia su broadcast y su gateway, más el envío por interfaz de siempre
 *   (cubre el hotspot propio, que no es un objeto [Network]).
 * - **Escucha** de `car_beacon` (UDP 47324) en un socket por red Wi-Fi y uno sin enlazar.
 * - **Marcador**: mientras no haya pantallas conectadas, marca TCP 47323 al gateway de cada red
 *   Wi-Fi, a las IPs de `car_beacon` y a la IP manual (`flutter.phone_car_ip`), en paralelo,
 *   timeout 3 s, backoff 1→10 s que se reinicia ante cambios de red y beacons nuevos.
 *
 * Motivo: en Android 10+ un Wi-Fi sin internet (el hotspot del carro) no es la red por defecto y
 * los sockets sin enlazar salen por datos móviles.
 */
class PhoneNetLink(
    private val ctx: Context,
    private val device: String,
    private val installId: String,
    /** true si hay ≥ 1 pantalla conectada (en cualquier sentido): no se marca. */
    private val hasClients: () -> Boolean,
    /** Conexión saliente lograda: el dueño la convierte en un cliente normal. */
    private val onDialed: (socket: Socket, ip: String, label: String) -> Unit,
) {
    companion object {
        private const val BEACON_INTERVAL_MS = 2_000L
        private const val CONNECT_TIMEOUT_MS = 3_000
        private const val BACKOFF_MIN_MS = 1_000L
        private const val BACKOFF_MAX_MS = 10_000L
        private const val CAR_BEACON_TTL_MS = 30_000L
        private const val BEACON_SUMMARY_MS = 60_000L
        /** v3: tras un cambio de red / caída, se considera "marcando activamente" este tiempo. */
        private const val ACTIVE_DIAL_WINDOW_MS = 2 * 60_000L
        const val PREF_FILE = "FlutterSharedPreferences"
        const val PREF_CAR_IP = "flutter.phone_car_ip"
    }

    data class Target(val ip: String, val port: Int, val network: Network?, val label: String)

    private data class SeenBeacon(
        val device: String, val id: String?, val port: Int, val network: Network?, val at: Long,
    )

    @Volatile private var running = false

    /**
     * v3 (batería): true mientras se marca al carro con chances reales (≤ 2 min desde un cambio de
     * red / caída de pantalla, o hay `car_beacon` reciente). El dueño toma el Wi-Fi lock solo así.
     */
    @Volatile var dialingActive = false
        private set
    @Volatile private var lastPokeAt = 0L
    private val threads = mutableListOf<Thread>()
    private val tracked = ConcurrentHashMap<Network, Long>()
    private val netDesc = ConcurrentHashMap<Network, String>()
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val carBeacons = ConcurrentHashMap<String, SeenBeacon>()
    @Suppress("PLATFORM_CLASS_MAPPED_TO_KOTLIN")
    private val wake = Object() // wait/notify
    private var poked = false // guarded by wake
    private val dialPool: ExecutorService = Executors.newCachedThreadPool { r ->
        Thread(r, "pcp-dial").apply { isDaemon = true }
    }
    private val lastDialResult = HashMap<String, Pair<String, Long>>() // dialer thread only

    /** Sockets por red: escucha de car_beacon y envío de beacons. Guardados por `this`. */
    private val listeners = HashMap<Network, DatagramSocket>()
    private val senders = HashMap<Network, DatagramSocket>()
    private var unboundListener: DatagramSocket? = null

    // beacon summary counters (beacon thread only)
    private val beaconOk = HashMap<String, Int>()
    private val beaconErr = HashMap<String, String>()
    private var lastSummaryAt = 0L

    // ------------------------------------------------------------------ lifecycle

    fun start() {
        if (running) return
        running = true
        lastPokeAt = SystemClock.elapsedRealtime()
        LinkDiag.log("enlace: inicio (id ${installId.take(8)})")
        registerCallback()
        spawn("pcp-beacon") { beaconLoop() }
        spawn("pcp-dialer") { dialLoop() }
        spawn("pcp-carbeacon") { unboundListenLoop() }
    }

    fun stop() {
        if (!running) return
        running = false
        dialingActive = false
        unregisterCallback()
        poke("stop")
        threads.forEach { it.interrupt() }
        threads.clear()
        synchronized(this) {
            (listeners.values + senders.values).forEach { runCatching { it.close() } }
            listeners.clear()
            senders.clear()
            unboundListener?.let { runCatching { it.close() } }
            unboundListener = null
        }
        dialPool.shutdownNow()
        LinkDiag.log("enlace: detenido")
    }

    private fun spawn(name: String, body: () -> Unit) {
        val t = Thread({
            try {
                body()
            } catch (_: InterruptedException) {
            } catch (e: Throwable) {
                Log.e(TAG, "$name crashed", e)
                LinkDiag.log("$name falló: ${LinkDiag.errClass(e)}")
            }
        }, name).apply { isDaemon = true }
        threads += t
        t.start()
    }

    /** Despierta al marcador y reinicia el backoff (cambios de red, beacons, cliente caído). */
    fun poke(reason: String) {
        lastPokeAt = SystemClock.elapsedRealtime()
        synchronized(wake) {
            poked = true
            wake.notifyAll()
        }
        Log.d(TAG, "dialer poke: $reason")
    }

    /** Espera [ms] o hasta un [poke]; true si lo despertó un poke. */
    private fun waitPoke(ms: Long): Boolean = synchronized(wake) {
        if (!poked && ms > 0) wake.wait(ms)
        val p = poked
        poked = false
        p
    }

    fun wifiNetworks(): List<WifiNets.NetInfo> = WifiNets.wifiNetworks(ctx, tracked.keys)

    fun trackedNetworks(): Collection<Network> = tracked.keys

    // ------------------------------------------------------------------ NetworkCallback

    private fun cm() = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    private fun registerCallback() {
        val cm = cm() ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                tracked[network] = SystemClock.elapsedRealtime()
                describe(cm, network, "disponible")
                poke("onAvailable")
            }

            override fun onLost(network: Network) {
                tracked.remove(network)
                val d = netDesc.remove(network) ?: network.toString()
                LinkDiag.log("red perdida: $d")
                synchronized(this@PhoneNetLink) {
                    listeners.remove(network)?.let { runCatching { it.close() } }
                    senders.remove(network)?.let { runCatching { it.close() } }
                }
                poke("onLost")
            }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                tracked.putIfAbsent(network, SystemClock.elapsedRealtime())
                if (describe(cm, network, "cambió")) poke("onLinkPropertiesChanged")
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                tracked.putIfAbsent(network, SystemClock.elapsedRealtime())
                describe(cm, network, "cambió")
            }
        }
        try {
            val req = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                // Sin esto solo coinciden redes con internet; el hotspot del carro no lo tiene.
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            cm.registerNetworkCallback(req, cb)
            callback = cb
        } catch (e: Exception) {
            Log.w(TAG, "registerNetworkCallback failed", e)
            LinkDiag.log("NetworkCallback no disponible: ${LinkDiag.errClass(e)}")
        }
    }

    private fun unregisterCallback() {
        val cb = callback ?: return
        callback = null
        try {
            cm()?.unregisterNetworkCallback(cb)
        } catch (_: Exception) {
        }
    }

    /** Registra la red si su descripción cambió; true si cambió. */
    private fun describe(cm: ConnectivityManager, n: Network, verb: String): Boolean {
        val info = WifiNets.info(cm, n, try { cm.activeNetwork } catch (_: Exception) { null }) ?: return false
        val d = "${info.iface ?: n} ip=${info.ip ?: "-"}/${info.prefix} gw=${info.gateway ?: "-"}" +
            (if (info.hasInternet) " internet" else " sin-internet") + (if (info.isDefault) " (default)" else "")
        val prev = netDesc.put(n, d)
        if (prev == d) return false
        LinkDiag.log("red Wi-Fi $verb: $d")
        return true
    }

    // ------------------------------------------------------------------ beacons out

    private fun sleepWhileRunning(ms: Long): Boolean = try {
        Thread.sleep(ms)
        running
    } catch (_: InterruptedException) {
        false
    }

    private fun beaconLoop() {
        val payload = LinkProtocol.beacon(device, installId).toByteArray(Charsets.UTF_8)
        var fallback: DatagramSocket? = null
        try {
            while (running) {
                val wifi = try {
                    wifiNetworks()
                } catch (e: Exception) {
                    emptyList()
                }
                syncSockets(wifi)
                for (n in wifi) sendBound(n, payload)
                // Respaldo: broadcast por interfaz + 255.255.255.255 sin enlazar (hotspot propio).
                try {
                    val s = fallback ?: DatagramSocket().also { it.broadcast = true; fallback = it }
                    for (addr in NetUtils.broadcastAddresses()) {
                        val key = "if ${addr.hostAddress}"
                        try {
                            s.send(DatagramPacket(payload, payload.size, addr, LinkProtocol.BEACON_PORT))
                            beaconOk.merge(key, 1, Int::plus)
                        } catch (e: Exception) {
                            beaconErr[key] = LinkDiag.errClass(e)
                        }
                    }
                } catch (e: Exception) {
                    runCatching { fallback?.close() }
                    fallback = null
                    beaconErr["respaldo"] = LinkDiag.errClass(e)
                }
                summarizeBeacons()
                if (!sleepWhileRunning(BEACON_INTERVAL_MS)) return
            }
        } finally {
            runCatching { fallback?.close() }
        }
    }

    private fun sendBound(n: WifiNets.NetInfo, payload: ByteArray) {
        val net = n.network ?: return
        val sock = synchronized(this) {
            senders[net] ?: try {
                DatagramSocket().also {
                    it.broadcast = true
                    net.bindSocket(it)
                    senders[net] = it
                }
            } catch (e: Exception) {
                beaconErr["${n.iface} socket"] = LinkDiag.errClass(e)
                null
            }
        } ?: return
        val dests = LinkedHashSet<String>()
        n.broadcast?.let { dests += it }
        n.gateway?.let { dests += it }
        for (d in dests) {
            val key = "${n.iface} $d"
            try {
                sock.send(DatagramPacket(payload, payload.size, InetAddress.getByName(d), LinkProtocol.BEACON_PORT))
                beaconOk.merge(key, 1, Int::plus)
            } catch (e: Exception) {
                beaconErr[key] = LinkDiag.errClass(e)
                if (e is java.net.SocketException && sock.isClosed) synchronized(this) { senders.remove(net) }
            }
        }
    }

    private fun summarizeBeacons() {
        val now = SystemClock.elapsedRealtime()
        if (lastSummaryAt != 0L && now - lastSummaryAt < BEACON_SUMMARY_MS) return
        lastSummaryAt = now
        if (beaconOk.isEmpty() && beaconErr.isEmpty()) return
        val ok = beaconOk.entries.joinToString(", ") { "${it.key}×${it.value}" }
        val err = beaconErr.entries.joinToString(", ") { "${it.key}: ${it.value}" }
        LinkDiag.log("beacons enviados: ${ok.ifEmpty { "ninguno" }}" + if (err.isNotEmpty()) " · errores: $err" else "")
        beaconOk.clear()
        beaconErr.clear()
    }

    // ------------------------------------------------------------------ car_beacon in

    private fun newListenSocket(): DatagramSocket {
        val s = DatagramSocket(null as SocketAddress?)
        try {
            s.reuseAddress = true
            s.broadcast = true
            s.bind(InetSocketAddress(LinkProtocol.CAR_BEACON_PORT))
        } catch (e: Exception) {
            s.close()
            throw e
        }
        return s
    }

    /** Abre/cierra los sockets por red para que coincidan con las redes Wi-Fi actuales. */
    private fun syncSockets(wifi: List<WifiNets.NetInfo>) {
        val want = wifi.mapNotNull { it.network }.toSet()
        val toStart = mutableListOf<Pair<Network, DatagramSocket>>()
        synchronized(this) {
            for (n in listeners.keys.toList()) {
                if (n !in want) listeners.remove(n)?.let { runCatching { it.close() } }
            }
            for (n in senders.keys.toList()) {
                if (n !in want) senders.remove(n)?.let { runCatching { it.close() } }
            }
            for (n in want) {
                if (n in listeners) continue
                try {
                    val s = newListenSocket()
                    try {
                        n.bindSocket(s)
                    } catch (e: Exception) {
                        s.close()
                        throw e
                    }
                    listeners[n] = s
                    toStart += n to s
                } catch (e: Exception) {
                    LinkDiag.throttled("listen-$n", 60_000) {
                        "escucha car_beacon en red $n falló: ${LinkDiag.errClass(e)}"
                    }
                }
            }
        }
        for ((n, s) in toStart) {
            LinkDiag.log("escuchando car_beacon :${LinkProtocol.CAR_BEACON_PORT} en ${netDesc[n] ?: n}")
            Thread({ listenLoop(s, n) }, "pcp-carbeacon-$n").apply { isDaemon = true }.start()
        }
    }

    private fun unboundListenLoop() {
        while (running) {
            try {
                val s = newListenSocket()
                synchronized(this) { unboundListener = s }
                listenLoop(s, null)
            } catch (e: Exception) {
                LinkDiag.throttled("listen-unbound", 60_000) {
                    "escucha car_beacon sin enlazar falló: ${LinkDiag.errClass(e)}"
                }
            }
            if (!sleepWhileRunning(5_000)) return
        }
    }

    private fun listenLoop(s: DatagramSocket, network: Network?) {
        val buf = ByteArray(2048)
        try {
            while (running && !s.isClosed) {
                val p = DatagramPacket(buf, buf.size)
                s.receive(p)
                val from = p.address as? Inet4Address ?: continue
                val text = String(p.data, p.offset, p.length, Charsets.UTF_8)
                onCarBeacon(from, text, network)
            }
        } catch (e: Exception) {
            if (running && !s.isClosed) Log.d(TAG, "car_beacon listener ended: ${e.message}")
        } finally {
            runCatching { s.close() }
            if (network != null) synchronized(this) {
                if (listeners[network] === s) listeners.remove(network)
            }
        }
    }

    private fun onCarBeacon(from: Inet4Address, text: String, network: Network?) {
        val b = LinkProtocol.parseCarBeacon(text) ?: return
        val ip = from.hostAddress ?: return
        if (b.id != null && b.id == installId) return
        val now = SystemClock.elapsedRealtime()
        val prev = carBeacons[ip]
        carBeacons[ip] = SeenBeacon(b.device, b.id, b.port, network ?: prev?.network, now)
        if (prev == null || now - prev.at > 10_000) {
            LinkDiag.log(
                "car_beacon de $ip:${b.port} (${b.device.ifEmpty { "?" }}, id ${b.id?.take(8) ?: "-"})" +
                    " por ${network?.let { netDesc[it] ?: it.toString() } ?: "socket sin enlazar"}"
            )
            if (!hasClients()) poke("car_beacon")
        }
    }

    // ------------------------------------------------------------------ dialer

    private fun manualIp(): String? = try {
        ctx.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE).getString(PREF_CAR_IP, null)
            ?.trim()?.takeIf { WifiNets.ipv4Bytes(it) != null }
    } catch (_: Exception) {
        null
    }

    /** Destinos actuales, sin repetir ni incluir IPs propias. */
    fun targets(): List<Target> {
        val wifi = wifiNetworks()
        val own = NetUtils.localIps().toSet()
        fun netFor(ip: String): Network? = wifi.firstOrNull { n ->
            n.network != null && n.ip != null && WifiNets.sameSubnet(ip, n.ip, n.prefix)
        }?.network

        val out = LinkedHashMap<String, Target>()
        fun add(t: Target) {
            if (t.ip in own) return
            out.putIfAbsent("${t.ip}:${t.port}", t)
        }
        for (n in wifi) n.gateway?.let { add(Target(it, LinkProtocol.CAR_TCP_PORT, n.network, "gateway ${n.iface}")) }
        val now = SystemClock.elapsedRealtime()
        for ((ip, b) in carBeacons.entries.toList()) {
            if (now - b.at > CAR_BEACON_TTL_MS) {
                carBeacons.remove(ip)
                continue
            }
            add(Target(ip, b.port, b.network ?: netFor(ip), "car_beacon"))
        }
        manualIp()?.let { add(Target(it, LinkProtocol.CAR_TCP_PORT, netFor(it), "manual")) }
        return out.values.toList()
    }

    private fun dialLoop() {
        var backoff = BACKOFF_MIN_MS
        while (running) {
            if (hasClients()) {
                dialingActive = false
                waitPoke(2_000)
                backoff = BACKOFF_MIN_MS
                continue
            }
            val targets = try {
                targets()
            } catch (e: Exception) {
                emptyList()
            }
            dialingActive = targets.isNotEmpty() && (
                SystemClock.elapsedRealtime() - lastPokeAt < ACTIVE_DIAL_WINDOW_MS ||
                    targets.any { it.label == "car_beacon" }
                )
            if (targets.isEmpty()) {
                LinkDiag.throttled("dial-none", 60_000) {
                    "marcar: sin destinos (ni gateway Wi-Fi, ni car_beacon, ni IP manual)"
                }
            } else {
                val won = dialAll(targets)
                if (won != null) {
                    backoff = BACKOFF_MIN_MS
                    val (sock, t) = won
                    if (!running || hasClients()) {
                        // Otra conexión llegó mientras marcábamos: esta sobra.
                        runCatching { sock.close() }
                    } else {
                        onDialed(sock, t.ip, t.label)
                    }
                    waitPoke(1_000)
                    continue
                }
            }
            if (waitPoke(backoff)) {
                backoff = BACKOFF_MIN_MS
            } else {
                backoff = (backoff * 2).coerceAtMost(BACKOFF_MAX_MS)
            }
        }
    }

    /** Marca todos los destinos en paralelo; devuelve la primera conexión lograda (las demás se cierran). */
    private fun dialAll(targets: List<Target>): Pair<Socket, Target>? {
        val winner = AtomicReference<Pair<Socket, Target>?>(null)
        val pending = AtomicInteger(targets.size)
        val done = CountDownLatch(1)
        val results = ConcurrentHashMap<Target, String>()
        for (t in targets) {
            try {
                dialPool.execute {
                    try {
                        val s = connect(t)
                        if (winner.compareAndSet(null, s to t)) {
                            results[t] = "ok"
                            done.countDown()
                        } else {
                            results[t] = "ok (sobra)"
                            runCatching { s.close() }
                        }
                    } catch (e: Exception) {
                        results[t] = LinkDiag.errClass(e)
                    } finally {
                        if (pending.decrementAndGet() == 0) done.countDown()
                    }
                }
            } catch (e: Exception) {
                if (pending.decrementAndGet() == 0) done.countDown() // pool shut down
            }
        }
        try {
            done.await(CONNECT_TIMEOUT_MS + 1_500L, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        val won = winner.get()
        val now = SystemClock.elapsedRealtime()
        for (t in targets) {
            val r = results[t] ?: if (won != null) "cancelado (otro ganó)" else "sin respuesta"
            val key = "${t.ip}:${t.port}"
            val prev = lastDialResult[key]
            // Registro sin inundar: cambios de resultado, o cada 60 s si se repite.
            if (prev == null || prev.first != r || now - prev.second >= 60_000 || r == "ok") {
                lastDialResult[key] = r to now
                val via = t.network?.let { netDesc[it] ?: it.toString() } ?: "sin enlazar"
                LinkDiag.log("marcar $key (${t.label}, $via) → $r")
            }
        }
        return won
    }

    private fun connect(t: Target): Socket {
        val s = Socket()
        try {
            t.network?.bindSocket(s)
            s.tcpNoDelay = true
            s.keepAlive = true
            s.connect(InetSocketAddress(t.ip, t.port), CONNECT_TIMEOUT_MS)
            s.soTimeout = 0 // lectura bloqueante: la caída la detecta la regla de 30 s sin datos
            return s
        } catch (e: Exception) {
            runCatching { s.close() }
            throw e
        }
    }
}
