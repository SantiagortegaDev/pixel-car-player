package com.santiagortega.pixelcarplayer

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Real-audio visualizer on the global output mix (`Visualizer(0)`). Posts
 * `{type:'fft', bands: List<Double>(64, 0..1), rms: Double}` through [EventHub], ≤ ~30 fps
 * (most HALs cap the capture rate at 20 Hz). Main thread only.
 */
object AudioViz {
    private const val MIN_INTERVAL_MS = 33L

    private var visualizer: Visualizer? = null
    private val bands = FftBands(64)
    private var lastPost = 0L
    private var rms = 0.0

    fun hasPermission(ctx: Context) =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun start(ctx: Context): Boolean {
        if (visualizer != null) return true
        if (!hasPermission(ctx)) {
            Log.i(TAG, "visualizer: RECORD_AUDIO not granted")
            return false
        }
        var v: Visualizer? = null
        return try {
            v = Visualizer(0)
            v.enabled = false
            val size = Visualizer.getCaptureSizeRange()?.getOrNull(1)?.takeIf { it > 0 } ?: 1024
            if (v.setCaptureSize(size) != Visualizer.SUCCESS) v.setCaptureSize(1024)
            v.scalingMode = Visualizer.SCALING_MODE_NORMALIZED
            bands.configure(v.captureSize, v.samplingRate)
            val rate = Visualizer.getMaxCaptureRate()
            v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(vz: Visualizer?, waveform: ByteArray?, samplingRate: Int) {
                    if (waveform != null) rms = bands.rms(waveform)
                }

                override fun onFftDataCapture(vz: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    if (fft == null) return
                    val values = bands.process(fft)
                    val now = SystemClock.uptimeMillis()
                    if (now - lastPost < MIN_INTERVAL_MS) return
                    lastPost = now
                    EventHub.post(mapOf("type" to "fft", "bands" to values.toList(), "rms" to rms))
                }
            }, rate, true, true)
            if (v.setEnabled(true) != Visualizer.SUCCESS) throw IllegalStateException("setEnabled failed")
            visualizer = v
            Log.i(TAG, "visualizer started: capture=${v.captureSize} rate=${rate / 1000.0}Hz sr=${v.samplingRate}")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "visualizer unavailable", e)
            try { v?.release() } catch (_: Throwable) {}
            false
        }
    }

    fun stop() {
        val v = visualizer ?: return
        visualizer = null
        try {
            v.enabled = false
        } catch (_: Throwable) {
        }
        try {
            v.release()
        } catch (e: Throwable) {
            Log.w(TAG, "visualizer release failed", e)
        }
        bands.reset()
        rms = 0.0
    }
}

/**
 * Turns Visualizer FFT frames (`[re0, reN/2, re1, im1, re2, im2, …]`, signed bytes) into [count]
 * log-spaced bands (bass → treble), normalized to 0..1 with a slowly decaying running peak
 * (auto-gain) so quiet sources still move. Pure JVM: unit-tested.
 */
class FftBands(val count: Int = 64) {
    companion object {
        private const val F_LO = 30.0
        private const val F_HI = 16_000.0
        /** Per-frame peak decay (~20 fps → halves in ~7 s). */
        private const val PEAK_DECAY = 0.995
        private val MIN_PEAK = ln(1.0 + 6.0)
        private const val MIN_RMS_PEAK = 0.05
    }

    private var starts = IntArray(count)
    private var ends = IntArray(count)
    private var configuredBins = -1
    private val out = DoubleArray(count)
    private var peak = MIN_PEAK
    private var rmsPeak = MIN_RMS_PEAK

    /** @param samplingRateMilliHz as reported by Visualizer (mHz); ≤ 0 means 44.1 kHz. */
    fun configure(captureSize: Int, samplingRateMilliHz: Int) {
        val n = max(captureSize, 4)
        val bins = n / 2 // usable bins 1 until bins (0 = DC, bins = Nyquist, both real-only)
        val sr = if (samplingRateMilliHz > 0) samplingRateMilliHz / 1000.0 else 44_100.0
        val binHz = sr / n
        val lo = (F_LO / binHz).roundToInt().coerceIn(1, bins - 1)
        val hi = (min(F_HI, sr / 2) / binHz).roundToInt().coerceIn(lo + 1, bins) // exclusive
        var prevEnd = lo
        for (i in 0 until count) {
            val start = prevEnd.coerceAtMost(hi - 1)
            val target = (lo * (hi.toDouble() / lo).pow((i + 1).toDouble() / count)).roundToInt()
            val end = max(target, start + 1).coerceAtMost(hi)
            starts[i] = start
            ends[i] = max(end, start + 1)
            prevEnd = ends[i]
        }
        configuredBins = bins
        reset()
    }

    fun reset() {
        out.fill(0.0)
        peak = MIN_PEAK
        rmsPeak = MIN_RMS_PEAK
    }

    fun process(fft: ByteArray): DoubleArray {
        if (configuredBins != fft.size / 2) configure(fft.size, 0)
        val raw = DoubleArray(count)
        var frameMax = 0.0
        for (i in 0 until count) {
            var m = 0.0
            for (k in starts[i] until ends[i]) {
                val idx = 2 * k
                if (idx + 1 >= fft.size) break
                val re = fft[idx].toDouble()
                val im = fft[idx + 1].toDouble()
                m = max(m, sqrt(re * re + im * im))
            }
            // Log compression + mild treble tilt (real music falls off ~ with frequency).
            val v = ln(1.0 + m) * (1.0 + 0.6 * i / (count - 1).coerceAtLeast(1))
            raw[i] = v
            frameMax = max(frameMax, v)
        }
        peak = max(max(frameMax, peak * PEAK_DECAY), MIN_PEAK)
        for (i in 0 until count) {
            val target = (raw[i] / peak).coerceIn(0.0, 1.0)
            val prev = out[i]
            out[i] = if (target >= prev) prev + (target - prev) * 0.7 else prev * 0.7 + target * 0.3
        }
        return out.copyOf()
    }

    /** RMS of an unsigned 8-bit waveform frame, auto-gained to 0..1. */
    fun rms(wave: ByteArray): Double {
        if (wave.isEmpty()) return 0.0
        var sum = 0.0
        for (b in wave) {
            val s = ((b.toInt() and 0xff) - 128) / 128.0
            sum += s * s
        }
        val r = sqrt(sum / wave.size)
        rmsPeak = max(max(r, rmsPeak * PEAK_DECAY), MIN_RMS_PEAK)
        return (r / rmsPeak).coerceIn(0.0, 1.0)
    }
}
