package com.santiagortega.pixelcarplayer

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.ContextCompat
import java.io.File
import java.util.concurrent.Executors

/**
 * Copias de seguridad de la configuración (JSON) en Documentos/PixelCarPlayer/ y lectura de una copia
 * elegida por el usuario (ACTION_OPEN_DOCUMENT).
 */
object BackupFiles {
    const val DEFAULT_NAME = BackupNames.DEFAULT_NAME
    const val SUBDIR = "PixelCarPlayer"
    private const val MAX_READ_BYTES = 5L * 1024 * 1024
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor { r -> Thread(r, "pcp-backup").apply { isDaemon = true } }

    fun sanitizeName(name: String): String = BackupNames.sanitize(name)

    /** Guarda [json]; [done] recibe la ruta legible (o URI) en el hilo principal, o null si falló. */
    fun save(activity: Activity, json: String, name: String, done: (String?) -> Unit) {
        val ctx = activity.applicationContext
        val file = sanitizeName(name)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            io.execute {
                val r = runCatching { saveMediaStore(ctx, json, file) }
                    .onFailure { Log.w(TAG, "backup MediaStore failed", it) }
                    .getOrNull() ?: runCatching { saveAppDir(ctx, json, file) }.getOrNull()
                main.post { done(r) }
            }
            return
        }
        val perm = Manifest.permission.WRITE_EXTERNAL_STORAGE
        val write = {
            io.execute {
                val granted = ContextCompat.checkSelfPermission(ctx, perm) == PackageManager.PERMISSION_GRANTED
                val r = (if (granted) runCatching { saveLegacy(json, file) }
                    .onFailure { Log.w(TAG, "backup legacy failed", it) }.getOrNull() else null)
                    ?: runCatching { saveAppDir(ctx, json, file) }.getOrNull()
                main.post { done(r) }
            }
        }
        if (ContextCompat.checkSelfPermission(ctx, perm) == PackageManager.PERMISSION_GRANTED) {
            write()
        } else {
            CarFeatures.suspendKeepFront("backupPermission")
            CarHelperActivity.requestPermissions(activity, arrayOf(perm)) { write() }
        }
    }

    private fun saveMediaStore(ctx: Context, json: String, name: String): String {
        val resolver = ctx.contentResolver
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relPath = "${Environment.DIRECTORY_DOCUMENTS}/$SUBDIR/"
        // Solo vemos archivos propios (sin permiso de lectura): si existe uno nuestro, se sobrescribe.
        var uri: Uri? = null
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME}=?",
            arrayOf(relPath, name),
            null,
        )?.use { c ->
            if (c.moveToFirst()) uri = android.content.ContentUris.withAppendedId(collection, c.getLong(0))
        }
        val target = uri ?: resolver.insert(collection, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relPath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }) ?: error("MediaStore insert returned null")
        resolver.openOutputStream(target, "wt")!!.use { it.write(json.toByteArray(Charsets.UTF_8)) }
        if (uri == null) {
            resolver.update(target, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        }
        // Nombre real (MediaStore agrega " (1)" si ya había uno ajeno con el mismo nombre).
        val finalName = resolver.query(target, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: name
        @Suppress("DEPRECATION")
        val root = Environment.getExternalStorageDirectory().absolutePath
        return "$root/$relPath$finalName"
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(json: String, name: String): String {
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS), SUBDIR)
        if (!dir.exists() && !dir.mkdirs()) error("mkdirs failed: $dir")
        val f = File(dir, name)
        f.writeText(json, Charsets.UTF_8)
        return f.absolutePath
    }

    /** Respaldo sin permisos: carpeta de la app en el almacenamiento externo (se borra al desinstalar). */
    private fun saveAppDir(ctx: Context, json: String, name: String): String? {
        val dir = File(ctx.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS) ?: return null, SUBDIR)
        dir.mkdirs()
        val f = File(dir, name)
        f.writeText(json, Charsets.UTF_8)
        return f.absolutePath
    }

    /** Selector del sistema; [done] recibe el contenido del archivo (main thread) o null. */
    fun pick(activity: Activity, done: (String?) -> Unit) {
        val ctx = activity.applicationContext
        CarHelperActivity.openDocument(activity, arrayOf("application/json", "text/*", "application/octet-stream")) { uri ->
            if (uri == null) {
                done(null)
                return@openDocument
            }
            io.execute {
                val text = runCatching { read(ctx, uri) }
                    .onFailure { Log.w(TAG, "backup read failed", it) }
                    .getOrNull()
                main.post { done(text) }
            }
        }
    }

    private fun read(ctx: Context, uri: Uri): String? {
        ctx.contentResolver.openInputStream(uri)?.use { input ->
            val bytes = input.readBytes()
            if (bytes.size > MAX_READ_BYTES) return null
            return String(bytes, Charsets.UTF_8)
        }
        return null
    }
}

