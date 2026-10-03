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

    /** Stable id: SHA-1(title|artist|album|durationMs), first 16 hex chars. */
    fun trackId(title: String, artist: String, album: String, durationMs: Long): String {
        val digest = MessageDigest.getInstance("SHA-1")
            .digest("$title|$artist|$album|$durationMs".toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }.substring(0, 16)
    }

    fun hello(device: String, source: String): String = JSONObject()
        .put("t", "hello").put("v", VERSION).put("device", device).put("source", source)
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

    fun ping(): String = """{"t":"ping"}"""

    fun beacon(device: String): String = JSONObject()
        .put("t", "beacon").put("v", VERSION).put("device", device).put("port", TCP_PORT)
        .toString()

    /** Parses an incoming line; null if it is not a JSON object with a string `t`. */
    fun parse(line: String): JSONObject? = try {
        val o = JSONObject(line)
        if (o.optString("t").isNullOrEmpty()) null else o
    } catch (_: Exception) {
        null
    }
}
