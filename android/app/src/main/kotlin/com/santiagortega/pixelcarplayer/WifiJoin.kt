package com.santiagortega.pixelcarplayer

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.SupplicantState
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi

/** Phone side: make the phone join the car's hotspot on its own. Nothing is persisted here. */
object WifiJoin {

    private fun wifi(ctx: Context) =
        ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

    private fun result(ok: Boolean, method: String, error: String? = null) =
        mapOf("ok" to ok, "method" to method, "error" to error)

    /** `{ok, method: 'suggestion'|'legacy'|'none', error}` (see CONTRACT §2). */
    fun setAutoConnect(ctx: Context, ssid: String, password: String, enabled: Boolean): Map<String, Any?> {
        if (ssid.isBlank()) return result(false, "none", "Falta el nombre de la red (emptySsid)")
        if (password.isNotEmpty() && password.length !in 8..63) return result(false, "none", "La contraseña debe tener entre 8 y 63 caracteres (invalidPassword)")
        val wm = wifi(ctx) ?: return result(false, "none", "Este equipo no tiene Wi-Fi (noWifi)")
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                suggestion(wm, ssid, password, enabled)
            } else {
                legacy(wm, ssid, password, enabled)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "setHotspotAutoConnect denied", e)
            result(false, if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) "suggestion" else "legacy", "Android no dio permiso para cambiar el Wi-Fi (securityException)")
        } catch (e: Exception) {
            Log.w(TAG, "setHotspotAutoConnect failed", e)
            result(false, "none", "No se pudo registrar la red (${e.javaClass.simpleName})")
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun suggestion(wm: WifiManager, ssid: String, password: String, enabled: Boolean): Map<String, Any?> {
        val toRemove: List<WifiNetworkSuggestion> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val mine = wm.networkSuggestions.filter { Hotspot.unquote(it.ssid) == ssid }
            // Same SSID + passphrase already registered: leave it alone (removing would disconnect).
            if (enabled && mine.size == 1 && (mine[0].passphrase ?: "") == password) {
                return result(true, "suggestion")
            }
            mine
        } else {
            emptyList() // API 29 cannot list suggestions; an empty list removes all of this app's.
        }
        if (toRemove.isNotEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            val st = wm.removeNetworkSuggestions(toRemove)
            if (st != WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) Log.d(TAG, "removeNetworkSuggestions: ${statusName(st)}")
        }
        if (!enabled) return result(true, "suggestion")

        val builder = WifiNetworkSuggestion.Builder().setSsid(ssid)
        if (password.isNotEmpty()) builder.setWpa2Passphrase(password)
        val st = wm.addNetworkSuggestions(listOf(builder.build()))
        val ok = st == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS ||
            st == WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_DUPLICATE
        return result(ok, "suggestion", if (ok) null else statusName(st))
    }

    private fun statusName(code: Int): String = when (code) {
        WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS -> "success"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_INTERNAL -> "Error interno del Wi-Fi (internal)"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_APP_DISALLOWED ->
            "Rechazaste las redes sugeridas de esta app; actívalas en Ajustes › Wi-Fi (appDisallowed)"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_DUPLICATE -> "La red ya estaba registrada (duplicate)"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_EXCEEDS_MAX_PER_APP ->
            "Demasiadas redes sugeridas (exceedsMaxPerApp)"
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_REMOVE_INVALID -> "No había red que quitar (removeInvalid)"
        6 -> "El sistema no permite agregar redes ahora (addNotAllowed)"
        7 -> "Red inválida: revisa nombre y contraseña (addInvalid)"
        8 -> "Bloqueado por el administrador del equipo (restrictedByAdmin)"
        else -> "Error de Wi-Fi (status$code)"
    }

    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    private fun legacy(wm: WifiManager, ssid: String, password: String, enabled: Boolean): Map<String, Any?> {
        val quoted = "\"$ssid\""
        if (!wm.isWifiEnabled) runCatching { wm.isWifiEnabled = true }
        val existing = try {
            wm.configuredNetworks
        } catch (e: SecurityException) {
            null
        }
        existing?.filter { it.SSID == quoted }?.forEach { runCatching { wm.removeNetwork(it.networkId) } }
        if (!enabled) {
            runCatching { wm.saveConfiguration() }
            return result(true, "legacy")
        }
        val conf = WifiConfiguration().apply {
            SSID = quoted
            if (password.isEmpty()) {
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
            } else {
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                preSharedKey = "\"$password\""
            }
        }
        val id = wm.addNetwork(conf)
        if (id == -1) return result(false, "legacy", "Android rechazó la red (addNetworkFailed)")
        wm.enableNetwork(id, false)
        runCatching { wm.saveConfiguration() }
        return result(true, "legacy")
    }

    /** `{connected, ssid?}`; ssid is null when the OS hides it (no location permission/service). */
    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    fun status(ctx: Context): Map<String, Any?> {
        val wm = wifi(ctx)
        val info = try { wm?.connectionInfo } catch (_: Exception) { null }
        val cmWifi = try {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            cm?.allNetworks?.any { n ->
                cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            } ?: false
        } catch (_: Exception) {
            false
        }
        val connected = cmWifi || (info != null && info.networkId != -1 && info.supplicantState == SupplicantState.COMPLETED)
        val ssid = info?.ssid
            ?.takeUnless { it.isBlank() || it == WifiManager.UNKNOWN_SSID || it == "0x" }
            ?.let { Hotspot.unquote(it) }
        return mapOf("connected" to connected, "ssid" to if (connected) ssid else null)
    }
}
