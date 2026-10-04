package com.santiagortega.pixelcarplayer

import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

// Lógica pura (sin APIs de Android) de las funciones del carro y de actualizaciones, para tests JVM.

/** Evento de UsageStatsManager reducido: [type] 1 = ACTIVITY_RESUMED/MOVE_TO_FOREGROUND, 2 = PAUSED. */
data class UsageEv(val time: Long, val type: Int, val pkg: String)

object ForegroundEvents {
    const val RESUMED = 1 // UsageEvents.Event.ACTIVITY_RESUMED == MOVE_TO_FOREGROUND
    const val PAUSED = 2 // UsageEvents.Event.ACTIVITY_PAUSED == MOVE_TO_BACKGROUND

    /**
     * App en primer plano tras aplicar [events] (en cualquier orden) sobre [previous]: la del último
     * RESUMED. Un PAUSED solo no cambia nada (siempre le sigue el RESUMED de otra app, p. ej. el
     * launcher), salvo que sea el de la app actual y no haya RESUMED posterior: se mantiene igual.
     */
    fun latestForeground(events: List<UsageEv>, previous: String?): String? {
        var fg = previous
        var lastTime = Long.MIN_VALUE
        for (e in events.sortedBy { it.time }) {
            if (e.type == RESUMED && e.time >= lastTime) {
                fg = e.pkg
                lastTime = e.time
            }
        }
        return fg
    }
}

/**
 * Decide cuándo volver a traer Pixel Car Player al frente ("mantener al frente").
 * Se llama en cada sondeo con la app en primer plano; devuelve true cuando hay que traerla ya.
 */
class KeepFrontPolicy(var config: Config = Config()) {
    data class Config(
        val enabled: Boolean = false,
        val packages: Set<String> = emptySet(),
        val anyApp: Boolean = false,
        val delayMs: Long = 1500,
        val includeLauncher: Boolean = false,
    )

    companion object {
        /** Nunca disparan (salvo que estén en la lista explícita): el usuario está configurando algo. */
        val IGNORED = setOf(
            "android",
            "com.android.systemui",
            "com.android.settings",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.android.documentsui",
            "com.google.android.documentsui",
            "com.android.intentresolver",
            "com.android.vending",
        )
        private val IGNORED_PREFIXES = listOf("com.android.settings", "com.android.systemui")

        /** Paquete comodín cuando no se conoce la app en primer plano (sin acceso de uso). */
        const val UNKNOWN = "*"
        const val FIGHT_WINDOW_MS = 60_000L
        const val FIGHT_MAX_PULLS = 3
        const val BACKOFF_MS = 5 * 60_000L
    }

    private var pendingPkg: String? = null
    private var pendingSince = 0L
    private val pulls = HashMap<String, ArrayDeque<Long>>()
    private val backoffUntil = HashMap<String, Long>()

    fun reset() {
        pendingPkg = null
    }

    /** ¿La app [fg] en primer plano es motivo para volver? (sin contar demora ni pelea). */
    fun triggers(fg: String?, ownPkg: String, ownResumed: Boolean, suspended: Boolean, launchers: Set<String>): Boolean {
        val c = config
        if (!c.enabled || ownResumed || suspended || fg.isNullOrEmpty() || fg == ownPkg) return false
        if (fg == UNKNOWN) return c.anyApp
        if (fg in c.packages) return true
        if (!c.anyApp) return false
        if (fg in IGNORED || IGNORED_PREFIXES.any { fg.startsWith(it) }) return false
        if (fg in launchers && !c.includeLauncher) return false
        return true
    }

    /** Un sondeo. true = traer al frente ahora (y queda registrado para el límite anti-pelea). */
    fun tick(now: Long, fg: String?, ownPkg: String, ownResumed: Boolean, suspended: Boolean, launchers: Set<String>): Boolean {
        if (!triggers(fg, ownPkg, ownResumed, suspended, launchers)) {
            pendingPkg = null
            return false
        }
        val pkg = fg!!
        if ((backoffUntil[pkg] ?: 0L) > now) return false
        if (pendingPkg != pkg) {
            pendingPkg = pkg
            pendingSince = now
        }
        if (now - pendingSince < config.delayMs) return false
        pendingPkg = null
        return recordPull(pkg, now)
    }

