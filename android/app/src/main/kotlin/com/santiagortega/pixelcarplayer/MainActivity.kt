package com.santiagortega.pixelcarplayer

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val PERMISSION_REQUEST_BASE = 4732
        /** Extra que pone BootReceiver: la app acompañante ya se abrió al encender. */
        const val EXTRA_FROM_BOOT = "pcp_from_boot"
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool { r -> Thread(r, "pcp-io").apply { isDaemon = true } }
    /** requestCode → continuation, run on the main thread once the dialog answers. */
    private val permissionCallbacks = HashMap<Int, () -> Unit>()
    private var nextPermissionRequest = PERMISSION_REQUEST_BASE
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "pcp/native").setMethodCallHandler(::onMethodCall)
        EventChannel(messenger, "pcp/events").setStreamHandler(EventHub)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        EventHub.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        releaseMulticastLock()
        AudioViz.stop()
        val pending = permissionCallbacks.values.toList()
        permissionCallbacks.clear()
        pending.forEach { runCatching(it) }
        super.onDestroy()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            handle(call, result)
        } catch (e: Exception) {
            Log.e(TAG, "Method ${call.method} failed", e)
            result.error("native_error", e.message, null)
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val ctx: Context = applicationContext
        when (call.method) {
            // ---- both sides
            "getDeviceInfo" -> result.success(
                mapOf(
                    "model" to Build.MODEL,
                    "manufacturer" to Build.MANUFACTURER,
                    "sdkInt" to Build.VERSION.SDK_INT,
                )
            )
            "hasNotificationAccess" -> result.success(MediaListenerService.hasAccess(ctx))
            "openNotificationAccessSettings" -> {
                MediaListenerService.openSettings(this)
                result.success(null)
            }
            "requestRuntimePermissions" -> requestRuntimePermissions(result)
            "canDrawOverlays" -> result.success(
                Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)
            )
            "openOverlaySettings" -> {
                openSettingsSafely(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")),
                    appDetailsFallback = true,
                )
                result.success(null)
            }
            "openBatteryOptimizationSettings" -> {
                openSettingsSafely(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                    appDetailsFallback = true,
                )
                result.success(null)
            }
            "getLocalIps" -> background(result) { NetUtils.localIps() }
            "getLinkDiagnostics" -> background(result) { TransmitterService.linkDiagnostics(ctx) }
            "clearLinkDiagnostics" -> {
                LinkDiag.clear()
                result.success(null)
            }
            "getWifiNetworks" -> background(result) { TransmitterService.wifiNetworks(ctx) }

            // ---- phone (transmitter)
            "startTransmitter" -> {
                // An explicit null means "any music app"; a missing argument means the default.
                val src: String? = if (call.hasArgument("sourcePackage")) {
                    call.argument<String>("sourcePackage")
                } else {
                    TransmitterService.DEFAULT_SOURCE
                }
                result.success(TransmitterService.start(ctx, src))
            }
            "stopTransmitter" -> {
                TransmitterService.stop(ctx)
                result.success(null)
            }
            "getTransmitterStatus" -> background(result) { TransmitterService.status() }

            // ---- car (screen)
            "setKeepScreenOn" -> {
                val on = call.argument<Boolean>("on") ?: true
                runOnUiThread {
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
            "getGatewayIp" -> background(result) { NetUtils.gatewayIp(ctx) }
            "acquireMulticastLock" -> {
                acquireMulticastLock()
                result.success(null)
            }
            "releaseMulticastLock" -> {
                releaseMulticastLock()
                result.success(null)
            }
            "getBondedDevices" -> background(result) { Bt.bondedDevices(ctx) }
            "connectRfcomm" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrBlank()) result.success(false)
                else background(result) { RfcommClient.connect(ctx, address) }
            }
            "sendRfcomm" -> {
                val line = call.argument<String>("line")
                if (line == null) result.success(false)
                else background(result) { RfcommClient.send(line) }
            }
            "disconnectRfcomm" -> background(result) {
                RfcommClient.disconnect()
                null
            }
            "startLocalMediaWatch" -> result.success(LocalMediaWatch.start(ctx))
            "stopLocalMediaWatch" -> {
                LocalMediaWatch.stop()
                result.success(null)
            }
            "localMediaCommand" -> {
                val action = call.argument<String>("action") ?: ""
                val pos = call.argument<Number>("positionMs")?.toLong()
                background(result) { LocalMediaWatch.command(ctx, action, pos) }
            }

            // ---- car: hotspot
            "getHotspotState" -> background(result) { Hotspot.state(ctx) }
            "setHotspotEnabled" -> setHotspotEnabled(
                call.argument<Boolean>("enabled") ?: true,
                call.argument<Boolean>("allowLocalOnly") ?: false,
                result,
            )
            "openHotspotSettings" -> {
                Hotspot.openSettings(this)
                result.success(null)
            }
            "openWriteSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    openSettingsSafely(
                        Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:$packageName")),
                        appDetailsFallback = true,
                    )
                }
                result.success(null)
            }
            "getNeighborIps" -> background(result) { NetUtils.neighborIps() }

            // ---- car: real-audio visualizer
            "requestAudioPermission" -> withPermissions(listOf(Manifest.permission.RECORD_AUDIO)) {
                result.success(isGranted(Manifest.permission.RECORD_AUDIO))
            }
            "startVisualizer" -> result.success(AudioViz.start(this))
            "stopVisualizer" -> {
                AudioViz.stop()
                result.success(null)
            }

            // ---- car: companion app
            "getLaunchableApps" -> background(result) { AppLauncher.launchableApps(ctx) }
            "launchApp" -> {
                val pkg = call.argument<String>("package")
                val bg = call.argument<Boolean>("background") ?: true
                val delay = (call.argument<Number>("delayMs")?.toLong() ?: 1500L).coerceIn(0L, 60_000L)
                if (pkg.isNullOrBlank()) {
                    result.success(false)
                } else {
                    val ok = AppLauncher.launch(this, pkg)
                    if (ok && bg) {
                        val task = taskId
                        main.postDelayed({ AppLauncher.bringToFront(ctx, task) }, delay)
                    }
                    result.success(ok)
                }
            }
            "consumeBootLaunch" -> {
                val fromBoot = intent?.getBooleanExtra(EXTRA_FROM_BOOT, false) == true
                intent?.removeExtra(EXTRA_FROM_BOOT)
                result.success(fromBoot)
            }
            "bringToFront" -> {
                AppLauncher.bringToFront(ctx, taskId)
                result.success(null)
            }

            // ---- phone: auto-join the car hotspot
            "setHotspotAutoConnect" -> {
                val ssid = call.argument<String>("ssid") ?: ""
                val password = call.argument<String>("password") ?: ""
                val enabled = call.argument<Boolean>("enabled") ?: true
                background(result) { WifiJoin.setAutoConnect(ctx, ssid, password, enabled) }
            }
            "getWifiStatus" -> background(result) { WifiJoin.status(ctx) }

            else -> result.notImplemented()
        }
    }

    /**
     * System paths (tethering / wifiAp) off the main thread. Only with [allowLocalOnly] does a failed
     * enable fall back to a LocalOnlyHotspot (random SSID/password, not the one configured in the
     * head unit's settings), after asking for the runtime permissions it needs.
     */
    private fun setHotspotEnabled(enabled: Boolean, allowLocalOnly: Boolean, result: MethodChannel.Result) {
        val ctx = applicationContext
        io.execute {
            val first = try {
                Hotspot.setEnabled(ctx, enabled)
            } catch (e: Throwable) {
                Log.e(TAG, "setHotspotEnabled failed", e)
                mapOf("ok" to false, "method" to "none", "needsSettings" to true, "error" to e.message)
            }
            if (first["ok"] == true || !enabled || !allowLocalOnly || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                main.post { result.success(first) }
                return@execute
            }
            main.post {
                val perms = Hotspot.localOnlyPermissions()
                withPermissions(perms) {
                    val granted = perms.all(::isGranted)
                    background(result) { Hotspot.startLocalOnly(ctx, granted) }
                }
            }
        }
    }

    /** Runs [work] off the main thread and replies on the main thread. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            val reply = try {
                Result.success(work())
            } catch (e: Throwable) {
                Result.failure(e)
            }
            main.post {
                reply.fold(
                    onSuccess = { result.success(it) },
                    onFailure = {
                        Log.e(TAG, "background call failed", it)
                        result.error("native_error", it.message, null)
                    },
                )
            }
        }
    }

    private fun openSettingsSafely(intent: Intent, appDetailsFallback: Boolean) {
        try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "settings intent not found: ${intent.action}", e)
            if (!appDetailsFallback) return
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (e2: Exception) {
                Log.w(TAG, "app details settings failed", e2)
            }
        }
    }

    // ------------------------------------------------------------------ permissions

    private fun isGranted(permission: String) =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun permissionState(): Map<String, Boolean> = mapOf(
        "bluetoothConnect" to Bt.hasConnectPermission(this),
        "postNotifications" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            isGranted(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        },
    )

    private fun requestRuntimePermissions(result: MethodChannel.Result) {
        val wanted = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(Manifest.permission.BLUETOOTH_CONNECT)
        }
        withPermissions(wanted) { result.success(permissionState()) }
    }

    /**
     * Requests the missing [permissions] (main thread) and then runs [done] exactly once, whatever
     * the user answered (callers re-check with [isGranted]). Also runs if the activity is destroyed.
     */
    private fun withPermissions(permissions: List<String>, done: () -> Unit) {
        val missing = permissions.filterNot(::isGranted)
        if (missing.isEmpty()) {
            done()
            return
        }
        val code = nextPermissionRequest++
        if (nextPermissionRequest > PERMISSION_REQUEST_BASE + 1000) nextPermissionRequest = PERMISSION_REQUEST_BASE
        permissionCallbacks[code] = done
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), code)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        permissionCallbacks.remove(requestCode)?.let { runCatching(it).onFailure { e -> Log.w(TAG, "permission callback failed", e) } }
    }

    // ------------------------------------------------------------------ multicast

    private fun acquireMulticastLock() {
        try {
            if (multicastLock?.isHeld == true) return
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
            multicastLock = wm.createMulticastLock("PixelCarPlayer:discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
            LinkDiag.log("multicast lock adquirido")
        } catch (e: Exception) {
            Log.w(TAG, "multicast lock failed", e)
            LinkDiag.log("multicast lock falló: ${LinkDiag.errClass(e)}")
        }
    }

    private fun releaseMulticastLock() {
        try {
            if (multicastLock?.isHeld == true) LinkDiag.log("multicast lock liberado")
            multicastLock?.takeIf { it.isHeld }?.release()
        } catch (_: Exception) {
        }
        multicastLock = null
    }
}
