package com.santiagortega.pixelcarplayer

import android.content.Context
import java.util.UUID

/** Identificador estable de esta instalación (va en `hello`/`beacon` como `id`). */
object InstallId {
    private const val PREFS = "pcp_native"
    private const val KEY = "install_id"
    @Volatile private var cached: String? = null

    fun get(ctx: Context): String {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val prefs = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val id = prefs.getString(KEY, null)?.takeIf { it.isNotBlank() }
                ?: UUID.randomUUID().toString().also { prefs.edit().putString(KEY, it).apply() }
            cached = id
            return id
        }
    }
}
