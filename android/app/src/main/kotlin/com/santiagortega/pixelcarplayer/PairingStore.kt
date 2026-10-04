package com.santiagortega.pixelcarplayer

import android.content.Context
import android.util.Log
import org.json.JSONObject

/**
 * v3 (celular): tokens de los carros emparejados en `SharedPreferences("pcp_native")["paired_cars"]`,
 * JSON `{carId: {token, name, pairedAt}}` (CONTRACT §1 v3). Los tokens nunca salen de aquí salvo
 * para calcular el MAC; no se registran en LinkDiag.
 */
object PairingStore {
    private const val PREFS = "pcp_native"
    private const val KEY = "paired_cars"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val PREF_REQUIRE = "flutter.phone_require_pairing"

    /** `flutter.phone_require_pairing` (def. true). */
    fun requirePairing(ctx: Context): Boolean = try {
        ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).getBoolean(PREF_REQUIRE, true)
    } catch (_: Exception) {
        true
    }

    private fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    @Synchronized
    private fun read(ctx: Context): JSONObject = try {
        JSONObject(prefs(ctx).getString(KEY, null) ?: "{}")
    } catch (e: Exception) {
        Log.w(TAG, "paired_cars corrupto; se ignora", e)
        JSONObject()
    }

    @Synchronized
    private fun write(ctx: Context, o: JSONObject) {
        prefs(ctx).edit().putString(KEY, o.toString()).commit()
    }

    fun token(ctx: Context, carId: String): String? =
        read(ctx).optJSONObject(carId)?.optString("token", "")?.takeIf { it.isNotEmpty() }

    @Synchronized
    fun put(ctx: Context, carId: String, token: String, name: String) {
        val o = read(ctx)
        o.put(carId, JSONObject().put("token", token).put("name", name).put("pairedAt", System.currentTimeMillis()))
        write(ctx, o)
    }

    @Synchronized
    fun remove(ctx: Context, carId: String): Boolean {
        val o = read(ctx)
        if (!o.has(carId)) return false
        o.remove(carId)
        write(ctx, o)
        return true
    }

    /** `getPairedCars`: `[{id, name, pairedAt}]`, más reciente primero. */
    fun list(ctx: Context): List<Map<String, Any?>> {
        val o = read(ctx)
        return o.keys().asSequence().mapNotNull { id ->
            val e = o.optJSONObject(id) ?: return@mapNotNull null
            mapOf("id" to id, "name" to e.optString("name", ""), "pairedAt" to e.optLong("pairedAt", 0L))
        }.sortedByDescending { it["pairedAt"] as Long }.toList()
    }
}
