package com.santiagortega.pixelcarplayer

import android.Manifest
import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.annotation.RequiresApi
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit

/**
 * Car side: the head unit's own Wi-Fi hotspot, so the phone can join it.
 *
 * Every privileged path is reflection on hidden/system APIs and may be blocked by the ROM; nothing
 * here throws to the caller. Order for [setEnabled]: tethering (ConnectivityManager binder ≤ Q,
 * ConnectivityManager callback if it is an interface, TetheringManager R+) → WifiManager
 * setWifiApEnabled → LocalOnlyHotspot ([startLocalOnly], needs runtime permissions, done by the
 * caller) → `needsSettings`.
 *
 * Blocking calls (polling up to [CONFIRM_MS]): call off the main thread.
 */
object Hotspot {
    private const val TETHERING_WIFI = 0
    private const val AP_DISABLING = 10
    private const val AP_DISABLED = 11
    private const val AP_ENABLING = 12
    private const val AP_ENABLED = 13
    private const val AP_FAILED = 14
    private const val CONFIRM_MS = 3_000L
    private const val LOH_TIMEOUT_MS = 8_000L

    private val main by lazy { Handler(Looper.getMainLooper()) }

    /** Active `WifiManager.LocalOnlyHotspotReservation` (typed Any so API 24/25 never resolve it). */
    @Volatile private var reservation: Any? = null
    /** Method that last turned the hotspot on successfully (for getHotspotState). */
    @Volatile private var lastMethod: String? = null

    data class Creds(val ssid: String?, val password: String?)

    private fun wifi(ctx: Context) =
        ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

