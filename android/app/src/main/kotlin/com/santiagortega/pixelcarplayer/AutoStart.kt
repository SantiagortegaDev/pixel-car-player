package com.santiagortega.pixelcarplayer

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothProfile
import android.companion.CompanionDeviceManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.IntentCompat

/**
 * v3 (celular): arranque/parada automática del transmisor (ahorro de batería).
 *
 * Disparadores:
 * - **Bluetooth**: [AutoStartReceiver] (ACL conectado/desconectado y A2DP) y, en API 31+,
 *   [CarPresenceService] (CompanionDeviceManager, presencia del dispositivo asociado).
 * - **Wi-Fi**: `registerNetworkCallback(request, PendingIntent)` hacia [AutoStartReceiver]: llega
 *   aunque la app no esté corriendo. El SSID solo es legible con ubicación concedida (y, con la app
 *   en segundo plano en Android 10+, con ubicación "todo el tiempo"); si no, se omite.
 *
 * Al conectar: si coincide una regla → [TransmitterService.startAuto]. Al desconectar el Bluetooth
 * del carro: detener tras `stopAfterMinutes` (0 = ya) salvo que otra regla siga coincidiendo.
 */
object AutoStart {
    private const val PREFS = "pcp_native"
    private const val KEY_RULES = "autostart_rules"
    private const val KEY_BT = "autostart_bt_connected"
    const val ACTION_WIFI = "com.santiagortega.pixelcarplayer.AUTOSTART_WIFI"
    private const val CHANNEL_ID = "pcp_autostart"
    const val TAP_NOTIFICATION_ID = 47330

    private fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(ctx: Context): AutoStartRules = AutoStartRules.fromJson(prefs(ctx).getString(KEY_RULES, null))

    fun save(ctx: Context, rules: AutoStartRules) {
        prefs(ctx).edit().putString(KEY_RULES, rules.toJson()).commit()
        LinkDiag.log(
            "auto: reglas ${if (rules.enabled) "activas" else "inactivas"} (bt ${rules.btAddresses.size}, " +
                "wifi ${rules.wifiSsids.size}, parar tras ${rules.stopAfterMinutes} min)"
        )
        sync(ctx, force = true)
    }

    /** Ajusta el vigía de Wi-Fi y la observación de CompanionDeviceManager a las reglas. */
    fun sync(ctx: Context, force: Boolean) {
        runCatching { syncWifiWatch(ctx, force) }.onFailure { Log.w(TAG, "syncWifiWatch failed", it) }
        runCatching { syncCdmObservation(ctx) }.onFailure { Log.w(TAG, "syncCdmObservation failed", it) }
    }

    // ------------------------------------------------------------------ Bluetooth

    @Synchronized
    private fun setBtConnected(ctx: Context, address: String, connected: Boolean) {
        val a = AutoStartRules.normMac(address) ?: return
        val cur = prefs(ctx).getStringSet(KEY_BT, emptySet()).orEmpty().toMutableSet()
        val changed = if (connected) cur.add(a) else cur.remove(a)
        if (changed) prefs(ctx).edit().putStringSet(KEY_BT, cur).apply()
    }

    private fun trackedBt(ctx: Context): Set<String> = prefs(ctx).getStringSet(KEY_BT, emptySet()).orEmpty()

    /** `BluetoothDevice.isConnected()` (API oculta; null si no se puede consultar). */
    @SuppressLint("MissingPermission")
    private fun isBtConnected(ctx: Context, address: String): Boolean? = try {
        if (!Bt.hasConnectPermission(ctx)) {
            null
        } else {
            val d = Bt.adapter(ctx)?.getRemoteDevice(address)
            d?.javaClass?.getMethod("isConnected")?.invoke(d) as? Boolean
        }
    } catch (_: Throwable) {
        null
    }

    /** Direcciones de las reglas que están conectadas ahora (consulta directa o lo registrado). */
    private fun connectedCarBt(ctx: Context, rules: AutoStartRules): List<String> {
        val tracked = trackedBt(ctx)
        return rules.btAddresses.filter { isBtConnected(ctx, it) ?: (it in tracked) }
    }

    @SuppressLint("MissingPermission")
    private fun btName(ctx: Context, address: String): String? = try {
        if (!Bt.hasConnectPermission(ctx)) null
        else Bt.adapter(ctx)?.bondedDevices?.firstOrNull { it.address.equals(address, true) }?.name
    } catch (_: Exception) {
        null
    }