    /** ms que faltan para que venza la demora pendiente (para sondear justo a tiempo), o null. */
    fun msUntilDue(now: Long): Long? = pendingPkg?.let { (pendingSince + config.delayMs - now).coerceAtLeast(0L) }

    /**
     * No pelear con el usuario: si hubo que traerla [FIGHT_MAX_PULLS] veces en [FIGHT_WINDOW_MS] por la
     * misma app (el usuario la vuelve a abrir a propósito), se deja de insistir [BACKOFF_MS].
     */
    private fun recordPull(pkg: String, now: Long): Boolean {
        val q = pulls.getOrPut(pkg) { ArrayDeque() }
        while (q.isNotEmpty() && now - q.first() > FIGHT_WINDOW_MS) q.removeFirst()
        if (q.size >= FIGHT_MAX_PULLS) {
            backoffUntil[pkg] = now + BACKOFF_MS
            q.clear()
            return false
        }
        q.addLast(now)
        return true
    }
}

/** Elección de la actualización en GitHub Releases. */
object UpdateLogic {
    data class Asset(
        val name: String,
        val url: String,
        val size: Long,
        val versionName: String?,
        val versionCode: Long?,
        val abi: String,
    )

    data class Current(val versionName: String, val versionCode: Long, val installTimeMs: Long)

    val KNOWN_ABIS = listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86", "universal")
    private val NAME_RE = Regex("""^pixel-car-player-(.+)-(\d+)-(arm64-v8a|armeabi-v7a|x86_64|x86|universal)\.apk$""")

    /** Margen para el respaldo por fecha (release publicado justo antes/después de instalar). */
    const val DATE_MARGIN_MS = 10 * 60_000L

    /** `pixel-car-player-<versionName>-<versionCode>-<abi>.apk`; otros .apk = universal sin versión. */
    fun parseAsset(name: String, url: String, size: Long): Asset? {
        if (!name.endsWith(".apk", ignoreCase = true)) return null
        val m = NAME_RE.matchEntire(name)
            ?: return Asset(name, url, size, null, null, "universal")
        return Asset(name, url, size, m.groupValues[1], m.groupValues[2].toLongOrNull(), m.groupValues[3])
    }

    /** ABI exacta en el orden de preferencia del equipo, luego universal. */
    fun pickAsset(assets: List<Asset>, deviceAbis: List<String>): Asset? {
        for (abi in deviceAbis) {
            assets.firstOrNull { it.abi == abi && it.versionCode != null }?.let { return it }
        }
        return assets.firstOrNull { it.abi == "universal" && it.versionCode != null }
            ?: assets.firstOrNull { it.abi == "universal" }
    }

    /**
     * `flutter build apk --split-per-abi` suma 1000 × código de ABI al versionCode; se compara la base
     * para que el APK instalado (p. ej. 2005) y el nombre del asset (5 o 2005) coincidan.
     */
    fun baseCode(code: Long): Long = if (code >= 1000) code % 1000 else code

    /** Compara versionName numéricamente por partes ("1.10.0" > "1.9.2"); null si no son comparables. */
    fun compareNames(a: String?, b: String?): Int? {
        fun parts(s: String?): List<Int>? {
            val core = s?.trim()?.removePrefix("v")?.substringBefore('-')?.substringBefore('+') ?: return null
            val p = core.split('.').map { it.toIntOrNull() ?: return null }
            return p.takeIf { it.isNotEmpty() }
        }
        val pa = parts(a) ?: return null
        val pb = parts(b) ?: return null
        for (i in 0 until maxOf(pa.size, pb.size)) {
            val d = (pa.getOrElse(i) { 0 }).compareTo(pb.getOrElse(i) { 0 })
            if (d != 0) return d
        }
        return 0
    }

