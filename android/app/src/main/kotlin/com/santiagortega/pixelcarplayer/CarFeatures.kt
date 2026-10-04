package com.santiagortega.pixelcarplayer

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Funciones v3 del lado tableta (mantener al frente, burbuja, conectividad) y compartidas
 * (actualizaciones, copias de seguridad). MainActivity delega aquí con una sola línea; devuelve true
 * si atendió el método.
 *
 * Prefs nativas: `SharedPreferences("pcp_car")` (ver CONTRACT §2 v3).
 */
object CarFeatures {
    const val PREFS = "pcp_car"
    const val K_KF_ENABLED = "keep_front_enabled"
    const val K_KF_PACKAGES = "keep_front_packages"
    const val K_KF_ANY = "keep_front_any_app"
    const val K_KF_DELAY = "keep_front_delay_ms"
    const val K_KF_LAUNCHER = "keep_front_include_launcher"
    const val K_BUBBLE_ENABLED = "bubble_enabled"
    const val K_BUBBLE_SIZE = "bubble_size"
    const val K_BUBBLE_OPACITY = "bubble_opacity"
    const val K_BUBBLE_TITLE = "bubble_show_title"
    const val K_BUBBLE_X = "bubble_x"
    const val K_BUBBLE_Y = "bubble_y"

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool { r -> Thread(r, "pcp-car").apply { isDaemon = true } }

    // ------------------------------------------------------------------ estado de nuestras Activities

    @Volatile private var lifecycleRegistered = false
    /** Cantidad de Activities nuestras en estado resumed (MainActivity o CarHelperActivity). */
    @Volatile private var resumedCount = 0
    @Volatile var mainTaskId: Int = -1
        private set
    /**
     * "Mantener al frente" en pausa: lo pusimos nosotros al abrir Ajustes, el instalador, el selector
     * de archivos, permisos o la app acompañante en primer plano. Se limpia cuando MainActivity vuelve.
     */
    @Volatile var keepFrontSuspended = false
        private set
    private val listeners = java.util.concurrent.CopyOnWriteArrayList<(Boolean) -> Unit>()

    val ownResumed: Boolean get() = resumedCount > 0

    fun addResumeListener(l: (Boolean) -> Unit) { listeners += l }
    fun removeResumeListener(l: (Boolean) -> Unit) { listeners -= l }

    /** Hasta cuándo (uptime) una salida de MainActivity cuenta como provocada por nosotros. */
    @Volatile private var suspendArmedUntil = 0L

    /**
     * Arma la pausa de "mantener al frente": si MainActivity deja de estar al frente en los próximos
     * [windowMs] (se abrió Ajustes, un diálogo, el instalador…), no se la vuelve a traer hasta que el
     * usuario regrese. Si ya no está al frente, la pausa es inmediata.
     */
    fun suspendKeepFront(reason: String, windowMs: Long = 8_000L) {
        Log.d(TAG, "keep-front: pausa armada ($reason)")
        suspendArmedUntil = android.os.SystemClock.uptimeMillis() + windowMs
        if (!ownResumed) keepFrontSuspended = true
    }

    /** Idempotente. Lo llaman handle() y KeepFrontService.onCreate (arranque sin Activity). */
    fun ensureLifecycle(ctx: Context, current: Activity? = null) {
        if (!lifecycleRegistered) {
            synchronized(this) {
                if (!lifecycleRegistered) {
                    val app = ctx.applicationContext as Application
                    app.registerActivityLifecycleCallbacks(Callbacks)
                    lifecycleRegistered = true
                    // Registrado tarde: si la Activity que llama ya está al frente, contarla.
                    if (current != null && isResumed(current)) {
                        resumedCount = 1
                        mainTaskId = current.taskId
                    }
                }
            }
        }
        if (current != null && current.taskId != -1) mainTaskId = current.taskId
    }