    fun onBtEvent(ctx: Context, address: String, connected: Boolean, via: String) {
        setBtConnected(ctx, address, connected)
        val rules = load(ctx)
        if (!rules.enabled || !rules.hasBt(address)) return
        if (connected) {
            LinkDiag.log("auto: Bluetooth del carro conectado ($via ${address.takeLast(5)})")
            val svc = TransmitterService.instance
            if (svc != null) svc.cancelAutoStop() else TransmitterService.startAuto(ctx, "Bluetooth del carro")
            return
        }
        val svc = TransmitterService.instance ?: return
        if (matchesNow(ctx, rules)) {
            LinkDiag.log("auto: Bluetooth del carro desconectado ($via), pero otra regla sigue activa")
            return
        }
        if (rules.stopAfterMinutes <= 0) {
            LinkDiag.log("auto: Bluetooth del carro desconectado ($via) → se detiene el transmisor")
            TransmitterService.stop(ctx)
        } else {
            LinkDiag.log("auto: Bluetooth del carro desconectado ($via) → detener en ${rules.stopAfterMinutes} min")
            svc.scheduleAutoStop(rules.stopAfterMinutes * 60_000L)
        }
    }

    // ------------------------------------------------------------------ Wi-Fi

    fun currentSsid(ctx: Context): String? = try {
        AutoStartRules.unquoteSsid(WifiJoin.status(ctx)["ssid"] as? String)
    } catch (_: Exception) {
        null
    }

    private fun wifiPendingIntent(ctx: Context, create: Boolean): PendingIntent? {
        val i = Intent(ctx, AutoStartReceiver::class.java).setAction(ACTION_WIFI)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (!create) flags = flags or PendingIntent.FLAG_NO_CREATE
        // El sistema agrega EXTRA_NETWORK: debe ser mutable en API 31+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
        return PendingIntent.getBroadcast(ctx, 3, i, flags)
    }

