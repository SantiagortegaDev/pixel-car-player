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
 * Optional companion app: car_companion_package (String) is launched first and MainActivity follows
 * car_companion_delay ms later (Long, default 1500) so ours ends up in front.
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
            val companion = prefs.getString("flutter.car_companion_package", null)?.trim()?.ifEmpty { null }
            val companionDelayMs = try {
                (prefs.all["flutter.car_companion_delay"] as? Number)?.toLong() ?: 1500L
            } catch (_: Exception) {
                1500L
            }.coerceIn(0L, 30_000L)
            Log.i(TAG, "BootReceiver($action): launching in ${delaySec}s (companion=$companion)")

            val app = context.applicationContext
            val pending = goAsync()
            val handler = Handler(Looper.getMainLooper())
            val finish = { try { pending.finish() } catch (_: Exception) {} }
            handler.postDelayed({
                try {
                    if (companion != null && AppLauncher.launch(app, companion)) {
                        handler.postDelayed({
                            try {
                                launch(app)
                            } finally {
                                finish()
                            }
                        }, companionDelayMs)
                    } else {
                        try {
                            launch(app)
                        } finally {
                            finish()
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "BootReceiver launch failed", e)
                    finish()
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
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
            }
            ctx.startActivity(i)
        } catch (e: Exception) {
            Log.w(TAG, "BootReceiver: startActivity failed", e)
        }
    }
}
