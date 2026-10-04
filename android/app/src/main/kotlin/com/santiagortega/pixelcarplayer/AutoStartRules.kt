package com.santiagortega.pixelcarplayer

import org.json.JSONArray
import org.json.JSONObject

/**
 * v3 (celular): reglas de arranque/parada automática del transmisor
 * (`setAutoStartRules`: `{enabled, btAddresses, wifiSsids, stopAfterMinutes}`). Lógica pura.
 */
data class AutoStartRules(
    val enabled: Boolean = false,
    val btAddresses: List<String> = emptyList(),
    val wifiSsids: List<String> = emptyList(),
    /** Minutos tras perder el Bluetooth del carro antes de detener (0 = de inmediato). */
    val stopAfterMinutes: Int = DEFAULT_STOP_AFTER,
) {
    fun hasBt(address: String?): Boolean {
        val a = normMac(address) ?: return false
        return btAddresses.any { normMac(it) == a }
    }

    fun hasSsid(ssid: String?): Boolean {
        val s = unquoteSsid(ssid) ?: return false
        return wifiSsids.any { it.trim() == s }
    }

    /** Alguna regla coincide con el estado actual (Bluetooth conectados + SSID actual). */
    fun matches(btConnected: Collection<String>, ssid: String?): Boolean =
        enabled && (btConnected.any { hasBt(it) } || hasSsid(ssid))

    fun toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "btAddresses" to btAddresses,
        "wifiSsids" to wifiSsids,
        "stopAfterMinutes" to stopAfterMinutes,
    )

    fun toJson(): String = JSONObject()
        .put("enabled", enabled)
        .put("btAddresses", JSONArray(btAddresses))
        .put("wifiSsids", JSONArray(wifiSsids))
        .put("stopAfterMinutes", stopAfterMinutes)
        .toString()

    fun withBt(address: String): AutoStartRules {
        val a = normMac(address) ?: return this
        return if (hasBt(a)) this else copy(btAddresses = btAddresses + a)
    }

    companion object {
        const val DEFAULT_STOP_AFTER = 2
        const val MAX_STOP_AFTER = 240

        fun normMac(s: String?): String? = s?.trim()?.uppercase()?.takeIf { it.isNotEmpty() }

        /** Quita comillas (WifiInfo.getSSID) y descarta `<unknown ssid>`. */
        fun unquoteSsid(s: String?): String? {
            var v = s?.trim() ?: return null
            if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) v = v.substring(1, v.length - 1)
            if (v.isEmpty() || v == "<unknown ssid>" || v == "0x") return null
            return v
        }

        private fun clean(list: List<String>, mac: Boolean): List<String> =
            list.mapNotNull { if (mac) normMac(it) else it.trim().takeIf { s -> s.isNotEmpty() } }.distinct()

        fun fromMap(m: Map<*, *>?): AutoStartRules {
            if (m == null) return AutoStartRules()
            fun strings(k: String) = (m[k] as? List<*>).orEmpty().mapNotNull { it?.toString() }
            return AutoStartRules(
                enabled = m["enabled"] as? Boolean ?: false,
                btAddresses = clean(strings("btAddresses"), true),
                wifiSsids = clean(strings("wifiSsids"), false),
                stopAfterMinutes = ((m["stopAfterMinutes"] as? Number)?.toInt() ?: DEFAULT_STOP_AFTER)
                    .coerceIn(0, MAX_STOP_AFTER),
            )
        }

        fun fromJson(s: String?): AutoStartRules {
            if (s.isNullOrBlank()) return AutoStartRules()
            return try {
                val o = JSONObject(s)
                fun strings(k: String): List<String> {
                    val a = o.optJSONArray(k) ?: return emptyList()
                    return (0 until a.length()).mapNotNull { a.optString(it, null) }
                }
                AutoStartRules(
                    enabled = o.optBoolean("enabled", false),
                    btAddresses = clean(strings("btAddresses"), true),
                    wifiSsids = clean(strings("wifiSsids"), false),
                    stopAfterMinutes = o.optInt("stopAfterMinutes", DEFAULT_STOP_AFTER).coerceIn(0, MAX_STOP_AFTER),
                )
            } catch (_: Exception) {
                AutoStartRules()
            }
        }
    }
}
