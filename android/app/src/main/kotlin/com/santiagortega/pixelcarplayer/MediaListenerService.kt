package com.santiagortega.pixelcarplayer

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.util.Log
import androidx.core.app.NotificationManagerCompat

/**
 * Empty notification listener. Its only purpose is to grant us the right to call
 * `MediaSessionManager.getActiveSessions(ComponentName)` once the user enables
 * "Notification access" for the app.
 */
class MediaListenerService : NotificationListenerService() {

    override fun onListenerConnected() {
        Log.i(TAG, "Notification listener connected")
    }

    override fun onListenerDisconnected() {
        Log.i(TAG, "Notification listener disconnected; requesting rebind")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                requestRebind(componentName(this))
            } catch (e: Exception) {
                Log.w(TAG, "requestRebind failed", e)
            }
        }
    }

    companion object {
        fun componentName(context: Context) =
            ComponentName(context, MediaListenerService::class.java)

        fun hasAccess(context: Context): Boolean {
            val pkg = context.packageName
            try {
                if (NotificationManagerCompat.getEnabledListenerPackages(context).contains(pkg)) {
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "getEnabledListenerPackages failed", e)
            }
            return try {
                val flat = Settings.Secure.getString(
                    context.contentResolver, "enabled_notification_listeners"
                ) ?: return false
                flat.split(':').any { ComponentName.unflattenFromString(it)?.packageName == pkg }
            } catch (e: Exception) {
                false
            }
        }

        fun openSettings(context: Context) {
            val intents = listOf(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS),
                Intent(Settings.ACTION_SETTINGS),
            )
            for (intent in intents) {
                try {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    return
                } catch (e: Exception) {
                    Log.w(TAG, "Cannot open ${intent.action}", e)
                }
            }
        }
    }
}