    private fun isResumed(a: Activity): Boolean =
        (a as? androidx.lifecycle.LifecycleOwner)?.lifecycle?.currentState
            ?.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)
            ?: a.hasWindowFocus()

    private object Callbacks : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(activity: Activity) {
            if (activity is MainActivity) {
                mainTaskId = activity.taskId
                keepFrontSuspended = false
                suspendArmedUntil = 0L
            }
            resumedCount = (resumedCount + 1).coerceAtMost(4)
            notifyListeners()
        }

        override fun onActivityPaused(activity: Activity) {
            if (activity is MainActivity && android.os.SystemClock.uptimeMillis() < suspendArmedUntil) {
                keepFrontSuspended = true
            }
            resumedCount = (resumedCount - 1).coerceAtLeast(0)
            notifyListeners()
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
        override fun onActivityDestroyed(activity: Activity) {}
    }

    private fun notifyListeners() {
        val v = ownResumed
        listeners.forEach { runCatching { it(v) } }
    }

    fun prefs(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ------------------------------------------------------------------ canal

    /** true si atendió [call]. Llamado desde MainActivity en el hilo principal. */
    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result): Boolean {
        val ctx = activity.applicationContext
        ensureLifecycle(ctx, activity)
        when (call.method) {
            // ---- métodos de MainActivity que sacan otra app al frente: pausar keep-front y seguir
            "openNotificationAccessSettings", "openOverlaySettings", "openBatteryOptimizationSettings",
            "openHotspotSettings", "openWriteSettings", "requestRuntimePermissions",
            "requestAudioPermission", "setHotspotEnabled" -> {
                suspendKeepFront(call.method)
                return false
            }
            "launchApp" -> {
                if (call.argument<Boolean>("background") == false) suspendKeepFront("launchApp")
                return false
            }

            // ---- versión y actualizaciones (ambos)
            "getAppVersion" -> result.success(AppUpdater.appVersion(ctx))
            "checkForUpdate" -> background(result) { AppUpdater.check(ctx) }
            "downloadAndInstallUpdate" -> {
                val url = call.argument<String>("apkUrl")
                if (url.isNullOrBlank()) result.success(false)
                else background(result) { AppUpdater.downloadAndInstall(ctx, url) }
            }
            "canInstallPackages" -> result.success(AppUpdater.canInstall(ctx))
            "openInstallPermissionSettings" -> {
                suspendKeepFront(call.method)
                AppUpdater.openInstallPermissionSettings(activity)
                result.success(null)
            }

            // ---- copias de seguridad (ambos)
            "saveBackupFile" -> {
                val json = call.argument<String>("json")
                val name = call.argument<String>("name") ?: BackupFiles.DEFAULT_NAME
                if (json == null) result.success(null) else BackupFiles.save(activity, json, name) { result.success(it) }
            }
            "pickBackupFile" -> {
                suspendKeepFront(call.method)
                BackupFiles.pick(activity) { result.success(it) }
            }

            // ---- tableta: conectividad
            "getConnectivityStatus" -> background(result) { ConnectivityWatch.status(ctx) }
            "startConnectivityWatch" -> {
                ConnectivityWatch.start(ctx)
                result.success(null)
            }
            "stopConnectivityWatch" -> {
                ConnectivityWatch.stop(ctx)
                result.success(null)
            }

            // ---- tableta: mantener al frente + burbuja
            "hasUsageAccess" -> result.success(hasUsageAccess(ctx))
            "openUsageAccessSettings" -> {
                suspendKeepFront(call.method)
                openUsageAccessSettings(activity)
                result.success(null)
            }
            "setKeepInFront" -> result.success(setKeepInFront(ctx, call))
            "setFloatingBubble" -> result.success(setFloatingBubble(ctx, call))
            "updateFloatingBubble" -> {
                FloatingBubble.setNowPlaying(
                    title = call.argument<String>("title") ?: "",
                    artist = call.argument<String>("artist") ?: "",
                    art = call.argument<ByteArray>("art"),
                    playing = call.argument<Boolean>("playing") ?: false,
                )
                result.success(null)
            }
            else -> return false
        }
        return true
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            val reply = runCatching(work)
            main.post {
                reply.fold(
                    onSuccess = { result.success(it) },
                    onFailure = {
                        Log.e(TAG, "car call failed", it)
                        result.error("native_error", it.message, null)
                    },
                )
            }
        }
    }

    // ------------------------------------------------------------------ mantener al frente

    fun hasUsageAccess(ctx: Context): Boolean = try {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        }
        if (mode == AppOpsManager.MODE_DEFAULT) {
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.PACKAGE_USAGE_STATS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            mode == AppOpsManager.MODE_ALLOWED
        }
    } catch (e: Exception) {
        Log.w(TAG, "hasUsageAccess failed", e)
        false
    }

    private fun openUsageAccessSettings(activity: Activity) {
        val attempts = listOf(
            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:${activity.packageName}")),
            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")),
        )
        for (i in attempts) {
            try {
                activity.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (e: Exception) {
                Log.d(TAG, "usage settings intent failed: ${i.action} ${i.data}")
            }
        }
    }

    fun keepFrontConfig(ctx: Context): KeepFrontPolicy.Config {
        val p = prefs(ctx)
        return KeepFrontPolicy.Config(
            enabled = p.getBoolean(K_KF_ENABLED, false),
            packages = p.getStringSet(K_KF_PACKAGES, emptySet())?.toSet() ?: emptySet(),
            anyApp = p.getBoolean(K_KF_ANY, false),
            delayMs = p.getLong(K_KF_DELAY, 1500L),
            includeLauncher = p.getBoolean(K_KF_LAUNCHER, false),
        )
    }

    private fun setKeepInFront(ctx: Context, call: MethodCall): Boolean {
        val enabled = call.argument<Boolean>("enabled") ?: false
        val packages = (call.argument<List<*>>("packages") ?: emptyList<Any>())
            .mapNotNull { (it as? String)?.trim()?.ifEmpty { null } }
            .filter { it != ctx.packageName }
            .toSet()
        val anyApp = call.argument<Boolean>("anyApp") ?: false
        val delay = (call.argument<Number>("delayMs")?.toLong() ?: 1500L).coerceIn(0L, 60_000L)
        val p = prefs(ctx).edit()
            .putBoolean(K_KF_ENABLED, enabled)
            .putStringSet(K_KF_PACKAGES, packages)
            .putBoolean(K_KF_ANY, anyApp)
            .putLong(K_KF_DELAY, delay)
        if (call.hasArgument("includeLauncher")) p.putBoolean(K_KF_LAUNCHER, call.argument<Boolean>("includeLauncher") == true)
        p.apply()
        return KeepFrontService.sync(ctx) || !enabled
    }

    private fun setFloatingBubble(ctx: Context, call: MethodCall): Boolean {
        val enabled = call.argument<Boolean>("enabled") ?: false
        val size = (call.argument<Number>("size")?.toInt() ?: 64).coerceIn(40, 160)
        val opacity = (call.argument<Number>("opacity")?.toFloat() ?: 0.95f).coerceIn(0.2f, 1f)
        val e = prefs(ctx).edit()
            .putBoolean(K_BUBBLE_ENABLED, enabled)
            .putInt(K_BUBBLE_SIZE, size)
            .putFloat(K_BUBBLE_OPACITY, opacity)
        if (call.hasArgument("showTitle")) e.putBoolean(K_BUBBLE_TITLE, call.argument<Boolean>("showTitle") != false)
        e.apply()
        if (!enabled) {
            KeepFrontService.sync(ctx)
            return true
        }
        if (!FloatingBubble.canDraw(ctx)) {
            Log.w(TAG, "setFloatingBubble: falta permiso de superposición")
            KeepFrontService.sync(ctx)
            return false
        }
        return KeepFrontService.sync(ctx)
    }

    /** Arranque / app actualizada: reanudar el servicio si alguna función quedó activa. */
    fun restoreOnBoot(ctx: Context) {
        try {
            val p = prefs(ctx)
            if (p.getBoolean(K_KF_ENABLED, false) || p.getBoolean(K_BUBBLE_ENABLED, false)) {
                Log.i(TAG, "restaurando servicio mantener-al-frente/burbuja")
                KeepFrontService.sync(ctx)
            }
        } catch (e: Exception) {
            Log.w(TAG, "restoreOnBoot failed", e)
        }
    }
}
