package com.santiagortega.pixelcarplayer

import android.util.Log
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale

/**
 * Registro circular (últimas [MAX] líneas, con hora) de eventos del enlace: beacons, marcados,
 * clientes, cambios de red, hotspot. Compartido por el lado celular y el lado carro (un proceso
 * corre un solo modo). Seguro desde cualquier hilo. Expuesto por `getLinkDiagnostics`.
 */
object LinkDiag {
    const val MAX = 150

    private val lines = ArrayDeque<String>(MAX)
    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    /** Último instante por clave, para [throttled]. */
    private val lastByKey = HashMap<String, Long>()

    fun log(msg: String) {
        val line = synchronized(this) {
            val l = "${fmt.format(Date())} $msg"
            if (lines.size >= MAX) lines.removeFirst()
            lines.addLast(l)
            l
        }
        runCatching { Log.d(TAG, "diag: $line") }
    }

    /** Registra [msg()] solo si pasaron [intervalMs] desde el último registro con esta [key]. */
    fun throttled(key: String, intervalMs: Long, msg: () -> String) {
        val now = System.currentTimeMillis()
        val go = synchronized(this) {
            val last = lastByKey[key]
            if (last == null || now - last >= intervalMs) {
                lastByKey[key] = now
                true
            } else {
                false
            }
        }
        if (go) log(msg())
    }

    fun lines(): List<String> = synchronized(this) { lines.toList() }

    fun clear() = synchronized(this) {
        lines.clear()
        lastByKey.clear()
    }

    /** Clase corta de un error de red para el registro (p. ej. `ConnectException: ECONNREFUSED`). */
    fun errClass(e: Throwable): String {
        val msg = e.message ?: ""
        val code = Regex("""\b(E[A-Z]{3,})\b""").find(msg)?.value
        return if (code != null) "${e.javaClass.simpleName}: $code" else "${e.javaClass.simpleName}: ${msg.take(60)}"
    }
}