    fun canWriteSettings(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.System.canWrite(ctx)

    // ------------------------------------------------------------------ state

    /** Raw `WIFI_AP_STATE_*` (10..14), or null when no source is readable. */
    fun apState(ctx: Context): Int? {
        if (reservation != null) return AP_ENABLED
        val wm = wifi(ctx) ?: return null
        HiddenApi.exempt()
        try {
            val s = WifiManager::class.java.getMethod("getWifiApState").invoke(wm) as? Int
            if (s != null && s in AP_DISABLING..AP_FAILED) return s
        } catch (e: Throwable) {
            Log.d(TAG, "getWifiApState unavailable: ${rootMessage(e)}")
        }
        try {
            val on = WifiManager::class.java.getMethod("isWifiApEnabled").invoke(wm) as? Boolean
            if (on != null) return if (on) AP_ENABLED else AP_DISABLED
        } catch (e: Throwable) {
            Log.d(TAG, "isWifiApEnabled unavailable: ${rootMessage(e)}")
        }
        // Last resort: a typical soft-AP interface that is up with an IPv4 address.
        return if (apInterfaceUp()) AP_ENABLED else null
    }

    private fun apInterfaceUp(): Boolean = try {
        NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().any { nif ->
            val name = nif.name ?: ""
            (name.startsWith("ap") || name.startsWith("swlan") || name.startsWith("softap")) &&
                runCatching { nif.isUp }.getOrDefault(false) &&
                nif.inetAddresses.toList().any { it is Inet4Address }
        }
    } catch (_: Exception) {
        false
    }

    fun isEnabled(ctx: Context): Boolean? = when (apState(ctx)) {
        null -> null
        AP_ENABLED, AP_ENABLING -> true
        else -> false
    }

    /**
     * `{enabled, ssid, password, configuredSsid, configuredPassword, method, canWriteSettings}`
     * (see CONTRACT §2). ssid/password = red activa (LocalOnly si hay reserva, si no la configurada).
     */
    fun state(ctx: Context): Map<String, Any?> {
        val enabled = isEnabled(ctx)
        val configured = configuredCredentials(ctx)
        val creds = reservationCreds() ?: configured
        val method = when {
            reservation != null -> "localOnly"
            enabled == true -> lastMethod ?: "system"
            enabled == null -> "unknown"
            else -> "none"
        }
        return mapOf(
            "enabled" to enabled,
            "ssid" to creds.ssid,
            "password" to creds.password,
            "configuredSsid" to configured.ssid,
            "configuredPassword" to configured.password,
            "method" to method,
            "canWriteSettings" to canWriteSettings(ctx),
        )
    }

    /** SSID/password of the active LocalOnlyHotspot, else of the configured system soft AP. */
    fun credentials(ctx: Context): Creds = reservationCreds() ?: configuredCredentials(ctx)

    private val SOFTAP_XML = listOf(
        "/data/misc/apexdata/com.android.wifi/WifiConfigStoreSoftAp.xml",
        "/data/misc/wifi/WifiConfigStoreSoftAp.xml",
    )
    private const val SOFTAP_CONF = "/data/misc/wifi/softap.conf"

    /**
     * SSID/clave del hotspot configurado en los Ajustes del equipo (el que usan tethering y
     * setWifiApEnabled; LocalOnly en cambio inventa una red). Fuentes en orden, completando los
     * campos que falten: getSoftApConfiguration → getWifiApConfiguration → archivos del sistema
     * (casi nunca legibles sin root; los errores se ignoran).
     */
    fun configuredCredentials(ctx: Context): Creds {
        var ssid: String? = null
        var pass: String? = null
        fun take(c: Creds?) {
            if (c == null) return
            if (ssid == null) ssid = c.ssid
            if (pass == null && c.ssid != null && (ssid == null || c.ssid == ssid)) pass = c.password
        }
        val wm = wifi(ctx)
        if (wm != null) {
            HiddenApi.exempt()
            take(runCatching {
                WifiManager::class.java.getMethod("getSoftApConfiguration").invoke(wm)?.let { softApCreds(it) }
            }.onFailure { Log.d(TAG, "getSoftApConfiguration denied: ${rootMessage(it)}") }.getOrNull())
            if (ssid == null || pass == null) {
                take(runCatching {
                    @Suppress("DEPRECATION")
                    (WifiManager::class.java.getMethod("getWifiApConfiguration").invoke(wm) as? WifiConfiguration)
                        ?.let {
                            @Suppress("DEPRECATION")
                            Creds(unquote(it.SSID), unquote(it.preSharedKey))
                        }
                }.onFailure { Log.d(TAG, "getWifiApConfiguration denied: ${rootMessage(it)}") }.getOrNull())
            }
        }
        if (ssid == null || pass == null) {
            for (path in SOFTAP_XML) {
                take(runCatching { parseSoftApXml(java.io.File(path).readText()) }.getOrNull())
            }
        }
        if (ssid == null || pass == null) {
            take(runCatching { parseSoftApConf(java.io.File(SOFTAP_CONF).readBytes()) }.getOrNull())
        }
        return Creds(ssid, pass)
    }

    /** SoftApConfiguration read reflectively (getSsid deprecated in 33, getWifiSsid hidden before). */
    private fun softApCreds(conf: Any): Creds {
        val cls = conf.javaClass
        val ssid = runCatching { cls.getMethod("getSsid").invoke(conf) as? String }.getOrNull()
            ?: runCatching { cls.getMethod("getWifiSsid").invoke(conf)?.toString() }.getOrNull()
                ?.let { decodeWifiSsid(it) }
        val pass = runCatching { cls.getMethod("getPassphrase").invoke(conf) as? String }.getOrNull()
        return Creds(unquote(ssid), unquote(pass))
    }

    /** `WifiSsid.toString()`: `"texto"` entre comillas, o hex si no es UTF-8. */
    fun decodeWifiSsid(s: String): String? {
        val t = s.trim()
        if (t.isEmpty()) return null
        if (t.length >= 2 && t.startsWith("\"") && t.endsWith("\"")) return unquote(t)
        if (t.length % 2 == 0 && t.matches(Regex("[0-9a-fA-F]+"))) {
            return runCatching {
                String(ByteArray(t.length / 2) { t.substring(it * 2, it * 2 + 2).toInt(16).toByte() }, Charsets.UTF_8)
            }.getOrNull()?.ifEmpty { null }
        }
        return t
    }

    /** `WifiConfigStoreSoftAp.xml` (Android 11+): `<string name="SSID">` / `WifiSsid` y `Passphrase`. */
    fun parseSoftApXml(xml: String): Creds {
        fun str(name: String): String? =
            Regex("""<string\s+name="$name"\s*>([^<]*)</string>""").find(xml)?.groupValues?.get(1)?.let(::xmlUnescape)
        val ssid = str("WifiSsid")?.let { decodeWifiSsid(it) } ?: str("SSID")?.let { unquote(it) }
        return Creds(ssid, unquote(str("Passphrase")))
    }

    private fun xmlUnescape(s: String) = s.replace("&quot;", "\"").replace("&apos;", "'")
        .replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")

    /**
     * `softap.conf` (WifiApConfigStore, Android 7–10): int versión, UTF ssid, [v≥2: int banda,
     * int canal], [v≥3: boolean oculto], int authType, [authType≠0: UTF clave].
     */
    fun parseSoftApConf(bytes: ByteArray): Creds? = try {
        java.io.DataInputStream(bytes.inputStream()).use { inp ->
            val version = inp.readInt()
            if (version !in 1..3) return null
            val ssid = inp.readUTF()
            if (version >= 2) {
                inp.readInt()
                inp.readInt()
            }
            if (version >= 3) inp.readBoolean()
            val auth = inp.readInt()
            val pass = if (auth != 0) inp.readUTF() else null
            Creds(unquote(ssid), unquote(pass))
        }
    } catch (_: Exception) {
        null
    }

    @SuppressLint("NewApi")
    private fun reservationCreds(): Creds? {
        val any = reservation ?: return null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val r = any as? WifiManager.LocalOnlyHotspotReservation ?: return null
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                softApCreds(r.softApConfiguration)
            } else {
                @Suppress("DEPRECATION")
                val c = r.wifiConfiguration
                @Suppress("DEPRECATION")
                Creds(unquote(c?.SSID), unquote(c?.preSharedKey))
            }
        } catch (e: Throwable) {
            Log.w(TAG, "LocalOnlyHotspot config unreadable", e)
            Creds(null, null)
        }
    }

    // ------------------------------------------------------------------ enable / disable

    private fun result(
        ok: Boolean,
        method: String,
        needsSettings: Boolean = false,
        creds: Creds = Creds(null, null),
        error: String? = null,
    ): Map<String, Any?> = mapOf(
        "ok" to ok,
        "method" to method,
        "needsSettings" to needsSettings,
        "ssid" to creds.ssid,
        "password" to creds.password,
        "error" to error,
    )

    /**
     * Tries the system (non local-only) paths. Returns the contract map; when enabling failed and
     * the caller may still try LocalOnlyHotspot, `method == "none"` and `ok == false`.
     */
    fun setEnabled(ctx: Context, enabled: Boolean): Map<String, Any?> {
        val r = setEnabledInner(ctx, enabled)
        LinkDiag.log(
            "hotspot ${if (enabled) "encender" else "apagar"} → ok=${r["ok"]} método=${r["method"]}" +
                (r["error"]?.let { " error=$it" } ?: "") + (r["ssid"]?.let { " ssid=$it" } ?: "")
        )
        return r
    }

    private fun setEnabledInner(ctx: Context, enabled: Boolean): Map<String, Any?> {
        HiddenApi.exempt()
        if (!enabled) return disable(ctx)

        reservationCreds()?.let { return result(true, "localOnly", creds = it) }
        // Ya encendido (por nosotros, por el sistema o por el usuario): no se toca nada.
        val st = apState(ctx)
        if (st == AP_ENABLED || st == AP_ENABLING) {
            return result(true, lastMethod ?: "none", creds = credentials(ctx))
        }

        val tetherAttempts = listOf<Pair<String, () -> Boolean?>>(
            "binder" to { tetherViaBinder(ctx, true) },
            "cmCallback" to { tetherViaConnectivityManager(ctx, true) },
            "tetheringManager" to { tetherViaTetheringManager(ctx, true) },
        )
        for ((name, attempt) in tetherAttempts) {
            val accepted = guarded("tethering/$name") { attempt() }
            LinkDiag.log("hotspot tethering/$name → ${accepted ?: "no disponible"}")
            if (accepted != true) continue
            if (confirm(ctx, true) != false) {
                lastMethod = "tethering"
                return result(true, "tethering", creds = credentials(ctx))
            }
        }

        val wifiWasOn = wifi(ctx)?.isWifiEnabled == true
        val apAccepted = guarded("wifiAp") { viaWifiAp(ctx, true) }
        LinkDiag.log("hotspot setWifiApEnabled → ${apAccepted ?: "no disponible"}")
        if (apAccepted == true && confirm(ctx, true) != false) {
            lastMethod = "wifiAp"
            return result(true, "wifiAp", creds = credentials(ctx))
        }
        if (apAccepted != null && wifiWasOn) restoreWifi(ctx)

        return result(false, "none", needsSettings = true, error = "systemPathsFailed")
    }

    private fun disable(ctx: Context): Map<String, Any?> {
        val hadReservation = reservation != null
        stopLocalOnly(ctx)
        if (hadReservation && confirm(ctx, false) != false) return result(true, "localOnly")
        if (apState(ctx).let { it == AP_DISABLED || it == AP_FAILED }) {
            lastMethod = null
            return result(true, "none")
        }
        val attempts = listOf<Pair<String, () -> Boolean?>>(
            "tethering" to { tetherViaBinder(ctx, false) },
            "tethering" to { tetherViaConnectivityManager(ctx, false) },
            "tethering" to { tetherViaTetheringManager(ctx, false) },
            "wifiAp" to { viaWifiAp(ctx, false) },
        )
        for ((method, attempt) in attempts) {
            val accepted = guarded("disable/$method") { attempt() } ?: continue
            if (accepted && confirm(ctx, false) != false) {
                lastMethod = null
                return result(true, method)
            }
        }
        return result(false, "none", needsSettings = true, error = "systemPathsFailed")
    }

    /** Polls the AP state. true = reached, false = state readable but not reached, null = unreadable. */
    private fun confirm(ctx: Context, enabled: Boolean): Boolean? {
        val deadline = SystemClock.uptimeMillis() + CONFIRM_MS
        var sawState = false
        while (true) {
            val s = apState(ctx)
            if (s != null) {
                sawState = true
                if (enabled && s == AP_ENABLED) return true
                if (!enabled && (s == AP_DISABLED || s == AP_FAILED)) return true
                if (enabled && s == AP_FAILED) return false
            }
            if (SystemClock.uptimeMillis() >= deadline) return if (sawState) false else null
            SystemClock.sleep(150)
        }
    }

    private inline fun guarded(what: String, block: () -> Boolean?): Boolean? = try {
        block()
    } catch (e: Throwable) {
        Log.i(TAG, "hotspot $what failed: ${rootMessage(e)}")
        null
    }

    /** ≤ Q: IConnectivityManager.startTethering(type, ResultReceiver, showUi, pkg) via binder. */
    private fun tetherViaBinder(ctx: Context, enabled: Boolean): Boolean? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) return null
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return null
        val field = ConnectivityManager::class.java.getDeclaredField("mService").apply { isAccessible = true }
        val svc = field.get(cm) ?: return null
        val name = if (enabled) "startTethering" else "stopTethering"
        val m = svc.javaClass.methods.firstOrNull { it.name == name } ?: return null
        if (!enabled) {
            m.invoke(svc, *fillArgs(m, ctx.packageName, null))
            return true
        }
        val latch = CountDownLatch(1)
        var code = Int.MIN_VALUE
        val receiver = object : ResultReceiver(main) {
            override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                code = resultCode
                latch.countDown()
            }
        }
        m.invoke(svc, *fillArgs(m, ctx.packageName, receiver))
        val answered = latch.await(CONFIRM_MS, TimeUnit.MILLISECONDS)
        if (answered && code != 0) Log.i(TAG, "startTethering (binder) error code $code")
        return !answered || code == 0 // 0 = TETHER_ERROR_NO_ERROR
    }

    /** Fills a hidden-method signature by parameter type (signatures differ across releases). */
    private fun fillArgs(m: Method, pkg: String, receiver: ResultReceiver?): Array<Any?> =
        m.parameterTypes.map { t ->
            when {
                t == Int::class.javaPrimitiveType || t == Int::class.javaObjectType -> TETHERING_WIFI
                t == Boolean::class.javaPrimitiveType || t == Boolean::class.javaObjectType -> false
                t == String::class.java -> pkg
                ResultReceiver::class.java.isAssignableFrom(t) -> receiver
                else -> null
            }
        }.toTypedArray()

    /**
     * ConnectivityManager.startTethering(int, boolean, OnStartTetheringCallback, Handler). On AOSP the
     * callback is an abstract class, which java.lang.reflect.Proxy cannot implement without bytecode
     * generation, so this only runs on ROMs where it is an interface.
     */
    private fun tetherViaConnectivityManager(ctx: Context, enabled: Boolean): Boolean? {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return null
        val cmCls = ConnectivityManager::class.java
        if (!enabled) {
            // Only meaningful where the binder path does not exist (R+ goes through TetheringManager).
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
            cmCls.getMethod("stopTethering", Int::class.javaPrimitiveType).invoke(cm, TETHERING_WIFI)
            return true
        }
        val cbCls = Class.forName("android.net.ConnectivityManager\$OnStartTetheringCallback")
        if (!cbCls.isInterface) return null
        val latch = CountDownLatch(1)
        var ok = true
        val cb = callbackProxy(cbCls) { name, _ ->
            if (name == "onTetheringFailed") ok = false
            if (name == "onTetheringStarted" || name == "onTetheringFailed") latch.countDown()
        }
        cmCls.getMethod(
            "startTethering", Int::class.javaPrimitiveType, Boolean::class.javaPrimitiveType, cbCls, Handler::class.java,
        ).invoke(cm, TETHERING_WIFI, false, cb, main)
        latch.await(CONFIRM_MS, TimeUnit.MILLISECONDS)
        return ok
    }

    /** R+: TetheringManager.startTethering(TetheringRequest, Executor, StartTetheringCallback). */
    private fun tetherViaTetheringManager(ctx: Context, enabled: Boolean): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val tmCls = Class.forName("android.net.TetheringManager")
        val tm = ctx.applicationContext.getSystemService("tethering") ?: return null
        if (!enabled) {
            tmCls.getMethod("stopTethering", Int::class.javaPrimitiveType).invoke(tm, TETHERING_WIFI)
            return true
        }
        val reqCls = Class.forName("android.net.TetheringManager\$TetheringRequest")
        val builderCls = Class.forName("android.net.TetheringManager\$TetheringRequest\$Builder")
        val builder = builderCls.getConstructor(Int::class.javaPrimitiveType).newInstance(TETHERING_WIFI)
        runCatching {
            builderCls.getMethod("setShouldShowEntitlementUi", Boolean::class.javaPrimitiveType).invoke(builder, false)
        }
        val request = builderCls.getMethod("build").invoke(builder)
        val cbCls = Class.forName("android.net.TetheringManager\$StartTetheringCallback")
        val latch = CountDownLatch(1)
        var error: Any? = null
        val cb = callbackProxy(cbCls) { name, args ->
            if (name == "onTetheringFailed") error = args?.getOrNull(0) ?: "?"
            if (name == "onTetheringStarted" || name == "onTetheringFailed") latch.countDown()
        }
        tmCls.getMethod("startTethering", reqCls, Executor::class.java, cbCls)
            .invoke(tm, request, Executor { it.run() }, cb)
        latch.await(CONFIRM_MS, TimeUnit.MILLISECONDS)
        if (error != null) Log.i(TAG, "TetheringManager error $error")
        return error == null
    }

    private fun callbackProxy(iface: Class<*>, onCall: (String, Array<out Any?>?) -> Unit): Any =
        Proxy.newProxyInstance(iface.classLoader, arrayOf(iface)) { proxy, method, args ->
            when (method.name) {
                "hashCode" -> System.identityHashCode(proxy)
                "equals" -> proxy === args?.getOrNull(0)
                "toString" -> "PcpTetheringCallback"
                else -> {
                    onCall(method.name, args)
                    null
                }
            }
        }

    /** Pre-O WifiManager.setWifiApEnabled(config, enabled); some OEM builds keep it working. */
    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    private fun viaWifiAp(ctx: Context, enabled: Boolean): Boolean? {
        val wm = wifi(ctx) ?: return null
        val m = WifiManager::class.java.getMethod(
            "setWifiApEnabled", WifiConfiguration::class.java, Boolean::class.javaPrimitiveType,
        )
        // Most chips cannot run STA and AP at once; apps may only toggle Wi-Fi up to API 28.
        if (enabled && wm.isWifiEnabled) runCatching { wm.isWifiEnabled = false }
        val r = m.invoke(wm, null, enabled) as? Boolean
        return r ?: true
    }

    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    private fun restoreWifi(ctx: Context) {
        runCatching { wifi(ctx)?.isWifiEnabled = true }
    }

    // ------------------------------------------------------------------ LocalOnlyHotspot

    /** Runtime permissions LocalOnlyHotspot needs on this release. */
    fun localOnlyPermissions(): List<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> listOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
            listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
        else -> emptyList()
    }

    private fun locationOn(ctx: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            (ctx.getSystemService(Context.LOCATION_SERVICE) as? LocationManager)?.isLocationEnabled ?: true
        } else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(ctx.contentResolver, Settings.Secure.LOCATION_MODE) !=
                Settings.Secure.LOCATION_MODE_OFF
        }
    } catch (_: Exception) {
        true
    }

    /**
     * Starts a LocalOnlyHotspot (API 26+, random SSID/password chosen by the system, no internet).
     * Must be called off the main thread, after [localOnlyPermissions] were requested.
     */
    @SuppressLint("MissingPermission")
    fun startLocalOnly(ctx: Context, permissionsGranted: Boolean): Map<String, Any?> {
        val r = startLocalOnlyInner(ctx, permissionsGranted)
        LinkDiag.log(
            "hotspot LocalOnly (red aleatoria) → ok=${r["ok"]}" + (r["error"]?.let { " error=$it" } ?: "") +
                (r["ssid"]?.let { " ssid=$it" } ?: "")
        )
        return r
    }

    private fun startLocalOnlyInner(ctx: Context, permissionsGranted: Boolean): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return result(false, "none", needsSettings = true, error = "unsupported")
        }
        reservationCreds()?.let { return result(true, "localOnly", creds = it) }
        if (!permissionsGranted) return result(false, "localOnly", needsSettings = true, error = "permissionDenied")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && !locationOn(ctx)) {
            return result(false, "localOnly", needsSettings = true, error = "locationOff")
        }
        val wm = wifi(ctx) ?: return result(false, "none", needsSettings = true, error = "noWifi")
        val app = ctx.applicationContext
        val latch = CountDownLatch(1)
        var failure: String? = null
        try {
            wm.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation?) {
                    reservation = r
                    if (r != null) HotspotKeeperService.start(app)
                    latch.countDown()
                }

                override fun onStopped() {
                    Log.i(TAG, "LocalOnlyHotspot stopped by the system")
                    reservation = null
                    HotspotKeeperService.stop(app)
                }

                override fun onFailed(reason: Int) {
                    failure = when (reason) {
                        WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL -> "noChannel"
                        WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE -> "incompatibleMode"
                        WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED -> "tetheringDisallowed"
                        else -> "generic"
                    }
                    latch.countDown()
                }
            }, main)
        } catch (e: Throwable) {
            Log.w(TAG, "startLocalOnlyHotspot threw", e)
            val err = if (e is SecurityException) "permissionDenied" else rootMessage(e)
            return result(false, "localOnly", needsSettings = true, error = err)
        }
        if (!latch.await(LOH_TIMEOUT_MS, TimeUnit.MILLISECONDS)) failure = failure ?: "timeout"
        val creds = reservationCreds()
        return if (creds != null) {
            lastMethod = "localOnly"
            result(true, "localOnly", creds = creds)
        } else {
            result(false, "localOnly", needsSettings = true, error = failure ?: "generic")
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun closeReservation(r: Any) {
        (r as? WifiManager.LocalOnlyHotspotReservation)?.close()
    }

    fun stopLocalOnly(ctx: Context) {
        val r = reservation ?: return
        reservation = null
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) closeReservation(r)
        } catch (e: Exception) {
            Log.w(TAG, "LocalOnlyHotspot close failed", e)
        }
        HotspotKeeperService.stop(ctx.applicationContext)
    }

    // ------------------------------------------------------------------ settings screens

    /** Opens the most specific hotspot screen this ROM has. */
    fun openSettings(ctx: Context) {
        val candidates = listOf(
            Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.TetherSettings")),
            Intent().setComponent(
                ComponentName("com.android.settings", "com.android.settings.Settings\$TetherSettingsActivity")
            ),
            Intent().setComponent(
                ComponentName("com.android.settings", "com.android.settings.Settings\$WifiTetherSettingsActivity")
            ),
            Intent("android.settings.TETHER_SETTINGS"),
            Intent(Settings.ACTION_WIRELESS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in candidates) {
            try {
                ctx.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (e: Exception) {
                Log.d(TAG, "hotspot settings candidate failed: ${intent.component ?: intent.action}: ${e.message}")
            }
        }
    }

    // ------------------------------------------------------------------ helpers

    fun unquote(s: String?): String? {
        if (s == null) return null
        val t = if (s.length >= 2 && s.startsWith("\"") && s.endsWith("\"")) s.substring(1, s.length - 1) else s
        return t.ifEmpty { null }
    }

    private fun rootMessage(e: Throwable): String {
        val c = (e as? InvocationTargetException)?.targetException ?: e.cause ?: e
        return "${c.javaClass.simpleName}: ${c.message}"
    }
}

/**
 * Hidden-API exemption for API 28–29 ("meta-reflection" on VMRuntime). Android 11 closed this hole,
 * so on R+ hidden methods are only reachable if the ROM relaxes the policy
 * (`settings put global hidden_api_policy 1`).
 */
internal object HiddenApi {
    @Volatile private var done = false

    fun exempt() {
        if (done) return
        done = true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || Build.VERSION.SDK_INT > Build.VERSION_CODES.Q) return
        try {
            val forName = Class::class.java.getDeclaredMethod("forName", String::class.java)
            val getDeclaredMethod = Class::class.java.getDeclaredMethod(
                "getDeclaredMethod", String::class.java, arrayOf<Class<*>>()::class.java,
            )
            val vmRuntime = forName.invoke(null, "dalvik.system.VMRuntime") as Class<*>
            val getRuntime = getDeclaredMethod.invoke(vmRuntime, "getRuntime", null) as Method
            val setExemptions = getDeclaredMethod.invoke(
                vmRuntime, "setHiddenApiExemptions", arrayOf<Class<*>>(Array<String>::class.java),
            ) as Method
            setExemptions.invoke(getRuntime.invoke(null), arrayOf("L"))
            Log.i(TAG, "hidden API exemption applied")
        } catch (e: Throwable) {
            Log.i(TAG, "hidden API exemption unavailable: ${e.message}")
        }
    }
}
