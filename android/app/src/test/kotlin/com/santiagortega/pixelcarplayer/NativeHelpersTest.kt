package com.santiagortega.pixelcarplayer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeHelpersTest {

    @Test
    fun parsesArpTable() {
        val arp = """
            IP address       HW type     Flags       HW address            Mask     Device
            192.168.43.120   0x1         0x2         aa:bb:cc:dd:ee:ff     *        wlan0
            192.168.43.121   0x1         0x0         00:00:00:00:00:00     *        wlan0
            192.168.43.122   0x1         0x2         00:00:00:00:00:00     *        wlan0
            192.168.43.120   0x1         0x2         aa:bb:cc:dd:ee:ff     *        ap0
            192.168.43.130   0x1         0x6         11:22:33:44:55:66     *        ap0
        """.trimIndent()
        assertEquals(listOf("192.168.43.120", "192.168.43.130"), NetUtils.parseArp(arp))
    }

    @Test
    fun parsesIpNeigh() {
        val out = """
            192.168.43.5 dev ap0 lladdr aa:bb:cc:dd:ee:01 REACHABLE
            192.168.43.6 dev ap0 lladdr aa:bb:cc:dd:ee:02 STALE
            192.168.43.7 dev ap0  FAILED
            192.168.43.8 dev ap0 lladdr aa:bb:cc:dd:ee:03 DELAY
            fe80::1 dev wlan0 lladdr aa:bb:cc:dd:ee:04 REACHABLE
            192.168.43.9 dev ap0 lladdr aa:bb:cc:dd:ee:05 INCOMPLETE
        """.trimIndent()
        assertEquals(listOf("192.168.43.5", "192.168.43.6", "192.168.43.8"), NetUtils.parseIpNeigh(out))
    }

    @Test
    fun unquotesSsid() {
        assertEquals("Carro", Hotspot.unquote("\"Carro\""))
        assertEquals("Carro", Hotspot.unquote("Carro"))
        assertEquals(null, Hotspot.unquote("\"\""))
        assertEquals(null, Hotspot.unquote(null))
    }

    private fun fftWithPeak(size: Int, bin: Int, amp: Int = 100): ByteArray {
        val fft = ByteArray(size)
        fft[2 * bin] = amp.toByte()
        fft[2 * bin + 1] = amp.toByte()
        return fft
    }

    private fun DoubleArray.argMax(): Int = indices.maxByOrNull { this[it] }!!

    @Test
    fun bandsAreLogSpacedAndNormalized() {
        val bands = FftBands(64)
        bands.configure(1024, 44_100_000)
        val low = bands.process(fftWithPeak(1024, 3))
        assertEquals(64, low.size)
        assertTrue(low.all { it in 0.0..1.0 })
        bands.reset()
        val mid = bands.process(fftWithPeak(1024, 40))
        bands.reset()
        val high = bands.process(fftWithPeak(1024, 300))
        assertTrue(low.argMax() < mid.argMax())
        assertTrue(mid.argMax() < high.argMax())
        assertTrue(high.argMax() >= 56)
    }

    @Test
    fun autoGainLiftsQuietSignal() {
        val bands = FftBands(64)
        bands.configure(1024, 44_100_000)
        var last = DoubleArray(64)
        repeat(10) { last = bands.process(fftWithPeak(1024, 20, amp = 20)) }
        assertTrue("quiet audio should still reach a high level, was ${last.max()}", last.max() > 0.6)
    }

    @Test
    fun smallCaptureSizeStillGivesAllBands() {
        val bands = FftBands(64)
        bands.configure(128, 44_100_000)
        val out = bands.process(fftWithPeak(128, 10))
        assertEquals(64, out.size)
        assertTrue(out.all { it in 0.0..1.0 })
    }

    @Test
    fun rmsIsNormalized() {
        val bands = FftBands(64)
        val silence = ByteArray(256) { 128.toByte() }
        assertEquals(0.0, bands.rms(silence), 1e-9)
        val loud = ByteArray(256) { if (it % 2 == 0) 0 else 255.toByte() }
        assertTrue(bands.rms(loud) > 0.9)
    }
}
