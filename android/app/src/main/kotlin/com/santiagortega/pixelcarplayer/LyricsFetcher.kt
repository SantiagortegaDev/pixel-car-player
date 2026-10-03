package com.santiagortega.pixelcarplayer

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.FileNotFoundException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** Result of a lyrics lookup. [status] is `ok` or `not_found`. */
data class LyricsResult(
    val status: String,
    val synced: Boolean,
    val lines: List<LyricLine>,
    /** True when the lookup failed because of the network (not cached, may be retried). */
    val transientError: Boolean = false,
) {
    companion object {
        val NOT_FOUND = LyricsResult("not_found", false, emptyList())
    }
}

/** LRCLIB client (https://lrclib.net/docs). Blocking: call from a background executor. */
object LyricsFetcher {
    private const val BASE = "https://lrclib.net/api"
    private const val USER_AGENT =
        "PixelCarPlayer/1.0 (https://github.com/SantiagortegaDev/pixel-car-player)"
    private const val CACHE_SIZE = 30
    private const val DURATION_TOLERANCE_S = 5.0

    private val cache = object : LinkedHashMap<String, LyricsResult>(CACHE_SIZE, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, LyricsResult>?) =
            size > CACHE_SIZE
    }

    fun cached(trackId: String): LyricsResult? = synchronized(cache) { cache[trackId] }

    fun fetch(trackId: String, title: String, artist: String, album: String, durationMs: Long): LyricsResult {
        cached(trackId)?.let { return it }
        if (title.isBlank()) return LyricsResult.NOT_FOUND
        val result = try {
            lookup(title, artist, album, durationMs)
        } catch (e: IOException) {
            Log.w(TAG, "LRCLIB network error: ${e.message}")
            return LyricsResult.NOT_FOUND.copy(transientError = true)
        } catch (e: Exception) {
            Log.w(TAG, "LRCLIB lookup failed", e)
            return LyricsResult.NOT_FOUND.copy(transientError = true)
        }
        synchronized(cache) { cache[trackId] = result }
        return result
    }

    private fun lookup(title: String, artist: String, album: String, durationMs: Long): LyricsResult {
        val durationS = durationMs / 1000.0
        // 1) exact match endpoint (needs all fields)
        if (durationMs > 0) {
            val url = "$BASE/get?" + query(
                "artist_name" to artist,
                "track_name" to title,
                "album_name" to album,
                "duration" to (durationMs / 1000).toString(),
            )
            httpGet(url)?.let { body -> toResult(JSONObject(body))?.let { return it } }
        }
        // 2) search, with the raw title and then a cleaned-up one ("Song - Remastered 2011")
        val titles = linkedSetOf(title, cleanTitle(title)).filter { it.isNotBlank() }
        for (t in titles) {
            val url = "$BASE/search?" + query("track_name" to t, "artist_name" to artist)
            val body = httpGet(url) ?: continue
            pickBest(JSONArray(body), if (durationMs > 0) durationS else null)?.let { return it }
        }
        return LyricsResult.NOT_FOUND
    }

    private fun pickBest(arr: JSONArray, durationS: Double?): LyricsResult? {
        data class Cand(val obj: JSONObject, val diff: Double, val synced: Boolean)
        val cands = (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            val d = o.optDouble("duration", Double.NaN)
            val diff = if (durationS == null || d.isNaN()) 0.0 else kotlin.math.abs(d - durationS)
            if (durationS != null && !d.isNaN() && diff > DURATION_TOLERANCE_S) return@mapNotNull null
            val synced = !o.optStringOrNull("syncedLyrics").isNullOrBlank()
            val plain = !o.optStringOrNull("plainLyrics").isNullOrBlank()
            if (!synced && !plain) null else Cand(o, diff, synced)
        }
        val best = cands.sortedWith(compareBy<Cand>({ !it.synced }, { it.diff })).firstOrNull()
        return best?.let { toResult(it.obj) }
    }

    private fun toResult(o: JSONObject): LyricsResult? {
        val synced = o.optStringOrNull("syncedLyrics")
        if (!synced.isNullOrBlank()) {
            val lines = LrcParser.parse(synced)
            if (lines.isNotEmpty()) return LyricsResult("ok", true, lines)
        }
        val plain = o.optStringOrNull("plainLyrics")
        if (!plain.isNullOrBlank()) return LyricsResult("ok", false, LrcParser.plain(plain))
        return null // instrumental or empty
    }

    /** Returns the body on 2xx, null on 404 (not found); throws IOException on other failures. */
    private fun httpGet(url: String): String? {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 10_000
            conn.readTimeout = 15_000
            conn.setRequestProperty("User-Agent", USER_AGENT)
            conn.setRequestProperty("Accept", "application/json")
            val code = conn.responseCode
            if (code == 404) return null
            if (code !in 200..299) throw IOException("HTTP $code for $url")
            return conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } catch (e: FileNotFoundException) {
            return null
        } finally {
            conn.disconnect()
        }
    }

    private fun query(vararg params: Pair<String, String>) =
        params.joinToString("&") { (k, v) -> k + "=" + URLEncoder.encode(v, "UTF-8") }

    private val suffixDash = Regex("""\s+-\s+.*$""")
    private val bracketed = Regex("""\s*[(\[][^)\]]*(feat\.?|ft\.?|with|remaster|live|version|edit|mix)[^)\]]*[)\]]""", RegexOption.IGNORE_CASE)

    internal fun cleanTitle(title: String): String =
        title.replace(bracketed, "").replace(suffixDash, "").trim()

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (isNull(key)) null else optString(key, "")
}
