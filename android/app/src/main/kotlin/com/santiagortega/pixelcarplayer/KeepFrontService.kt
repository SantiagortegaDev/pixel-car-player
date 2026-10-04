package com.santiagortega.pixelcarplayer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Servicio en primer plano de la tableta para "mantener al frente" y la burbuja flotante.
 *
 * Cada ~1 s mira la app en primer plano (UsageStatsManager.queryEvents, requiere acceso de uso) y,
 * si una app de la lista (o cualquiera con anyApp) tapa a Pixel Car Player, espera delayMs y la
 * vuelve a traer (AppLauncher.bringToFront). Sin acceso de uso y con anyApp, se usa el respaldo
 * "MainActivity dejó de estar al frente".
 */
class KeepFrontService : Service() {

    companion object {
        private const val CHANNEL_ID = "pcp_keep_front"
        private const val NOTIFICATION_ID = 47325
        private const val POLL_MS = 1000L
        private const val LOOKBACK_MS = 10_000L
        private const val LAUNCHERS_TTL_MS = 60_000L

        /** Arranca o detiene el servicio según las prefs. true si queda corriendo. */
        fun sync(ctx: Context): Boolean {
            val app = ctx.applicationContext
            val p = CarFeatures.prefs(app)
            val wanted = p.getBoolean(CarFeatures.K_KF_ENABLED, false) ||
                (p.getBoolean(CarFeatures.K_BUBBLE_ENABLED, false) && FloatingBubble.canDraw(app))
            return try {
                if (wanted) {
                    ContextCompat.startForegroundService(app, Intent(app, KeepFrontService::class.java))
                    true
                } else {
                    app.stopService(Intent(app, KeepFrontService::class.java))
                    false
                }
            } catch (e: Exception) {
                Log.w(TAG, "KeepFrontService sync failed", e)
                false
            }
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var worker: HandlerThread? = null
    private var workerHandler: Handler? = null
    private val policy = KeepFrontPolicy()
    private var lastFg: String? = null
    private var lastQueryEnd = 0L
    private var launchers: Set<String> = emptySet()
    private var launchersAt = 0L
    private var bubble: FloatingBubble? = null
    private val resumeListener: (Boolean) -> Unit = { resumed ->
        main.post { updateBubbleVisibility(resumed) }
        workerHandler?.post { if (resumed) policy.reset() }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        CarFeatures.ensureLifecycle(this)
        CarFeatures.addResumeListener(resumeListener)
        worker = HandlerThread("pcp-keep-front").also { it.start() }
        workerHandler = Handler(worker!!.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!startInForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }
        applyConfig()
        return START_STICKY
    }

    override fun onDestroy() {
        CarFeatures.removeResumeListener(resumeListener)
        workerHandler?.removeCallbacksAndMessages(null)
        worker?.quitSafely()
        worker = null
        workerHandler = null
        bubble?.remove()
        bubble = null
        super.onDestroy()
    }

    /** Relee las prefs (llamado en cada startForegroundService). */
    private fun applyConfig() {
        val cfg = CarFeatures.keepFrontConfig(this)
        val p = CarFeatures.prefs(this)
        val bubbleOn = p.getBoolean(CarFeatures.K_BUBBLE_ENABLED, false) && FloatingBubble.canDraw(this)
        if (!cfg.enabled && !bubbleOn) {
            stopSelf()
            return
        }
        workerHandler?.post {
            policy.config = cfg
            policy.reset()
            workerHandler?.removeCallbacks(pollRunnable)
            if (cfg.enabled) workerHandler?.post(pollRunnable)
        }
        main.post {
            if (bubbleOn) {
                val b = bubble ?: FloatingBubble(this).also { bubble = it }
                b.configure(
                    sizeDp = p.getInt(CarFeatures.K_BUBBLE_SIZE, 64),
                    opacity = p.getFloat(CarFeatures.K_BUBBLE_OPACITY, 0.95f),
                    showTitle = p.getBoolean(CarFeatures.K_BUBBLE_TITLE, true),
                )
                updateBubbleVisibility(CarFeatures.ownResumed)
            } else {
                bubble?.remove()
                bubble = null
            }
        }
    }

    private fun updateBubbleVisibility(ownResumed: Boolean) {
        val b = bubble ?: return
        if (ownResumed) b.hide() else b.show()
    }

    // ------------------------------------------------------------------ sondeo

    private val pollRunnable = object : Runnable {
        override fun run() {
            var next = POLL_MS
            try {
                next = poll()
            } catch (e: Exception) {
                Log.w(TAG, "keep-front poll failed", e)
            }
            if (policy.config.enabled) workerHandler?.postDelayed(this, next.coerceIn(100L, POLL_MS))
        }
    }

    /** Un sondeo en el hilo worker; devuelve cuántos ms esperar al siguiente. */
    private fun poll(): Long {
        val now = System.currentTimeMillis()
        val uptime = android.os.SystemClock.uptimeMillis()
        val usage = CarFeatures.hasUsageAccess(this)
        val fg: String? = if (usage) {
            foregroundPackage(now)
        } else {
            // Sin acceso de uso no se sabe qué app está: solo vale "cualquier app" y que la nuestra no esté.
            if (CarFeatures.ownResumed) packageName else KeepFrontPolicy.UNKNOWN
        }
        if (uptime - launchersAt > LAUNCHERS_TTL_MS) {
            launchers = homePackages()
            launchersAt = uptime
        }
        val pull = policy.tick(
            now = uptime,
            fg = fg,
            ownPkg = packageName,
            ownResumed = CarFeatures.ownResumed,
            suspended = CarFeatures.keepFrontSuspended,
            launchers = launchers,
        )
        if (pull) {
            Log.i(TAG, "keep-front: $fg tapó a Pixel Car Player, volviendo al frente")
            main.post { AppLauncher.bringToFront(applicationContext, CarFeatures.mainTaskId.takeIf { it != -1 }) }
        }
        return policy.msUntilDue(uptime) ?: POLL_MS
    }

    private fun foregroundPackage(now: Long): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return lastFg
        val begin = if (lastQueryEnd == 0L) now - LOOKBACK_MS else lastQueryEnd - 2_000L
        val events = ArrayList<UsageEv>()
        try {
            val it = usm.queryEvents(begin, now) ?: return lastFg
            val e = UsageEvents.Event()
            while (it.hasNextEvent()) {
                it.getNextEvent(e)
                val type = e.eventType
                if (type == ForegroundEvents.RESUMED || type == ForegroundEvents.PAUSED) {
                    events += UsageEv(e.timeStamp, type, e.packageName ?: continue)
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "queryEvents failed: ${e.message}")
            return lastFg
        }
        lastQueryEnd = now
        lastFg = ForegroundEvents.latestForeground(events, lastFg)
        return lastFg
    }

    private fun homePackages(): Set<String> = try {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        @Suppress("DEPRECATION")
        packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .mapNotNull { it.activityInfo?.packageName }
            .filter { it != packageName }
            .toSet()
    } catch (e: Exception) {
        emptySet()
    }

    // ------------------------------------------------------------------ notificación

    private fun startInForeground(): Boolean = try {
        createChannel()
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_pcp)
            .setContentTitle("Pixel Car Player se mantiene al frente")
            .setContentText("Vuelve a la pantalla del reproductor cuando otra app la tapa")
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        true
    } catch (e: Exception) {
        Log.e(TAG, "KeepFrontService startForeground failed", e)
        false
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Mantener al frente", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Vuelve a traer Pixel Car Player cuando otra app la tapa y muestra la burbuja"
                setShowBadge(false)
            }
        )
    }
}
