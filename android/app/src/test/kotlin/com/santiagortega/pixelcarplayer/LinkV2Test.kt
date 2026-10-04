package com.santiagortega.pixelcarplayer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream

class LinkV2Test {

    @Test
    fun broadcastFromPrefix() {
        assertEquals("192.168.43.255", WifiNets.broadcastAddress("192.168.43.17", 24))
        assertEquals("10.0.255.255", WifiNets.broadcastAddress("10.0.3.4", 16))
        assertEquals("172.20.10.15", WifiNets.broadcastAddress("172.20.10.2", 28))
        assertEquals("192.168.1.5", WifiNets.broadcastAddress("192.168.1.5", 32))
        assertEquals("255.255.255.255", WifiNets.broadcastAddress("192.168.1.5", 0))
        assertNull(WifiNets.broadcastAddress("192.168.1", 24))
        assertNull(WifiNets.broadcastAddress("192.168.1.300", 24))
        assertNull(WifiNets.broadcastAddress("192.168.1.3", 33))
    }

    @Test
    fun subnetMatch() {
        assertTrue(WifiNets.sameSubnet("192.168.43.1", "192.168.43.200", 24))
        assertFalse(WifiNets.sameSubnet("192.168.44.1", "192.168.43.200", 24))
        assertTrue(WifiNets.sameSubnet("10.1.2.3", "10.9.9.9", 8))
        assertFalse(WifiNets.sameSubnet("nope", "10.9.9.9", 8))
    }

    @Test
    fun dedupKeepsHealthyOlder() {
        val now = 100_000L
        assertTrue(LinkDedup.keepOlder(now - 5_000, now))
        assertTrue(LinkDedup.keepOlder(now - 25_000, now))
        assertFalse(LinkDedup.keepOlder(now - 25_001, now))
        assertFalse("never answered → keep the newer", LinkDedup.keepOlder(0L, now))
    }

    @Test
    fun parsesCarBeacon() {
        val b = LinkProtocol.parseCarBeacon(
            """{"t":"car_beacon","v":2,"device":"Head Unit","id":"abc-123","port":47323}"""
        )!!
        assertEquals("Head Unit", b.device)
        assertEquals("abc-123", b.id)
        assertEquals(47323, b.port)

        val noPort = LinkProtocol.parseCarBeacon("""{"t":"car_beacon","device":"X"}""")!!
        assertEquals(LinkProtocol.CAR_TCP_PORT, noPort.port)
        assertNull(noPort.id)
        assertEquals(LinkProtocol.CAR_TCP_PORT, LinkProtocol.parseCarBeacon("""{"t":"car_beacon","port":99999}""")!!.port)

        assertNull(LinkProtocol.parseCarBeacon("""{"t":"beacon","v":1,"device":"Pixel","port":47321}"""))
        assertNull(LinkProtocol.parseCarBeacon("not json"))
        assertNull(LinkProtocol.parseCarBeacon(""))
    }

    @Test
    fun helloCarriesId() {
        val o = LinkProtocol.parse(LinkProtocol.hello("Pixel 8", "com.spotify.music", "id-1"))!!
        assertEquals("id-1", o.getString("id"))
        assertFalse(LinkProtocol.parse(LinkProtocol.hello("Pixel 8", "x"))!!.has("id"))
    }

    @Test
    fun parsesHotspotMessage() {
        val o = LinkProtocol.parse("""{"t":"hotspot","ssid":" Carro ","password":"12345678"}""")!!
        assertEquals("Carro" to "12345678", LinkProtocol.parseHotspot(o))
        assertNull(LinkProtocol.parseHotspot(LinkProtocol.parse("""{"t":"hotspot","ssid":""}""")!!))
    }

    @Test
    fun parsesSoftApXml() {
        val xml = """
            <?xml version='1.0' encoding='utf-8' standalone='yes' ?>
            <WifiConfigStoreData>
            <SoftAp>
            <string name="WifiSsid">&quot;Mi Carro&quot;</string>
            <string name="Passphrase">clave1234</string>
            </SoftAp>
            </WifiConfigStoreData>
        """.trimIndent()
        assertEquals(Hotspot.Creds("Mi Carro", "clave1234"), Hotspot.parseSoftApXml(xml))
        val old = """<string name="SSID">AndroidAP</string><string name="Passphrase">abcdefgh</string>"""
        assertEquals(Hotspot.Creds("AndroidAP", "abcdefgh"), Hotspot.parseSoftApXml(old))
        assertEquals("AB", Hotspot.decodeWifiSsid("4142"))
    }

    @Test
    fun parsesSoftApConf() {
        fun conf(version: Int, ssid: String, auth: Int, pass: String?): ByteArray {
            val bos = ByteArrayOutputStream()
            DataOutputStream(bos).use { out ->
                out.writeInt(version)
                out.writeUTF(ssid)
                if (version >= 2) {
                    out.writeInt(0)
                    out.writeInt(6)
                }
                if (version >= 3) out.writeBoolean(false)
                out.writeInt(auth)
                if (auth != 0) out.writeUTF(pass!!)
            }
            return bos.toByteArray()
        }
        assertEquals(Hotspot.Creds("Carro", "secreta123"), Hotspot.parseSoftApConf(conf(3, "Carro", 4, "secreta123")))
        assertEquals(Hotspot.Creds("Carro", "secreta123"), Hotspot.parseSoftApConf(conf(2, "Carro", 1, "secreta123")))
        assertEquals(Hotspot.Creds("Abierta", null), Hotspot.parseSoftApConf(conf(1, "Abierta", 0, null)))
        assertNull(Hotspot.parseSoftApConf(byteArrayOf(1, 2)))
    }

    @Test
    fun diagRingBufferIsBounded() {
        LinkDiag.clear()
        repeat(LinkDiag.MAX + 20) { LinkDiag.log("l$it") }
        val lines = LinkDiag.lines()
        assertEquals(LinkDiag.MAX, lines.size)
        assertTrue(lines.last().endsWith("l${LinkDiag.MAX + 19}"))
        LinkDiag.clear()
        assertTrue(LinkDiag.lines().isEmpty())
    }
}