    /** Con [force] re-registra aunque ya exista (reglas nuevas / arranque del equipo). */
    private fun syncWifiWatch(ctx: Context, force: Boolean) {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        val rules = load(ctx)
        val want = rules.enabled && rules.wifiSsids.isNotEmpty()
        val existing = wifiPendingIntent(ctx, create = false)
        if (existing != null && (!want || force)) {
            runCatching { cm.unregisterNetworkCallback(existing) }
            if (!want) existing.cancel()
        }
        if (!want || (existing != null && !force)) return
        val req = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) // el hotspot del carro no tiene
            .build()
        val pi = wifiPendingIntent(ctx, create = true) ?: return
        cm.registerNetworkCallback(req, pi)
        LinkDiag.log("auto: vigilando Wi-Fi ${rules.wifiSsids.joinToString()}")
    }

    fun onWifiAvailable(ctx: Context) {
        val rules = load(ctx)
        if (!rules.enabled || rules.wifiSsids.isEmpty()) return
        val ssid = currentSsid(ctx)
        if (ssid == null) {
            LinkDiag.throttled("auto-ssid", 10 * 60_000L) {
                "auto: Wi-Fi conectado pero el SSID no es legible (falta ubicación / ubicación en segundo plano)"
            }
            return
        }
        if (!rules.hasSsid(ssid)) return
        LinkDiag.log("auto: Wi-Fi del carro ($ssid)")
        val svc = TransmitterService.instance
        if (svc != null) svc.cancelAutoStop() else TransmitterService.startAuto(ctx, "Wi-Fi $ssid")
    }

    fun matchesNow(ctx: Context, rules: AutoStartRules = load(ctx)): Boolean =
        rules.matches(connectedCarBt(ctx, rules), if (rules.wifiSsids.isEmpty()) null else currentSsid(ctx))

    // ------------------------------------------------------------------ CompanionDeviceManager

    private fun cdm(ctx: Context): CompanionDeviceManager? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ctx.getSystemService(CompanionDeviceManager::class.java)
        } else {
            null
        }

    /** Direcciones asociadas a esta app (mayúsculas). */
    @Suppress("DEPRECATION")
    fun associatedAddresses(ctx: Context): Set<String> = try {
        val m = cdm(ctx)
        when {
            m == null -> emptySet()
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                m.myAssociations.mapNotNull { AutoStartRules.normMac(it.deviceMacAddress?.toString()) }.toSet()
            else -> m.associations.mapNotNull { AutoStartRules.normMac(it) }.toSet()
        }
    } catch (e: Exception) {
        emptySet()
    }

    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    private fun syncCdmObservation(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val m = cdm(ctx) ?: return
        val rules = load(ctx)
        for (a in associatedAddresses(ctx)) {
            try {
                if (rules.enabled && rules.hasBt(a)) m.startObservingDevicePresence(a)
                else m.stopObservingDevicePresence(a)
            } catch (e: Exception) {
                Log.d(TAG, "observe presence $a: ${e.message}")
            }
        }
    }

    /** Tras asociar en [CarAssociateActivity]: la dirección entra a las reglas y se observa. */
    fun onAssociated(ctx: Context, address: String) {
        val rules = load(ctx)
        val next = rules.withBt(address)
        if (next != rules) prefs(ctx).edit().putString(KEY_RULES, next.toJson()).commit()
        LinkDiag.log("auto: carro asociado con CompanionDeviceManager (${address.takeLast(5)})")
        sync(ctx, force = false)
    }

    // ------------------------------------------------------------------ status

    /** `getAutoStartStatus`. */
    fun status(ctx: Context): Map<String, Any?> {
        val rules = load(ctx)
        sync(ctx, force = false)
        val bt = connectedCarBt(ctx, rules)
        val ssid = currentSsid(ctx)
        val wifiMatch = rules.hasSsid(ssid)
        val running = TransmitterService.instance != null
        val reason = when {
            !rules.enabled -> "Inicio automático desactivado"
            bt.isNotEmpty() -> "Bluetooth del carro conectado"
            wifiMatch -> "Conectado al Wi-Fi del carro ($ssid)"
            rules.btAddresses.isEmpty() && rules.wifiSsids.isEmpty() -> "Sin reglas: elige el Bluetooth o el Wi-Fi del carro"
            rules.wifiSsids.isNotEmpty() && ssid == null && WifiJoin.status(ctx)["connected"] == true ->
                "Wi-Fi conectado pero sin permiso de ubicación para leer su nombre"
            else -> "El carro no está cerca"
        }
        return mapOf(
            "btCarConnected" to bt.isNotEmpty(),
            "btDevice" to bt.firstOrNull()?.let { btName(ctx, it) ?: it },
            "wifiSsid" to ssid,
            "matches" to ((bt.isNotEmpty() || wifiMatch) && rules.enabled),
            "transmitterRunning" to running,
            "reason" to reason,
            "associated" to associatedAddresses(ctx).toList(),
        )
    }

    // ------------------------------------------------------------------ fallback notification

    /**
     * Android 12+ puede negar iniciar un servicio en primer plano desde segundo plano
     * (ForegroundServiceStartNotAllowedException): se pide al usuario que toque una notificación
     * (iniciar desde el toque sí está permitido).
     */
    @SuppressLint("MissingPermission")
    fun postTapNotification(ctx: Context, reason: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = ctx.getSystemService(NotificationManager::class.java)
                if (nm != null && nm.getNotificationChannel(CHANNEL_ID) == null) {
                    nm.createNotificationChannel(
                        NotificationChannel(CHANNEL_ID, "Inicio automático", NotificationManager.IMPORTANCE_HIGH).apply {
                            description = "Avisa cuando Android no deja iniciar el transmisor solo"
                        }
                    )
                }
            }
            val intent = TransmitterService.autoIntent(ctx, fromTap = true)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(ctx, 4, intent, flags)
            } else {
                PendingIntent.getService(ctx, 4, intent, flags)
            }
            val n = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_pcp)
                .setContentTitle("Toca para transmitir al carro")
                .setContentText("Android no dejó iniciar el transmisor solo ($reason)")
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
                .setTimeoutAfter(30 * 60_000L)
                .build()
            NotificationManagerCompat.from(ctx).notify(TAP_NOTIFICATION_ID, n)
        } catch (e: Exception) {
            Log.w(TAG, "tap notification failed", e)
            LinkDiag.log("auto: no se pudo mostrar la notificación: ${LinkDiag.errClass(e)}")
        }
    }

    fun cancelTapNotification(ctx: Context) {
        runCatching { NotificationManagerCompat.from(ctx).cancel(TAP_NOTIFICATION_ID) }
    }

    /** Tras reiniciar el equipo: el registro de Bluetooth conectado ya no vale; re-registrar vigías. */
    fun onBoot(ctx: Context) {
        prefs(ctx).edit().remove(KEY_BT).apply()
        sync(ctx, force = true)
    }
}

/** Manifest: ACL/A2DP del Bluetooth, Wi-Fi (PendingIntent de [AutoStart]) y arranque del equipo. */
class AutoStartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val ctx = context.applicationContext
        try {
            when (intent?.action) {
                BluetoothDevice.ACTION_ACL_CONNECTED -> device(intent)?.let { AutoStart.onBtEvent(ctx, it, true, "ACL") }
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> device(intent)?.let { AutoStart.onBtEvent(ctx, it, false, "ACL") }
                BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED -> {
                    val addr = device(intent) ?: return
                    when (intent.getIntExtra(BluetoothProfile.EXTRA_STATE, -1)) {
                        BluetoothProfile.STATE_CONNECTED -> AutoStart.onBtEvent(ctx, addr, true, "A2DP")
                        BluetoothProfile.STATE_DISCONNECTED -> AutoStart.onBtEvent(ctx, addr, false, "A2DP")
                    }
                }
                AutoStart.ACTION_WIFI -> AutoStart.onWifiAvailable(ctx)
                Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> AutoStart.onBoot(ctx)
            }
        } catch (e: Exception) {
            Log.w(TAG, "AutoStartReceiver ${intent?.action} failed", e)
        }
    }

    private fun device(intent: Intent): String? = try {
        IntentCompat.getParcelableExtra(intent, BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)?.address
    } catch (_: Exception) {
        null
    }
}
