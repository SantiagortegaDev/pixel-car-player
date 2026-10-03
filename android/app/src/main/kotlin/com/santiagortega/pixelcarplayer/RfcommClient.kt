package com.santiagortega.pixelcarplayer

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.util.UUID

/** Bluetooth helpers shared by the car (client) and phone (server) sides. */
object Bt {
    fun adapter(context: Context): BluetoothAdapter? = try {
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    } catch (e: Exception) {
        null
    }

    /** BLUETOOTH_CONNECT on API 31+; implicit (install-time) before. */
    fun hasConnectPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    fun bondedDevices(context: Context): List<Map<String, Any?>> {
        val adapter = adapter(context) ?: return emptyList()
        if (!hasConnectPermission(context)) return emptyList()
        return try {
            adapter.bondedDevices.orEmpty().map { d ->
                mapOf("name" to (d.name ?: d.address), "address" to d.address)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "bondedDevices denied", e)
            emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    val uuid: UUID = UUID.fromString(LinkProtocol.RFCOMM_UUID)
}

/**
 * Car side: single RFCOMM connection to the phone. Lines read are posted as `rfcomm` events.
 */
object RfcommClient {
    private val lock = Any()
    private var socket: BluetoothSocket? = null
    private var output: OutputStream? = null
    private var generation = 0

    /** Blocking connect (call from a background thread). Returns true when connected. */
    @SuppressLint("MissingPermission")
    fun connect(context: Context, address: String): Boolean {
        disconnect("reconnect", emit = false)
        val adapter = Bt.adapter(context)
        if (adapter == null || !Bt.hasConnectPermission(context)) {
            Log.w(TAG, "RFCOMM unavailable (adapter=${adapter != null})")
            return false
        }
        val sock: BluetoothSocket
        val name: String
        try {
            if (!adapter.isEnabled) return false
            val device = adapter.getRemoteDevice(address)
            name = device.name ?: address
            try {
                adapter.cancelDiscovery()
            } catch (_: Exception) {
            }
            sock = device.createInsecureRfcommSocketToServiceRecord(Bt.uuid)
            sock.connect()
        } catch (e: SecurityException) {
            Log.w(TAG, "RFCOMM connect denied", e)
            return false
        } catch (e: Exception) {
            Log.w(TAG, "RFCOMM connect to $address failed: ${e.message}")
            return false
        }
        val gen: Int
        val out: OutputStream
        try {
            out = sock.outputStream
            synchronized(lock) {
                socket = sock
                output = out
                gen = ++generation
            }
        } catch (e: Exception) {
            closeQuietly(sock)
            return false
        }
        EventHub.post(mapOf("type" to "rfcomm", "event" to "connected", "name" to name, "address" to address))
        Thread({ readLoop(sock, gen) }, "pcp-rfcomm-read").apply { isDaemon = true }.start()
        return true
    }

    private fun readLoop(sock: BluetoothSocket, gen: Int) {
        var reason = "closed"
        try {
            BufferedReader(InputStreamReader(sock.inputStream, Charsets.UTF_8)).use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    if (line.isBlank()) continue
                    EventHub.post(mapOf("type" to "rfcomm", "event" to "line", "data" to line))
                }
            }
        } catch (e: Exception) {
            reason = e.message ?: "io_error"
        }
        val mine = synchronized(lock) {
            if (generation == gen) {
                socket = null
                output = null
                true
            } else {
                false
            }
        }
        closeQuietly(sock)
        if (mine) {
            EventHub.post(mapOf("type" to "rfcomm", "event" to "disconnected", "reason" to reason))
        }
    }

    /** Writes [line] + "\n". Blocking but short; returns false when not connected / failed. */
    fun send(line: String): Boolean {
        val out = synchronized(lock) { output } ?: return false
        return try {
            synchronized(out) {
                out.write((line + "\n").toByteArray(Charsets.UTF_8))
                out.flush()
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "RFCOMM send failed: ${e.message}")
            false
        }
    }

    fun disconnect(reason: String = "user", emit: Boolean = true) {
        val sock = synchronized(lock) {
            val s = socket
            socket = null
            output = null
            generation++
            s
        } ?: return
        closeQuietly(sock)
        if (emit) EventHub.post(mapOf("type" to "rfcomm", "event" to "disconnected", "reason" to reason))
    }

    private fun closeQuietly(s: BluetoothSocket) {
        try {
            s.close()
        } catch (_: Exception) {
        }
    }
}