/**
 * Activity transparente para resultados (selector de documentos, permisos) sin tocar MainActivity
 * (FlutterActivity no es ComponentActivity). Un pedido a la vez; uno nuevo cancela el anterior.
 */
class CarHelperActivity : Activity() {

    companion object {
        private const val EXTRA_MODE = "mode"
        private const val EXTRA_MIME = "mime"
        private const val EXTRA_PERMS = "perms"
        private const val MODE_OPEN = "open"
        private const val MODE_PERMS = "perms"
        private const val REQUEST = 4801

        private var pendingUri: ((Uri?) -> Unit)? = null
        private var pendingPerms: (() -> Unit)? = null

        private fun cancelPending() {
            pendingUri?.let { cb -> pendingUri = null; runCatching { cb(null) } }
            pendingPerms?.let { cb -> pendingPerms = null; runCatching { cb() } }
        }

        fun openDocument(activity: Activity, mimes: Array<String>, done: (Uri?) -> Unit) {
            cancelPending()
            pendingUri = done
            try {
                activity.startActivity(
                    Intent(activity, CarHelperActivity::class.java)
                        .putExtra(EXTRA_MODE, MODE_OPEN)
                        .putExtra(EXTRA_MIME, mimes)
                )
            } catch (e: Exception) {
                Log.w(TAG, "CarHelperActivity start failed", e)
                cancelPending()
            }
        }

        fun requestPermissions(activity: Activity, perms: Array<String>, done: () -> Unit) {
            cancelPending()
            pendingPerms = done
            try {
                activity.startActivity(
                    Intent(activity, CarHelperActivity::class.java)
                        .putExtra(EXTRA_MODE, MODE_PERMS)
                        .putExtra(EXTRA_PERMS, perms)
                )
            } catch (e: Exception) {
                Log.w(TAG, "CarHelperActivity start failed", e)
                cancelPending()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return // recreada: el resultado llega igual por onActivityResult
        when (intent?.getStringExtra(EXTRA_MODE)) {
            MODE_OPEN -> {
                val mimes = intent.getStringArrayExtra(EXTRA_MIME) ?: arrayOf("*/*")
                val pick = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(if (mimes.size == 1) mimes[0] else "*/*")
                    .putExtra(Intent.EXTRA_MIME_TYPES, mimes)
                try {
                    startActivityForResult(pick, REQUEST)
                } catch (e: Exception) {
                    // Algunos radios no traen DocumentsUI: probar GET_CONTENT.
                    try {
                        startActivityForResult(
                            Intent(Intent.ACTION_GET_CONTENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"),
                            REQUEST,
                        )
                    } catch (e2: Exception) {
                        Log.w(TAG, "no document picker", e2)
                        finishWith(null)
                    }
                }
            }
            MODE_PERMS -> {
                val perms = intent.getStringArrayExtra(EXTRA_PERMS) ?: emptyArray()
                if (perms.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) finishPerms()
                else requestPermissions(perms, REQUEST)
            }
            else -> finish()
        }
    }

    @Deprecated("Activity API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST) finishWith(if (resultCode == RESULT_OK) data?.data else null)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST) finishPerms()
    }

    private fun finishWith(uri: Uri?) {
        val cb = pendingUri
        pendingUri = null
        finish()
        cb?.invoke(uri)
    }

    private fun finishPerms() {
        val cb = pendingPerms
        pendingPerms = null
        finish()
        cb?.invoke()
    }

    override fun onDestroy() {
        // Destruida sin resultado (p. ej. el sistema la cerró): no dejar a Dart esperando.
        if (isFinishing && !isChangingConfigurations) cancelPending()
        super.onDestroy()
    }
}
