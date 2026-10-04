package com.santiagortega.pixelcarplayer

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * v3 (celular): métodos de `pcp/native` para emparejamiento y arranque automático
 * (docs/CONTRACT.md §1 v3, lib/data/bridge/native_bridge.dart "v3"). MainActivity delega aquí antes
 * de `notImplemented`.
 */
object PhoneFeatures {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool { r -> Thread(r, "pcp-phone").apply { isDaemon = true } }

    /** true si [call] es de este módulo (y ya respondió o responderá por [result]). */
    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result): Boolean {
        val ctx = activity.applicationContext
        when (call.method) {
            // ---- emparejamiento
            "getPairedCars" -> background(result) { PairingStore.list(ctx) }
            "forgetCar" -> {
                val id = call.argument<String>("id").orEmpty()
                background(result) {
                    if (id.isNotEmpty()) {
                        PairingStore.remove(ctx, id)
                        LinkDiag.log("emparejamiento: carro ${id.take(8)} olvidado")
                        TransmitterService.instance?.forgetCar(id)
                    }
                    null
                }
            }
            "submitPairCode" -> {
                val carId = call.argument<String>("carId").orEmpty()
                val code = LinkAuth.normalizeCode(call.argument<String>("code"))
                val svc = TransmitterService.instance
                result.success(carId.isNotEmpty() && code != null && svc != null && svc.submitPairCode(carId, code))
            }

            // ---- arranque automático
            "setAutoStartRules" -> {
                val rules = AutoStartRules.fromMap(call.arguments as? Map<*, *>)
                background(result) {
                    AutoStart.save(ctx, rules)
                    true
                }
            }
            "getAutoStartRules" -> background(result) {
                AutoStart.sync(ctx, force = false)
                AutoStart.load(ctx).toMap()
            }
            "getAutoStartStatus" -> background(result) { AutoStart.status(ctx) }
            "associateCarDevice" -> {
                val address = call.argument<String>("address")?.takeIf { it.isNotBlank() }
                    ?: AutoStart.load(ctx).btAddresses.firstOrNull()
                CarAssociateActivity.launch(activity, address) { r -> main.post { result.success(r) } }
            }
            else -> return false
        }
        return true
    }

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
                        Log.e(TAG, "phone call failed", it)
                        result.error("native_error", it.message, null)
                    },
                )
            }
        }
    }
}
