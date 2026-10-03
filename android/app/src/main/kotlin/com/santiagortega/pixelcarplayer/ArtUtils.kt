package com.santiagortega.pixelcarplayer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

object ArtUtils {
    const val MAX_SIZE = 640
    private const val JPEG_QUALITY = 85

    /** Scales [bitmap] so its longest side is ≤ [MAX_SIZE] and encodes it as JPEG q85. */
    fun toJpeg(bitmap: Bitmap): ByteArray? = try {
        var src = bitmap
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && src.config == Bitmap.Config.HARDWARE) {
            src = src.copy(Bitmap.Config.ARGB_8888, false)
        }
        val w = src.width
        val h = src.height
        if (w <= 0 || h <= 0) {
            null
        } else {
            val scale = minOf(1f, MAX_SIZE.toFloat() / maxOf(w, h))
            val scaled = if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    src, maxOf(1, (w * scale).toInt()), maxOf(1, (h * scale).toInt()), true
                )
            } else {
                src
            }
            ByteArrayOutputStream(64 * 1024).use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
                out.toByteArray()
            }
        }
    } catch (e: Throwable) { // includes OutOfMemoryError on low-end head units
        Log.w(TAG, "Art encoding failed", e)
        null
    }

    /** Loads an image from a content/file/resource or http(s) URI. Blocking: call off the main thread. */
    fun loadUri(context: Context, uriString: String): Bitmap? = try {
        val uri = Uri.parse(uriString)
        when (uri.scheme?.lowercase()) {
            "http", "https" -> download(uriString)
            else -> context.contentResolver.openInputStream(uri)?.use { decodeBounded(it.readBytes()) }
        }
    } catch (e: Throwable) {
        Log.w(TAG, "Cannot load art $uriString: ${e.message}")
        null
    }

    private fun download(url: String): Bitmap? {
        val conn = URL(url).openConnection() as HttpURLConnection
        return try {
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.instanceFollowRedirects = true
            if (conn.responseCode !in 200..299) return null
            conn.inputStream.use { stream: InputStream -> decodeBounded(stream.readBytes()) }
        } finally {
            conn.disconnect()
        }
    }

    /** Decodes with inSampleSize so huge images never blow the heap. */
    private fun decodeBounded(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= MAX_SIZE && bounds.outHeight / (sample * 2) >= MAX_SIZE) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    }
}
