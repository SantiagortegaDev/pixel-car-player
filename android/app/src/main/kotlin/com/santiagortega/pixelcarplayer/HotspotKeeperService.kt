package com.santiagortega.pixelcarplayer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the process at foreground-service importance while a LocalOnlyHotspot reservation is held:
 * the system tears the local-only hotspot down as soon as the requesting app drops below that
 * importance (e.g. when the companion app is opened on top).
 */
class HotspotKeeperService : Service() {

    companion object {
        private const val CHANNEL_ID = "pcp_hotspot"
        private const val NOTIFICATION_ID = 47323

        fun start(context: Context) {
            try {
                ContextCompat.startForegroundService(context, Intent(context, HotspotKeeperService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "HotspotKeeperService start failed", e)
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, HotspotKeeperService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "HotspotKeeperService stop failed", e)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            createChannel()
            val open = PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_pcp)
                .setContentTitle("Hotspot del carro activo")
                .setContentText("El celular puede conectarse a esta pantalla")
                .setContentIntent(open)
                .setOngoing(true)
                .setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .build()
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            } else {
                0
            }
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        } catch (e: Exception) {
            Log.e(TAG, "HotspotKeeperService startForeground failed", e)
            stopSelf()
        }
        // The reservation dies with the process; nothing to restore after a restart.
        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Hotspot del carro", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Mantiene encendido el hotspot local mientras la app está detrás"
                setShowBadge(false)
            }
        )
    }
}
