package com.santiagortega.pixelcarplayer

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import androidx.core.content.ContextCompat
import java.lang.reflect.Proxy
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor

/**
 * Estado de Bluetooth / Wi-Fi / hotspot del radio (`getConnectivityStatus`) y evento
 * `{type:'connectivity', ...}` cuando cambia (receivers + NetworkCallback, con antirrebote).
 */
object ConnectivityWatch {
    // Ids de perfil (algunos ocultos en el SDK público).
    private const val A2DP_SINK = 11
    private const val AVRCP_CONTROLLER = 12
    private const val HEADSET_CLIENT = 16
    private val PROFILES = linkedMapOf(
        BluetoothProfile.A2DP to "a2dp",
        A2DP_SINK to "a2dpSink",
        BluetoothProfile.HEADSET to "headset",
        HEADSET_CLIENT to "headsetClient",
        AVRCP_CONTROLLER to "avrcpController",
    )
    private val PROFILE_ACTIONS = listOf(
        "android.bluetooth.a2dp.profile.action.CONNECTION_STATE_CHANGED",
        "android.bluetooth.a2dp-sink.profile.action.CONNECTION_STATE_CHANGED",
        "android.bluetooth.headset.profile.action.CONNECTION_STATE_CHANGED",
        "android.bluetooth.headsetclient.profile.action.CONNECTION_STATE_CHANGED",
        "android.bluetooth.avrcp-controller.profile.action.CONNECTION_STATE_CHANGED",
    )
    private const val DEBOUNCE_MS = 500L

    private val proxies = ConcurrentHashMap<Int, BluetoothProfile>()
    private val requested = ConcurrentHashMap.newKeySet<Int>()
    private val unsupported = ConcurrentHashMap.newKeySet<Int>()
    /** Direcciones con ACL conectado según broadcasts (solo mientras se vigila). */
    private val aclConnected = ConcurrentHashMap<String, String>()

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var receiver: BroadcastReceiver? = null
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var softApCallback: Any? = null
    @Volatile private var softApClients: Int? = null
    @Volatile private var watching = false
    @Volatile private var lastEmitted: Map<String, Any?>? = null
    private lateinit var app: Context

    // ------------------------------------------------------------------ estado

    /** Bloqueante (lee ARP como respaldo de clientes): fuera del hilo principal. */
    fun status(ctx: Context): Map<String, Any?> {
        val c = ctx.applicationContext
        if (ensureProxies(c)) {
            // Primera vez: los proxies se conectan en unos ms; esperar un poco para no devolver vacío.
            val until = System.currentTimeMillis() + 700
            while (proxies.size < requested.size && System.currentTimeMillis() < until) Thread.sleep(50)
        }
        val adapter = Bt.adapter(c)
        val canBt = Bt.hasConnectPermission(c)
        val btEnabled = try { adapter?.isEnabled == true } catch (_: Exception) { false }

        val devices = LinkedHashMap<String, Pair<String, MutableSet<String>>>()
        @SuppressLint("MissingPermission")
        fun add(d: BluetoothDevice, profile: String) {
            val name = try { d.name } catch (_: SecurityException) { null } ?: d.address
            devices.getOrPut(d.address) { name to linkedSetOf() }.second += profile
        }
        if (btEnabled && canBt) {
            for ((id, label) in PROFILES) {
                val proxy = proxies[id] ?: continue
                try {
                    proxy.connectedDevices.orEmpty().forEach { add(it, label) }
                } catch (e: Exception) {
                    Log.d(TAG, "connectedDevices($label) failed: ${e.message}")
                }
            }
            // ACL: broadcasts recibidos + BluetoothDevice.isConnected() (oculto) de los emparejados.
            try {
                @SuppressLint("MissingPermission")
                val bonded = adapter?.bondedDevices.orEmpty()
                for (d in bonded) {
                    val acl = aclConnected.containsKey(d.address) || isConnectedHidden(d) == true
                    if (acl) add(d, "acl")
                }
            } catch (e: Exception) {
                Log.d(TAG, "bonded scan failed: ${e.message}")
            }
        }

        val wm = c.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val wifiEnabled = try { wm?.isWifiEnabled == true } catch (_: Exception) { false }
        val wifiConnected = wifiConnected(c)
        val ssid = if (wifiConnected) currentSsid(wm) else null
        val hotspotOn = try { Hotspot.isEnabled(c) } catch (_: Exception) { null }
        val clients = if (hotspotOn == true) {
            softApClients ?: NetUtils.neighborIps().size.takeIf { it > 0 }
        } else if (hotspotOn == false) 0 else null

        return mapOf(
            "btEnabled" to btEnabled,
            "btPermission" to canBt,
            "btDevices" to devices.map { (addr, v) ->
                mapOf("name" to v.first, "address" to addr, "profiles" to v.second.toList())
            },
            "wifiEnabled" to wifiEnabled,
            "wifiConnected" to wifiConnected,
            "wifiSsid" to ssid,
            "hotspotOn" to hotspotOn,
            "hotspotClients" to clients,
        )
    }

