package com.santiagortega.pixelcarplayer

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/**
 * Phone ⇄ car line protocol (docs/CONTRACT.md §1). One UTF-8 JSON object per line, field `t`.
 * Builders return the JSON text WITHOUT the trailing newline.
 */
object LinkProtocol {
    const val VERSION = 1
    const val TCP_PORT = 47321
    const val BEACON_PORT = 47322
    const val RFCOMM_UUID = "7c1e3a52-5b8e-4f0a-9d3c-2f6b8a4e91d7"
    const val RFCOMM_NAME = "PixelCarPlayer"

    /** v2: la tableta también escucha TCP aquí (el celular la marca). */
    const val CAR_TCP_PORT = 47323
    /** v2: beacon UDP de la tableta (`car_beacon`). */
    const val CAR_BEACON_PORT = 47324

    /** Stable id: SHA-1(title|artist|album|durationMs), first 16 hex chars. */
    fun trackId(title: String, artist: String, album: String, durationMs: Long): String {
        val digest = MessageDigest.getInstance("SHA-1")
            .digest("$title|$artist|$album|$durationMs".toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }.substring(0, 16)
    }

    fun hello(device: String, source: String, id: String? = null): String = JSONObject()
        .put("t", "hello").put("v", VERSION).put("device", device).put("source", source)
        .apply { if (!id.isNullOrEmpty()) put("id", id) }
        .toString()

    fun track(id: String, meta: TrackMeta): String = JSONObject()
        .put("t", "track")
        .put("id", id)
        .put("title", meta.title)
        .put("artist", meta.artist)
        .put("album", meta.album)
        .put("durationMs", meta.durationMs)
        .put("source", meta.packageName)
        .toString()

    fun art(id: String, jpeg: ByteArray): String = JSONObject()
        .put("t", "art")
        .put("id", id)
        .put("mime", "image/jpeg")
        .put("b64", Base64.encodeToString(jpeg, Base64.NO_WRAP))
        .toString()

    /** Built by hand so `speed` is always serialized as a double (`1.0`, not `1` as org.json does). */
    fun state(playing: Boolean, positionMs: Long, speed: Double): String {
        val s = if (speed.isFinite()) speed else 1.0
        return """{"t":"state","playing":$playing,"positionMs":$positionMs,"speed":$s}"""
    }

    fun lyrics(id: String, status: String, synced: Boolean, lines: List<LyricLine>): String {
        val arr = JSONArray()
        for (l in lines) arr.put(JSONObject().put("ms", l.ms).put("text", l.text))
        return JSONObject()
            .put("t", "lyrics")
            .put("id", id)
            .put("status", status)
            .put("synced", synced)
            .put("lines", arr)
            .toString()
    }

    fun queue(items: List<QueueEntry>): String {
        val arr = JSONArray()
        for (i in items) arr.put(JSONObject().put("title", i.title).put("artist", i.artist))
        return JSONObject().put("t", "queue").put("items", arr).toString()
    }

    fun ping(): String = """{"t":"ping"}"""

    fun beacon(device: String, id: String? = null): String = JSONObject()
        .put("t", "beacon").put("v", VERSION).put("device", device).put("port", TCP_PORT)
        .apply { if (!id.isNullOrEmpty()) put("id", id) }
        .toString()

    /** `{"t":"car_beacon","v":2,"device","id","port":47323}` recibido en UDP 47324. */
    data class CarBeacon(val device: String, val id: String?, val port: Int)

    /** null si [text] no es un `car_beacon` válido. Puerto fuera de rango → [CAR_TCP_PORT]. */
    fun parseCarBeacon(text: String): CarBeacon? {
        val o = parse(text.trim()) ?: return null
        if (o.optString("t") != "car_beacon") return null
        val port = o.optInt("port", CAR_TCP_PORT).takeIf { it in 1..65535 } ?: CAR_TCP_PORT
        val id = o.optString("id", "").takeIf { it.isNotBlank() }
        return CarBeacon(o.optString("device", ""), id, port)
    }

    /** Tableta → celular `{"t":"hotspot","ssid","password"}`; null sin ssid. */
    fun parseHotspot(o: JSONObject): Pair<String, String>? {
        if (o.optString("t") != "hotspot") return null
        val ssid = o.optString("ssid", "").trim()
        if (ssid.isEmpty()) return null
        return ssid to o.optString("password", "")
    }

    /** Parses an incoming line; null if it is not a JSON object with a string `t`. */
    fun parse(line: String): JSONObject? = try {
        val o = JSONObject(line)
        if (o.optString("t").isNullOrEmpty()) null else o
    } catch (_: Exception) {
        null
    }
}

/**
 * Una sola conexión por par (CONTRACT §1 v2): cuando llega un `hello` con un `id` que ya tiene otra
 * conexión viva, se conserva la existente si dio señales de vida (pong/hello) en [WINDOW_MS];
 * si no, se queda la nueva y se cierra la vieja.
 */
object LinkDedup {
    const val WINDOW_MS = 25_000L

    /** true = conservar la conexión más vieja (cerrar la nueva). */
    fun keepOlder(olderLastAliveMs: Long, nowMs: Long, windowMs: Long = WINDOW_MS): Boolean =
        olderLastAliveMs > 0 && nowMs - olderLastAliveMs <= windowMs
}
