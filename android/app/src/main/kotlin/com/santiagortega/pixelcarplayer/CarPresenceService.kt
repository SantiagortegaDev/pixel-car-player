package com.santiagortega.pixelcarplayer

import android.companion.AssociationInfo
import android.companion.CompanionDeviceManager
import android.companion.CompanionDeviceService
import android.companion.DevicePresenceEvent
import android.os.Build
import androidx.annotation.RequiresApi

/**
 * v3 (celular, API 31+): el sistema lo enlaza cuando el dispositivo Bluetooth del carro asociado
 * con CompanionDeviceManager aparece/desaparece (`startObservingDevicePresence`). Mientras está
 * enlazado, y con REQUEST_COMPANION_START_FOREGROUND_SERVICES_FROM_BACKGROUND, la app puede
 * iniciar el transmisor en primer plano desde segundo plano.
 *
 * Según la versión de Android llega una de las tres variantes de callback; [AutoStart.onBtEvent]
 * es idempotente, así que no importa si llegan dos.
 */
@RequiresApi(Build.VERSION_CODES.S)
class CarPresenceService : CompanionDeviceService() {

    @Deprecated("API 31-32")
    override fun onDeviceAppeared(address: String) {
        AutoStart.onBtEvent(applicationContext, address, true, "CDM")
    }

    @Deprecated("API 31-32")
    override fun onDeviceDisappeared(address: String) {
        AutoStart.onBtEvent(applicationContext, address, false, "CDM")
    }

    @Deprecated("API 33-35")
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    override fun onDeviceAppeared(associationInfo: AssociationInfo) {
        associationInfo.deviceMacAddress?.toString()?.let {
            AutoStart.onBtEvent(applicationContext, it, true, "CDM")
        }
    }

    @Deprecated("API 33-35")
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    override fun onDeviceDisappeared(associationInfo: AssociationInfo) {
        associationInfo.deviceMacAddress?.toString()?.let {
            AutoStart.onBtEvent(applicationContext, it, false, "CDM")
        }
    }

    @RequiresApi(36)
    override fun onDevicePresenceEvent(event: DevicePresenceEvent) {
        val appeared = when (event.event) {
            DevicePresenceEvent.EVENT_BLE_APPEARED, DevicePresenceEvent.EVENT_BT_CONNECTED -> true
            DevicePresenceEvent.EVENT_BLE_DISAPPEARED, DevicePresenceEvent.EVENT_BT_DISCONNECTED -> false
            else -> return
        }
        val address = try {
            getSystemService(CompanionDeviceManager::class.java)?.myAssociations
                ?.firstOrNull { it.id == event.associationId }?.deviceMacAddress?.toString()
        } catch (_: Exception) {
            null
        } ?: return
        AutoStart.onBtEvent(applicationContext, address, appeared, "CDM")
    }
}
