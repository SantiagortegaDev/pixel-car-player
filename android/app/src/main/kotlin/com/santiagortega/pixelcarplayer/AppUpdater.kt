package com.santiagortega.pixelcarplayer

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Actualizaciones desde GitHub Releases (ambos modos): versión instalada, búsqueda de la release más
 * nueva con el APK de la ABI del equipo, descarga con progreso e instalación (PackageInstaller o, como
 * respaldo, ACTION_VIEW con FileProvider). La actualización conserva los datos solo si el APK está
 * firmado con la misma clave.
 */
object AppUpdater {
    const val RELEASES_URL = "https://api.github.com/repos/SantiagortegaDev/pixel-car-player/releases?per_page=30"
    private const val ACTION_INSTALL_STATUS = "com.santiagortega.pixelcarplayer.INSTALL_STATUS"
    private const val PROGRESS_INTERVAL_MS = 250L

    @Volatile private var busy = false
    @Volatile private var receiverRegistered = false

    private fun packageInfo(ctx: Context): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.packageManager.getPackageInfo(ctx.packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            ctx.packageManager.getPackageInfo(ctx.packageName, 0)
        }

    @Suppress("DEPRECATION")
    private fun versionCodeOf(pi: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pi.longVersionCode else pi.versionCode.toLong()

    fun deviceAbis(): List<String> = Build.SUPPORTED_ABIS?.toList().orEmpty()

    /** `{versionName, versionCode, abi, package, installedAt}`. */
    fun appVersion(ctx: Context): Map<String, Any?> {
        val pi = packageInfo(ctx)
        return mapOf(
            "versionName" to (pi.versionName ?: ""),
            "versionCode" to versionCodeOf(pi),
            "abi" to (deviceAbis().firstOrNull() ?: ""),
            "package" to ctx.packageName,
            "installedAt" to pi.lastUpdateTime,
        )
    }

    /** Bloqueante. Contrato `checkForUpdate` (ver UpdateLogic.choose). */
    fun check(ctx: Context): Map<String, Any?> {
        val pi = packageInfo(ctx)
        val current = UpdateLogic.Current(pi.versionName ?: "", versionCodeOf(pi), pi.lastUpdateTime)
        val conn = (URL(RELEASES_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 15_000
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("X-GitHub-Api-Version", "2022-11-28")
            setRequestProperty("User-Agent", "PixelCarPlayer/${current.versionName}")
        }
        return try {
            val code = conn.responseCode
            if (code != 200) {
                val limited = (code == 403 || code == 429) && conn.getHeaderField("X-RateLimit-Remaining") == "0"
                mapOf("available" to false, "error" to if (limited) "rateLimited" else "http_$code")
            } else {
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                UpdateLogic.choose(body, deviceAbis(), current)
            }
        } catch (e: Exception) {
            Log.w(TAG, "checkForUpdate failed", e)
            mapOf("available" to false, "error" to "network")
        } finally {
            conn.disconnect()
        }
    }

    fun canInstall(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ctx.packageManager.canRequestPackageInstalls()

    fun openInstallPermissionSettings(activity: Activity) {
        val intents = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                add(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
            }
            @Suppress("DEPRECATION")
            add(Intent(Settings.ACTION_SECURITY_SETTINGS))
            add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
        }
        for (i in intents) {
            try {
                activity.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: Exception) {
            }
        }
    }

    private fun state(state: String, error: String? = null) {
        EventHub.post(mapOf("type" to "updateState", "state" to state, "error" to error))
    }

    /**
     * Bloqueante: descarga [apkUrl] y lanza la instalación. true si el instalador quedó en marcha
     * (el sistema pide confirmación al usuario). Emite `updateProgress` / `updateState`.
     */
    fun downloadAndInstall(ctx: Context, apkUrl: String): Boolean {
        if (busy) {
            state("error", "busy")
            return false
        }
        if (!apkUrl.startsWith("https://")) {
            state("error", "badUrl")
            return false
        }
        if (!canInstall(ctx)) {
            state("error", "installPermission")
            return false
        }
        busy = true
        try {
            state("downloading")
            val file = download(ctx, apkUrl) ?: return false
            val archive = archiveInfo(ctx, file)
            if (archive == null || archive.packageName != ctx.packageName) {
                Log.w(TAG, "update apk invalid: ${archive?.packageName}")
                file.delete()
                state("error", "invalidApk")
                return false
            }
            state("installing")
            CarFeatures.suspendKeepFront("update", windowMs = 60_000L)
            return installWithSession(ctx, file) || installWithIntent(ctx, file)
        } catch (e: Exception) {
            Log.w(TAG, "update failed", e)
            state("error", e.message ?: e.javaClass.simpleName)
            return false
        } finally {
            busy = false
        }
    }

    private fun download(ctx: Context, url: String): File? {
        val dir = File(ctx.cacheDir, "updates").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val out = File(dir, "update.apk")
        var conn = URL(url).openConnection() as HttpURLConnection
        var redirects = 0
        while (true) {
            conn.instanceFollowRedirects = true
            conn.connectTimeout = 15_000
            conn.readTimeout = 30_000
            conn.setRequestProperty("User-Agent", "PixelCarPlayer")
            conn.setRequestProperty("Accept", "application/octet-stream")
            val code = conn.responseCode
            if (code in 300..399 && redirects < 5) {
                val loc = conn.getHeaderField("Location") ?: break
                conn.disconnect()
                conn = URL(URL(url), loc).openConnection() as HttpURLConnection
                redirects++
                continue
            }
            if (code != 200) {
                conn.disconnect()
                state("error", "http_$code")
                return null
            }
            break
        }
        try {
            val total = conn.contentLengthLong
            var received = 0L
            var lastEmit = 0L
            conn.inputStream.use { input ->
                FileOutputStream(out).use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        output.write(buf, 0, n)
                        received += n
                        val now = System.currentTimeMillis()
                        if (now - lastEmit >= PROGRESS_INTERVAL_MS) {
                            lastEmit = now
                            EventHub.post(mapOf("type" to "updateProgress", "received" to received, "total" to total))
                        }
                    }
                    output.fd.sync()
                }
            }
            EventHub.post(mapOf("type" to "updateProgress", "received" to received, "total" to total))
            if ((total > 0 && received != total) || received == 0L || out.length() != received) {
                out.delete()
                state("error", "incomplete")
                return null
            }
            return out
        } catch (e: Exception) {
            out.delete()
            Log.w(TAG, "update download failed", e)
            state("error", "network")
            return null
        } finally {
            conn.disconnect()
        }
    }