    private fun isConnectedHidden(d: BluetoothDevice): Boolean? = try {
        d.javaClass.getMethod("isConnected").invoke(d) as? Boolean
    } catch (_: Exception) {
        null
    }

    private fun wifiConnected(c: Context): Boolean = try {
        val cm = c.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        @Suppress("DEPRECATION")
        cm.allNetworks.any { n ->
            cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
    } catch (_: Exception) {
        false
    }

    @Suppress("DEPRECATION")
    private fun currentSsid(wm: WifiManager?): String? = try {
        val raw = wm?.connectionInfo?.ssid
        raw?.removeSurrounding("\"")?.takeIf { it.isNotBlank() && it != "<unknown ssid>" && it != "0x" }
    } catch (_: Exception) {
        null
    }

    /** Pide los proxies de perfil una sola vez (asíncronos; los no soportados devuelven false). */
    private fun ensureProxies(c: Context): Boolean {
        if (!Bt.hasConnectPermission(c)) return false
        val adapter = Bt.adapter(c) ?: return false
        var any = false
        for (id in PROFILES.keys) {
            if (id in unsupported || !requested.add(id)) continue
            try {
                val ok = adapter.getProfileProxy(c, object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                        proxies[profile] = proxy
                        schedule()
                    }

                    override fun onServiceDisconnected(profile: Int) {
                        proxies.remove(profile)
                        schedule()
                    }
                }, id)
                if (ok) any = true else {
                    Log.d(TAG, "profile ${PROFILES[id]} no soportado")
                    requested.remove(id)
                    unsupported += id
                }
            } catch (e: Exception) {
                Log.d(TAG, "getProfileProxy(${PROFILES[id]}) failed: ${e.message}")
                requested.remove(id)
                unsupported += id
            }
        }
        return any
    }

    // ------------------------------------------------------------------ vigilancia

    @Synchronized
    fun start(ctx: Context) {
        if (watching) {
            lastEmitted = null
            schedule()
            return
        }
        app = ctx.applicationContext
        watching = true
        lastEmitted = null
        thread = HandlerThread("pcp-connectivity").also { it.start() }
        handler = Handler(thread!!.looper)
        ensureProxies(app)

        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothDevice.ACTION_NAME_CHANGED)
            PROFILE_ACTIONS.forEach { addAction(it) }
            addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
            addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION)
            addAction("android.net.wifi.WIFI_AP_STATE_CHANGED")
        }
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                @Suppress("DEPRECATION")
                val dev = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                when (intent.action) {
                    BluetoothDevice.ACTION_ACL_CONNECTED -> dev?.address?.let { aclConnected[it] = it }
                    BluetoothDevice.ACTION_ACL_DISCONNECTED -> dev?.address?.let { aclConnected.remove(it) }
                    BluetoothAdapter.ACTION_STATE_CHANGED -> {
                        val st = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)
                        if (st == BluetoothAdapter.STATE_OFF) aclConnected.clear()
                        if (st == BluetoothAdapter.STATE_ON) {
                            unsupported.clear()
                            ensureProxies(app)
                        }
                    }
                }
                schedule()
            }
        }
        try {
            // Broadcasts del sistema: deben ser exportados para recibirlos.
            ContextCompat.registerReceiver(app, r, filter, ContextCompat.RECEIVER_EXPORTED)
            receiver = r
        } catch (e: Exception) {
            Log.w(TAG, "connectivity receiver failed", e)
        }

        try {
            val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = schedule()
                override fun onLost(network: Network) = schedule()
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = schedule()
            }
            cm.registerNetworkCallback(
                NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(), cb
            )
            netCallback = cb
        } catch (e: Exception) {
            Log.w(TAG, "connectivity network callback failed", e)
        }
        registerSoftApCallback(app)
        schedule()
    }

    @Synchronized
    fun stop(ctx: Context) {
        if (!watching) return
        watching = false
        val c = ctx.applicationContext
        receiver?.let { runCatching { c.unregisterReceiver(it) } }
        receiver = null
        netCallback?.let {
            runCatching { (c.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(it) }
        }
        netCallback = null
        unregisterSoftApCallback(c)
        handler?.removeCallbacksAndMessages(null)
        thread?.quitSafely()
        thread = null
        handler = null
        lastEmitted = null
    }

    private val emitRunnable = Runnable {
        if (!watching) return@Runnable
        try {
            val s = status(app)
            if (s != lastEmitted) {
                lastEmitted = s
                EventHub.post(mapOf("type" to "connectivity") + s)
            }
        } catch (e: Exception) {
            Log.w(TAG, "connectivity status failed", e)
        }
    }

    private fun schedule() {
        val h = handler ?: return
        if (!watching) return
        h.removeCallbacks(emitRunnable)
        h.postDelayed(emitRunnable, DEBOUNCE_MS)
    }

    // ------------------------------------------------------------------ clientes del hotspot (API 30+, oculto)

    /**
     * WifiManager.registerSoftApCallback(Executor, SoftApCallback) es @SystemApi: en la mayoría de los
     * equipos tira SecurityException (NETWORK_SETTINGS); algunos ROM de radios lo permiten. Si falla
     * se usa la cantidad de IPs vecinas (ARP) como respaldo.
     */
    private fun registerSoftApCallback(c: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val wm = c.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val iface = Class.forName("android.net.wifi.WifiManager\$SoftApCallback")
            val cb = Proxy.newProxyInstance(iface.classLoader, arrayOf(iface)) { proxy, m, args ->
                when (m.name) {
                    "onConnectedClientsChanged" -> {
                        val list = args?.lastOrNull { it is List<*> } as? List<*>
                        softApClients = list?.size
                        schedule()
                    }
                    "onStateChanged" -> schedule()
                    "hashCode" -> return@newProxyInstance System.identityHashCode(proxy)
                    "equals" -> return@newProxyInstance proxy === args?.getOrNull(0)
                    "toString" -> return@newProxyInstance "PcpSoftApCallback"
                }
                null
            }
            val exec = Executor { r -> handler?.post(r) }
            wm.javaClass.getMethod("registerSoftApCallback", Executor::class.java, iface).invoke(wm, exec, cb)
            softApCallback = cb
        } catch (e: Throwable) {
            Log.d(TAG, "registerSoftApCallback no disponible: ${(e.cause ?: e).javaClass.simpleName}")
            softApCallback = null
            softApClients = null
        }
    }

    private fun unregisterSoftApCallback(c: Context) {
        val cb = softApCallback ?: return
        try {
            val wm = c.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val iface = Class.forName("android.net.wifi.WifiManager\$SoftApCallback")
            wm.javaClass.getMethod("unregisterSoftApCallback", iface).invoke(wm, cb)
        } catch (_: Throwable) {
        }
        softApCallback = null
        softApClients = null
    }
}
