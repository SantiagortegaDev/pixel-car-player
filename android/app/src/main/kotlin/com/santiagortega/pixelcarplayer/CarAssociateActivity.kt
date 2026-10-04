package com.santiagortega.pixelcarplayer

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.companion.AssociationInfo
import android.companion.AssociationRequest
import android.companion.BluetoothDeviceFilter
import android.companion.CompanionDeviceManager
import android.content.Intent
import android.content.IntentSender
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.content.IntentCompat

/**
 * v3 (celular): actividad transparente que muestra el diálogo de asociación de
 * CompanionDeviceManager para el Bluetooth del carro (`associateCarDevice`) y recibe su resultado
 * (`startIntentSenderForResult` → [onActivityResult]). Separada de MainActivity para no tocar su
 * `onActivityResult`. Responde una sola vez por [pending] en el hilo principal.
 */
class CarAssociateActivity : Activity() {

    companion object {
        private const val EXTRA_ADDRESS = "address"
        private const val REQUEST = 4790

        /** Respuesta pendiente de `associateCarDevice` (hilo principal). */
        private var pending: ((Map<String, Any?>) -> Unit)? = null

        fun launch(activity: Activity, address: String?, reply: (Map<String, Any?>) -> Unit) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                reply(mapOf("ok" to false, "error" to "unsupported"))
                return
            }
            pending?.invoke(mapOf("ok" to false, "error" to "superseded"))
            pending = reply
            try {
                activity.startActivity(
                    Intent(activity, CarAssociateActivity::class.java).putExtra(EXTRA_ADDRESS, address)
                )
            } catch (e: Exception) {
                deliver(mapOf("ok" to false, "error" to (e.message ?: "launch")))
            }
        }

        private fun deliver(r: Map<String, Any?>) {
            val p = pending ?: return
            pending = null
            runCatching { p(r) }
        }
    }

    private var address: String? = null
    private var launched = false
    private var done = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        address = AutoStartRules.normMac(intent?.getStringExtra(EXTRA_ADDRESS))
        if (savedInstanceState != null) return // el diálogo ya está en curso
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            finishWith(mapOf("ok" to false, "error" to "unsupported"))
            return
        }
        val cdm = getSystemService(CompanionDeviceManager::class.java)
        if (cdm == null) {
            finishWith(mapOf("ok" to false, "error" to "unsupported"))
            return
        }
        val a = address
        if (a != null && a in AutoStart.associatedAddresses(this)) {
            AutoStart.onAssociated(applicationContext, a)
            finishWith(mapOf("ok" to true, "address" to a, "name" to nameOf(a)))
            return
        }
        try {
            val filter = BluetoothDeviceFilter.Builder().apply { if (a != null) setAddress(a) }.build()
            val req = AssociationRequest.Builder()
                .addDeviceFilter(filter)
                .setSingleDevice(a != null)
                .build()
            val cb = object : CompanionDeviceManager.Callback() {
                @Deprecated("API < 33")
                override fun onDeviceFound(intentSender: IntentSender) = show(intentSender)

                override fun onAssociationPending(intentSender: IntentSender) = show(intentSender)

                override fun onAssociationCreated(associationInfo: AssociationInfo) {
                    // API 33+: también llega por onActivityResult; se usa como respaldo.
                    associationInfo.deviceMacAddress?.toString()?.let { address = AutoStartRules.normMac(it) }
                }

                override fun onFailure(error: CharSequence?) {
                    finishWith(mapOf("ok" to false, "error" to (error?.toString() ?: "failure")))
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                cdm.associate(req, mainExecutor, cb)
            } else {
                @Suppress("DEPRECATION")
                cdm.associate(req, cb, null)
            }
        } catch (e: Exception) {
            Log.w(TAG, "CDM associate failed", e)
            finishWith(mapOf("ok" to false, "error" to (e.message ?: e.javaClass.simpleName)))
        }
    }

    private fun show(sender: IntentSender) {
        if (launched || done) return
        launched = true
        try {
            startIntentSenderForResult(sender, REQUEST, null, 0, 0, 0)
        } catch (e: Exception) {
            finishWith(mapOf("ok" to false, "error" to (e.message ?: "intentSender")))
        }
    }

    @Deprecated("Activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST) return
        if (resultCode != RESULT_OK) {
            finishWith(mapOf("ok" to false, "error" to "cancelled"))
            return
        }
        val chosen = data?.let { resultAddress(it) } ?: address
        if (chosen == null) {
            finishWith(mapOf("ok" to false, "error" to "noDevice"))
            return
        }
        AutoStart.onAssociated(applicationContext, chosen)
        finishWith(mapOf("ok" to true, "address" to chosen, "name" to nameOf(chosen)))
    }

    private fun resultAddress(data: Intent): String? = try {
        val fromInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            IntentCompat.getParcelableExtra(data, CompanionDeviceManager.EXTRA_ASSOCIATION, AssociationInfo::class.java)
                ?.deviceMacAddress?.toString()
        } else {
            null
        }
        @Suppress("DEPRECATION")
        val fromDevice = IntentCompat.getParcelableExtra(data, CompanionDeviceManager.EXTRA_DEVICE, BluetoothDevice::class.java)
            ?.address
        AutoStartRules.normMac(fromInfo ?: fromDevice)
    } catch (_: Exception) {
        null
    }

    @SuppressLint("MissingPermission")
    private fun nameOf(a: String): String? = try {
        if (!Bt.hasConnectPermission(this)) null
        else Bt.adapter(this)?.bondedDevices?.firstOrNull { it.address.equals(a, true) }?.name
    } catch (_: Exception) {
        null
    }

    private fun finishWith(r: Map<String, Any?>) {
        if (done) return
        done = true
        deliver(r)
        finish()
    }

    override fun onDestroy() {
        if (!done && isFinishing) {
            done = true
            deliver(mapOf("ok" to false, "error" to "cancelled"))
        }
        super.onDestroy()
    }
}