    private fun archiveInfo(ctx: Context, file: File): PackageInfo? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.packageManager.getPackageArchiveInfo(file.path, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            ctx.packageManager.getPackageArchiveInfo(file.path, 0)
        }
    } catch (_: Exception) {
        null
    }

    private fun installWithSession(ctx: Context, file: File): Boolean {
        val app = ctx.applicationContext
        var session: PackageInstaller.Session? = null
        return try {
            ensureReceiver(app)
            val installer = app.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(app.packageName)
                setSize(file.length())
            }
            val id = installer.createSession(params)
            val s = installer.openSession(id)
            session = s
            file.inputStream().use { input ->
                s.openWrite("base.apk", 0, file.length()).use { output ->
                    input.copyTo(output, 64 * 1024)
                    s.fsync(output)
                }
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val pi = PendingIntent.getBroadcast(
                app, id, Intent(ACTION_INSTALL_STATUS).setPackage(app.packageName), flags,
            )
            s.commit(pi.intentSender)
            s.close()
            true
        } catch (e: Exception) {
            Log.w(TAG, "PackageInstaller session failed, falling back to ACTION_VIEW", e)
            runCatching { session?.abandon() }
            false
        }
    }

    private fun installWithIntent(ctx: Context, file: File): Boolean = try {
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", file)
        @Suppress("DEPRECATION")
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            ctx.startActivity(intent)
        } catch (_: Exception) {
            ctx.startActivity(Intent(intent).setAction(Intent.ACTION_VIEW))
        }
        true
    } catch (e: Exception) {
        Log.w(TAG, "install intent failed", e)
        state("error", "installer")
        false
    }

    @Synchronized
    private fun ensureReceiver(app: Context) {
        if (receiverRegistered) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
                val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                when (status) {
                    PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                        @Suppress("DEPRECATION")
                        val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                        try {
                            CarFeatures.suspendKeepFront("installer", windowMs = 60_000L)
                            context.startActivity(confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        } catch (e: Exception) {
                            Log.w(TAG, "installer confirm failed", e)
                            state("error", "installer")
                        }
                    }
                    PackageInstaller.STATUS_SUCCESS -> Log.i(TAG, "update instalado")
                    PackageInstaller.STATUS_FAILURE_ABORTED -> state("error", "cancelled")
                    PackageInstaller.STATUS_FAILURE_CONFLICT, PackageInstaller.STATUS_FAILURE_INCOMPATIBLE ->
                        state("error", "signature")
                    PackageInstaller.STATUS_FAILURE_STORAGE -> state("error", "storage")
                    else -> state("error", msg ?: "status_$status")
                }
            }
        }
        ContextCompat.registerReceiver(app, r, IntentFilter(ACTION_INSTALL_STATUS), ContextCompat.RECEIVER_NOT_EXPORTED)
        receiverRegistered = true
    }
}
