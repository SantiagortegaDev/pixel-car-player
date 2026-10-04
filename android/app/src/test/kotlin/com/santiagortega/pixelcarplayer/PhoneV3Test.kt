package com.santiagortega.pixelcarplayer

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneV3Test {

    private val token = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
    private val nonce = "0123456789abcdef0123456789abcdef"

    // ---------------------------------------------------------------- HMAC / auth

    @Test
    fun macMatchesReferenceVector() {
        // python: hmac.new(token.encode(), b"<nonce>:car-install-id", sha256).hexdigest()
        assertEquals(
            "e1888a2a1e5ddfccbb515a4ddcf40c8238d8f1c674af369f22b60a82e6f577fa",
            LinkAuth.mac(token, nonce, "car-install-id"),
        )
    }

    @Test
    fun verifyChecksNonceIdAndToken() {
        // El carro calcula con NUESTRO nonce y SU id; nosotros verificamos con lo mismo.
        val carMac = LinkAuth.mac(token, nonce, "car-1")
        assertTrue(LinkAuth.verify(token, nonce, "car-1", carMac))
        assertTrue(LinkAuth.verify(token, nonce, "car-1", carMac.uppercase()))
        assertFalse(LinkAuth.verify(token, nonce, "car-2", carMac))
        assertFalse(LinkAuth.verify(token, "ffff$nonce".take(32), "car-1", carMac))
        assertFalse(LinkAuth.verify(token.replace('0', '1'), nonce, "car-1", carMac))
        assertFalse(LinkAuth.verify(token, nonce, "car-1", carMac.dropLast(1)))
        assertFalse(LinkAuth.verify(token, nonce, "car-1", ""))
        assertFalse(LinkAuth.verify(token, nonce, "car-1", null))
    }

    @Test
    fun randomValuesHaveContractLengths() {
        val hex = Regex("^[0-9a-f]+$")
        val n = LinkAuth.newNonce()
        val t = LinkAuth.newToken()
        assertEquals(32, n.length)
        assertEquals(64, t.length)
        assertTrue(hex.matches(n) && hex.matches(t))
        assertTrue(LinkAuth.newNonce() != n)
    }

    @Test
    fun normalizesPairCode() {
        assertEquals("123456", LinkAuth.normalizeCode(" 123 456 "))
        assertNull(LinkAuth.normalizeCode("12"))
        assertNull(LinkAuth.normalizeCode(null))
    }

    @Test
    fun gateAllowsOnlyLinkProtocolBeforeAuth() {
        for (t in listOf("hello", "auth", "pair_request", "pair", "ping")) assertTrue(t, LinkGate.outboundAllowedBeforeAuth(t))
        for (t in listOf("track", "art", "state", "lyrics", "queue")) assertFalse(t, LinkGate.outboundAllowedBeforeAuth(t))
        for (t in listOf("hello", "auth", "pair_shown", "pair_ok", "pair_fail", "pong")) assertTrue(t, LinkGate.inboundAllowedBeforeAuth(t))
        for (t in listOf("cmd", "resync", "hotspot")) assertFalse(t, LinkGate.inboundAllowedBeforeAuth(t))
    }

    @Test
    fun buildsV3Messages() {
        val hello = JSONObject(LinkProtocol.hello("Pixel 8", "com.spotify.music", "id-1", nonce))
        assertEquals(nonce, hello.getString("nonce"))
        assertEquals("id-1", hello.getString("id"))
        assertEquals("auth", JSONObject(LinkProtocol.auth("ab")).getString("t"))
        val pr = JSONObject(LinkProtocol.pairRequest("Pixel 8"))
        assertEquals("pair_request", pr.getString("t"))
        assertEquals("Pixel 8", pr.getString("name"))
        val p = JSONObject(LinkProtocol.pair("123456", token))
        assertEquals("123456", p.getString("code"))
        assertEquals(token, p.getString("token"))
    }

    @Test
    fun stateCarriesExtras() {
        val s = JSONObject(
            LinkProtocol.state(true, 1000, 1.0, StateExtras(true, "one", null, canLike = false, canShuffle = true, canRepeat = true))
        )
        assertTrue(s.getBoolean("shuffle"))
        assertEquals("one", s.getString("repeat"))
        assertTrue(s.isNull("liked"))
        assertFalse(s.getBoolean("canLike"))
        assertTrue(s.getBoolean("canShuffle"))
        val none = JSONObject(LinkProtocol.state(false, 0, 1.0, StateExtras(null, null, false, true, false, false)))
        assertTrue(none.isNull("shuffle"))
        assertTrue(none.isNull("repeat"))
        assertFalse(none.getBoolean("liked"))
        // Sin extras: formato v1 intacto.
        assertEquals("""{"t":"state","playing":false,"positionMs":0,"speed":1.0}""", LinkProtocol.state(false, 0, 1.0))
    }

    @Test
    fun queueItemsCarryIdAndArt() {
        val q = JSONObject(LinkProtocol.queue(listOf(QueueEntry("A", "B", 7L, "abc"), QueueEntry("C", "D", 8L))))
        val items = q.getJSONArray("items")
        assertEquals(7L, items.getJSONObject(0).getLong("id"))
        assertEquals("abc", items.getJSONObject(0).getString("art"))
        assertFalse(items.getJSONObject(1).has("art"))
    }

    // ---------------------------------------------------------------- shuffle / repeat / like

    @Test
    fun mapsShuffleAndRepeat() {
        assertNull(MediaControls.shuffleOf(-1))
        assertEquals(false, MediaControls.shuffleOf(0))
        assertEquals(true, MediaControls.shuffleOf(1))
        assertNull(MediaControls.repeatOf(-1))
        assertEquals("off", MediaControls.repeatOf(0))
        assertEquals("one", MediaControls.repeatOf(1))
        assertEquals("all", MediaControls.repeatOf(2))
        assertEquals("all", MediaControls.repeatOf(3))
        // off → all → one → off
        assertEquals(2, MediaControls.nextRepeat(0))
        assertEquals(1, MediaControls.nextRepeat(2))
        assertEquals(0, MediaControls.nextRepeat(1))
        assertEquals(1, MediaControls.nextShuffle(0))
        assertEquals(0, MediaControls.nextShuffle(1))
    }

    @Test
    fun detectsSpotifyStyleCollectionActions() {
        val notLiked = MediaControls.detectLike(
            listOf(
                "TOGGLE_SHUFFLE" to "Shuffle",
                "ADD_TO" to "Add to Liked Songs",
                "START_RADIO" to "Go to radio",
                "SEEK_15_SECONDS_BACK" to "Seek back",
            )
        )
        assertEquals("ADD_TO", notLiked.likeAction)
        assertEquals(false, notLiked.liked)
        assertTrue(notLiked.canLike)
        assertEquals("ADD_TO", notLiked.actionToSend())

        val liked = MediaControls.detectLike(listOf("REMOVE_FROM" to "", "TOGGLE_REPEAT" to "Repeat"))
        assertEquals("REMOVE_FROM", liked.unlikeAction)
        assertEquals(true, liked.liked)
        assertEquals("REMOVE_FROM", liked.actionToSend())
    }

    @Test
    fun detectsOtherAppsAndIgnoresLookalikes() {
        val yt = MediaControls.detectLike(
            listOf("com.google.android.music.THUMBS_DOWN" to "Thumbs down", "com.google.android.music.THUMBS_UP" to "Thumbs up")
        )
        assertEquals("com.google.android.music.THUMBS_UP", yt.likeAction)
        assertNull(yt.unlikeAction)

        assertEquals(true, MediaControls.detectLike(listOf("TOGGLE_LIKE" to "Unlike")).liked)
        assertEquals(true, MediaControls.detectLike(listOf("fav" to "Quitar de Tus me gusta")).liked)
        assertEquals(false, MediaControls.detectLike(listOf("heart" to "Favorite")).liked)

        val none = MediaControls.detectLike(
            listOf("ADD_TO_PLAYLIST" to "Add to playlist", "DISLIKE" to "Dislike", "ADD_TO_QUEUE" to "Queue")
        )
        assertFalse(none.canLike)
        assertNull(none.liked)
        assertNull(none.actionToSend())
    }

    @Test
    fun findsCustomShuffleAction() {
        val a = listOf("TOGGLE_SHUFFLE" to "Shuffle", "TOGGLE_REPEAT" to "")
        assertEquals("TOGGLE_SHUFFLE", MediaControls.findAction(a, "shuffle"))
        assertEquals("TOGGLE_REPEAT", MediaControls.findAction(a, "repeat"))
        assertNull(MediaControls.findAction(a, "like"))
    }

    // ---------------------------------------------------------------- auto start rules

    @Test
    fun rulesMatchBluetoothAndWifi() {
        val r = AutoStartRules(true, listOf("AA:BB:CC:DD:EE:FF"), listOf("Carro"), 2)
        assertTrue(r.matches(listOf("aa:bb:cc:dd:ee:ff"), null))
        assertTrue(r.matches(emptyList(), "\"Carro\""))
        assertFalse(r.matches(emptyList(), "carro")) // SSID distingue mayúsculas
        assertFalse(r.matches(listOf("11:22:33:44:55:66"), "<unknown ssid>"))
        assertFalse(r.copy(enabled = false).matches(listOf("AA:BB:CC:DD:EE:FF"), "Carro"))
    }

    @Test
    fun rulesParseAndRoundTrip() {
        val r = AutoStartRules.fromMap(
            mapOf(
                "enabled" to true,
                "btAddresses" to listOf(" aa:bb:cc:dd:ee:ff ", "AA:BB:CC:DD:EE:FF", ""),
                "wifiSsids" to listOf("Carro", " "),
                "stopAfterMinutes" to 9999,
            )
        )
        assertEquals(listOf("AA:BB:CC:DD:EE:FF"), r.btAddresses)
        assertEquals(listOf("Carro"), r.wifiSsids)
        assertEquals(AutoStartRules.MAX_STOP_AFTER, r.stopAfterMinutes)
        assertEquals(r, AutoStartRules.fromJson(r.toJson()))
        assertEquals(AutoStartRules(), AutoStartRules.fromJson("no json"))
        assertEquals(AutoStartRules.DEFAULT_STOP_AFTER, AutoStartRules.fromMap(mapOf("enabled" to true)).stopAfterMinutes)
        assertEquals(listOf("AA:BB:CC:DD:EE:FF", "11:22:33:44:55:66"), r.withBt("11:22:33:44:55:66").btAddresses)
        assertEquals(r, r.withBt("aa:bb:cc:dd:ee:ff"))
    }
}
