package com.santiagortega.pixelcarplayer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log

/**
 * Opens the app when the head unit powers on ("inicio automático").
 * Reads Flutter SharedPreferences: app_mode == "car", car_autostart == true,
 * optional car_autostart_delay (seconds, default 3).
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        try {
            val prefs = context.applicationContext
                .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val mode = prefs.getString("flutter.app_mode", null)
            val enabled = prefs.getBoolean("flutter.car_autostart", false)
            if (mode != "car" || !enabled) {
                Log.i(TAG, "BootReceiver($action): autostart off (mode=$mode enabled=$enabled)")
                return
            }
            val delaySec = try {
                (prefs.all["flutter.car_autostart_delay"] as? Number)?.toLong() ?: 3L
            } catch (_: Exception) {
                3L
            }.coerceIn(0L, 120L)
            Log.i(TAG, "BootReceiver($action): launching in ${delaySec}s")

            val app = context.applicationContext
            val pending = goAsync()
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    launch(app)
                } finally {
                    try { pending.finish() } catch (_: Exception) {}
                }
            }, delaySec * 1000L)
        } catch (e: Exception) {
            Log.w(TAG, "BootReceiver failed", e)
        }
    }

    private fun launch(ctx: Context) {
        try {
            val canOverlay = Settings.canDrawOverlays(ctx)
            if (!canOverlay) Log.w(TAG, "BootReceiver: overlay permission missing, trying anyway")
            val i = Intent(ctx, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            }
            ctx.startActivity(i)
        } catch (e: Exception) {
            Log.w(TAG, "BootReceiver: startActivity failed", e)
        }
    }
}
