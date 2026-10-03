package com.santiagortega.pixelcarplayer

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Log
import java.io.ByteArrayOutputStream
import java.text.Collator

/** Companion app (e.g. the head unit's Bluetooth music app): listing, launching, coming back. */
object AppLauncher {
    private const val ICON_PX = 96

    /** `[{package, label, icon: PNG bytes?}]` sorted by label. Blocking: call off the main thread. */
    fun launchableApps(ctx: Context): List<Map<String, Any?>> {
        val pm = ctx.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val infos: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
        val collator = Collator.getInstance()
        return infos
            .filter { it.activityInfo?.packageName != null && it.activityInfo.packageName != ctx.packageName }
            .distinctBy { it.activityInfo.packageName }
            .map { ri ->
                val label = runCatching { ri.loadLabel(pm).toString() }.getOrNull()
                    ?.takeIf { it.isNotBlank() } ?: ri.activityInfo.packageName
                val icon = runCatching { iconPng(ri.loadIcon(pm)) }
                    .onFailure { Log.d(TAG, "icon failed for ${ri.activityInfo.packageName}: ${it.message}") }
                    .getOrNull()
                mapOf("package" to ri.activityInfo.packageName, "label" to label, "icon" to icon)
            }
            .sortedWith { a, b -> collator.compare(a["label"] as String, b["label"] as String) }
    }

    private fun iconPng(d: Drawable): ByteArray {
        val bmp = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val drawable = d.mutate()
        drawable.setBounds(0, 0, ICON_PX, ICON_PX)
        drawable.draw(canvas)
        return ByteArrayOutputStream().use { out ->
            bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
            bmp.recycle()
            out.toByteArray()
        }
    }

    fun launchIntent(ctx: Context, pkg: String): Intent? {
        val pm = ctx.packageManager
        return (pm.getLaunchIntentForPackage(pkg) ?: pm.getLeanbackLaunchIntentForPackage(pkg))
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /** Starts [pkg]'s launcher activity. false if it has none or the start failed. */
    fun launch(ctx: Context, pkg: String): Boolean {
        val intent = launchIntent(ctx, pkg) ?: run {
            Log.w(TAG, "no launch intent for $pkg")
            return false
        }
        return try {
            ctx.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "launch $pkg failed", e)
            false
        }
    }

    /**
     * Brings MainActivity back to the front. Android 10+ silently drops background activity starts
     * unless the app holds "display over other apps" (or is within the post-launch grace period), so
     * this also tries ActivityManager.moveTaskToFront (REORDER_TASKS) when the task id is known.
     */
    fun bringToFront(ctx: Context, taskId: Int?): Boolean {
        var ok = false
        try {
            ctx.startActivity(
                Intent(ctx, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            )
            ok = true
        } catch (e: Exception) {
            Log.w(TAG, "bringToFront startActivity failed", e)
        }
        if (taskId != null && taskId != -1) {
            try {
                val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                am?.moveTaskToFront(taskId, 0)
                ok = true
            } catch (e: Exception) {
                Log.w(TAG, "moveTaskToFront failed", e)
            }
        }
        return ok
    }
}
