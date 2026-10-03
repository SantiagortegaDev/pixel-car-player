package com.santiagortega.pixelcarplayer

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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

    private companion object {
        const val PERMISSION_REQUEST = 4732
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool { r -> Thread(r, "pcp-io").apply { isDaemon = true } }
    private var pendingPermissionResult: MethodChannel.Result? = null
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
        pendingPermissionResult?.success(permissionState())
        pendingPermissionResult = null
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
            "getLocalIps" -> background(result) { NetUtils.localIps() }

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
            else -> result.notImplemented()
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
        }.filterNot(::isGranted)
        if (wanted.isEmpty()) {
            result.success(permissionState())
            return
        }
        // A previous request still pending: answer it with the current state.
        pendingPermissionResult?.success(permissionState())
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, wanted.toTypedArray(), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        pendingPermissionResult?.success(permissionState())
        pendingPermissionResult = null
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
        } catch (e: Exception) {
            Log.w(TAG, "multicast lock failed", e)
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.takeIf { it.isHeld }?.release()
        } catch (_: Exception) {
        }
        multicastLock = null
    }
}