    /** > 0 si (nameA, codeA) es más nuevo que (nameB, codeB). */
    fun compareVersions(nameA: String?, codeA: Long, nameB: String?, codeB: Long): Int {
        val byName = compareNames(nameA, nameB)
        if (byName != null && byName != 0) return byName
        return baseCode(codeA).compareTo(baseCode(codeB))
    }

    fun parseTime(iso: String?): Long? {
        if (iso.isNullOrBlank()) return null
        return try {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.parse(iso)?.time
        } catch (_: Exception) {
            null
        }
    }

    private class Candidate(val release: JSONObject, val asset: Asset, val publishedAt: Long)

    /**
     * Resultado del contrato `checkForUpdate` a partir del JSON de `/releases` (lista, incluye
     * prereleases; se ignoran drafts). Con versionCode en el nombre del asset gana el más nuevo por
     * versión; si ningún release lo tiene, el más reciente por `published_at` frente a [Current.installTimeMs].
     */
    fun choose(releasesJson: String, deviceAbis: List<String>, current: Current): Map<String, Any?> {
        val arr = try {
            JSONArray(releasesJson)
        } catch (_: Exception) {
            return mapOf("available" to false, "error" to "parse")
        }
        if (arr.length() == 0) return mapOf("available" to false, "error" to "noReleases")
        val candidates = ArrayList<Candidate>()
        for (i in 0 until arr.length()) {
            val rel = arr.optJSONObject(i) ?: continue
            if (rel.optBoolean("draft", false)) continue
            val assetsJson = rel.optJSONArray("assets") ?: continue
            val assets = (0 until assetsJson.length()).mapNotNull { j ->
                val a = assetsJson.optJSONObject(j) ?: return@mapNotNull null
                parseAsset(a.optString("name"), a.optString("browser_download_url"), a.optLong("size", -1))
            }
            val pick = pickAsset(assets, deviceAbis) ?: continue
            val published = parseTime(rel.optString("published_at", "")) ?: parseTime(rel.optString("created_at", "")) ?: 0L
            candidates += Candidate(rel, pick, published)
        }
        if (candidates.isEmpty()) return mapOf("available" to false, "error" to "noAsset")

        val coded = candidates.filter { it.asset.versionCode != null }
        val best: Candidate
        val available: Boolean
        if (coded.isNotEmpty()) {
            best = coded.maxWithOrNull { x, y ->
                val v = compareVersions(x.asset.versionName, x.asset.versionCode!!, y.asset.versionName, y.asset.versionCode!!)
                if (v != 0) v else x.publishedAt.compareTo(y.publishedAt)
            }!!
            available = compareVersions(best.asset.versionName, best.asset.versionCode!!, current.versionName, current.versionCode) > 0
        } else {
            best = candidates.maxByOrNull { it.publishedAt }!!
            available = best.publishedAt > current.installTimeMs + DATE_MARGIN_MS
        }
        val rel = best.release
        val tag = rel.optString("tag_name", "")
        return mapOf(
            "available" to available,
            "versionName" to (best.asset.versionName ?: tag.ifEmpty { null }),
            "versionCode" to best.asset.versionCode,
            "notes" to rel.optString("body", ""),
            "htmlUrl" to rel.optString("html_url", ""),
            "apkUrl" to best.asset.url,
            "apkSize" to best.asset.size,
            "apkName" to best.asset.name,
            "abi" to best.asset.abi,
            "tag" to tag,
            "prerelease" to rel.optBoolean("prerelease", false),
            "publishedAt" to rel.optString("published_at", ""),
        )
    }
}

/** Nombre de archivo seguro para las copias de seguridad. */
object BackupNames {
    const val DEFAULT_NAME = "pixel-car-player-config.json"

    fun sanitize(name: String): String {
        val base = name.trim().replace(Regex("""[\\/:*?"<>|\u0000-\u001f]"""), "_").ifEmpty { DEFAULT_NAME }
        return if (base.endsWith(".json", ignoreCase = true)) base else "$base.json"
    }
}
