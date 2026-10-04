package com.santiagortega.pixelcarplayer

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

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

    /** v3: [nonce] (16 bytes hex, nuevo por conexión) para el `auth` del otro lado. */
    fun hello(device: String, source: String, id: String? = null, nonce: String? = null): String = JSONObject()
        .put("t", "hello").put("v", VERSION).put("device", device).put("source", source)
        .apply { if (!id.isNullOrEmpty()) put("id", id) }
        .apply { if (!nonce.isNullOrEmpty()) put("nonce", nonce) }
        .toString()

    /** v3 `{"t":"auth","mac":hex}` (ver [LinkAuth.mac]). */
    fun auth(mac: String): String = JSONObject().put("t", "auth").put("mac", mac).toString()

    /** v3 `{"t":"pair_request","name":"<modelo>"}`. */
    fun pairRequest(name: String): String = JSONObject().put("t", "pair_request").put("name", name).toString()

    /** v3 `{"t":"pair","code":"123456","token":"<64 hex>"}`. */
    fun pair(code: String, token: String): String =
        JSONObject().put("t", "pair").put("code", code).put("token", token).toString()

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

    /**
     * Built by hand so `speed` is always serialized as a double (`1.0`, not `1` as org.json does).
     * v3: [extras] agrega `shuffle`, `repeat`, `liked`, `canLike`, `canShuffle`, `canRepeat`.
     */
    fun state(playing: Boolean, positionMs: Long, speed: Double, extras: StateExtras? = null): String {
        val s = if (speed.isFinite()) speed else 1.0
        val base = """{"t":"state","playing":$playing,"positionMs":$positionMs,"speed":$s"""
        if (extras == null) return "$base}"
        val repeat = extras.repeat?.let { "\"$it\"" } ?: "null"
        return base + ""","shuffle":${extras.shuffle},"repeat":$repeat,"liked":${extras.liked}""" +
            ""","canLike":${extras.canLike},"canShuffle":${extras.canShuffle},"canRepeat":${extras.canRepeat}}"""
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

    /** v3: cada ítem lleva `id` (queueId) y, si hay, `art` (JPEG 96 px base64). */
    fun queue(items: List<QueueEntry>): String {
        val arr = JSONArray()
        for (i in items) {
            val o = JSONObject().put("title", i.title).put("artist", i.artist)
            i.id?.let { o.put("id", it) }
            i.art?.let { o.put("art", it) }
            arr.put(o)
        }
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

/** v3: extras de `state` (CONTRACT §1 v3 "Controles y estado extra"). */
data class StateExtras(
    val shuffle: Boolean?,
    /** `off` | `all` | `one` | null. */
    val repeat: String?,
    val liked: Boolean?,
    val canLike: Boolean,
    val canShuffle: Boolean,
    val canRepeat: Boolean,
)

/**
 * v3: autenticación mutua HMAC-SHA256 (CONTRACT §1 v3). Funciones puras (sin Android).
 * `mac = HMAC_SHA256(key = bytes UTF-8 de la cadena hex del token, msg = "<nonce del otro>:<id propio>")`.
 */
object LinkAuth {
    private val rng = SecureRandom()

    fun randomHex(bytes: Int): String {
        val b = ByteArray(bytes)
        rng.nextBytes(b)
        return hex(b)
    }

    /** 16 bytes hex (nuevo por conexión). */
    fun newNonce(): String = randomHex(16)

    /** 32 bytes hex (64 caracteres), generado por el celular al emparejar. */
    fun newToken(): String = randomHex(32)

    fun hex(b: ByteArray): String {
        val chars = "0123456789abcdef"
        val sb = StringBuilder(b.size * 2)
        for (x in b) {
            val v = x.toInt() and 0xff
            sb.append(chars[v ushr 4]).append(chars[v and 0x0f])
        }
        return sb.toString()
    }

    /** MAC en hex minúsculas que manda el lado [ownId] en respuesta al `hello` con [peerNonce]. */
    fun mac(token: String, peerNonce: String, ownId: String): String {
        val m = Mac.getInstance("HmacSHA256")
        m.init(SecretKeySpec(token.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        return hex(m.doFinal("$peerNonce:$ownId".toByteArray(Charsets.UTF_8)))
    }

    /**
     * Verifica el `auth` del otro lado: lo calculó con NUESTRO nonce ([ownNonce]) y SU id ([peerId]).
     * Comparación en tiempo constante.
     */
    fun verify(token: String, ownNonce: String, peerId: String, received: String?): Boolean {
        if (received.isNullOrEmpty()) return false
        val expected = mac(token, ownNonce, peerId).toByteArray(Charsets.US_ASCII)
        val got = received.trim().lowercase().toByteArray(Charsets.US_ASCII)
        return MessageDigest.isEqual(expected, got)
    }

    /** Solo dígitos, 4–10 caracteres (la tableta muestra 6). null si no sirve. */
    fun normalizeCode(code: String?): String? =
        code?.filter { it.isDigit() }?.takeIf { it.length in 4..10 }
}

/**
 * v3: qué puede viajar antes de autenticar (CONTRACT §1 v3). El celular solo envía
 * `hello`/`auth`/`pair_*`/`ping` e ignora todo lo demás que reciba salvo el protocolo de enlace.
 */
object LinkGate {
    private val outbound = setOf("hello", "auth", "pair_request", "pair", "ping")
    private val inbound = setOf("hello", "auth", "pair_shown", "pair_ok", "pair_fail", "ping", "pong")

    fun outboundAllowedBeforeAuth(t: String): Boolean = t in outbound
    fun inboundAllowedBeforeAuth(t: String): Boolean = t in inbound
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
