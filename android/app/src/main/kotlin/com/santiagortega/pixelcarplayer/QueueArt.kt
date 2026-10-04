package com.santiagortega.pixelcarplayer

import android.graphics.Bitmap
import android.os.Build
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream

/** v3: miniaturas de la cola (`queue.items[].art`): JPEG de 96 px (lado mayor) en base64. */
object QueueArt {
    const val SIZE = 96
    private const val QUALITY = 80

    fun encode(bitmap: Bitmap): String? = try {
        var src = bitmap
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && src.config == Bitmap.Config.HARDWARE) {
            src = src.copy(Bitmap.Config.ARGB_8888, false)
        }
        val w = src.width
        val h = src.height
        if (w <= 0 || h <= 0) {
            null
        } else {
            val scale = minOf(1f, SIZE.toFloat() / maxOf(w, h))
            val scaled = if (scale < 1f) {
                Bitmap.createScaledBitmap(src, maxOf(1, (w * scale).toInt()), maxOf(1, (h * scale).toInt()), true)
            } else {
                src
            }
            val bytes = ByteArrayOutputStream(8 * 1024).use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, QUALITY, out)
                out.toByteArray()
            }
            Base64.encodeToString(bytes, Base64.NO_WRAP)
        }
    } catch (e: Throwable) {
        Log.w(TAG, "queue art encoding failed", e)
        null
    }
}
