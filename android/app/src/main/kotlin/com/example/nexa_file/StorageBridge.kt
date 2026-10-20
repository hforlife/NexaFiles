package com.example.nexa_file

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Platform side of local storage. File I/O itself happens in Dart (dart:io);
 * this bridge only covers what needs Android APIs: the all-files permission,
 * volume discovery, thumbnails, media index refresh and sharing via FileProvider.
 */
class StorageBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val authority get() = "${activity.packageName}.files"

    init { MethodChannel(messenger, "nexa_file/storage").setMethodCallHandler(::handle) }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                "requestAllFilesAccess" -> { requestAllFilesAccess(); result.success(null) }
                "volumes" -> background(result) { volumes() }
                "categoryStats" -> background(result) { categoryStats() }
                "categoryFiles" -> background(result) {
                    categoryFiles(call.argument<String>("category")!!, call.argument<Int>("limit") ?: 2000)
                }
                "thumbnail" -> background(result) { thumbnail(File(call.argument<String>("path")!!)) }
                "scan" -> {
                    val paths = call.argument<List<String>>("paths").orEmpty()
                    if (paths.isNotEmpty()) MediaScannerConnection.scanFile(activity, paths.toTypedArray(), null, null)
                    result.success(null)
                }
                "share" -> { share(call); result.success(null) }
                "openWith" -> { openWith(call); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("STORAGE", e.message, e.javaClass.name)
        }
    }

    private fun background(result: MethodChannel.Result, task: () -> Any?) {
        io.execute {
            try { val value = task(); main.post { result.success(value) } }
            catch (e: Exception) { main.post { result.error("STORAGE", e.message, e.javaClass.name) } }
        }
    }

    private fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager()
        else ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    /** Opens the system screen; Dart re-checks the permission when the app resumes. */
    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${activity.packageName}")))
            } catch (_: Exception) {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE), 4702)
        }
    }

    /** Volume roots derived from app-specific dirs (works from API 21, primary first). */
    private fun volumes(): List<Map<String, Any?>> {
        val manager = activity.getSystemService(StorageManager::class.java)
        return activity.getExternalFilesDirs(null).filterNotNull().mapIndexedNotNull { index, dir ->
            val marker = dir.absolutePath.indexOf("/Android/data/")
            if (marker < 0) return@mapIndexedNotNull null
            val root = File(dir.absolutePath.substring(0, marker))
            val primary = index == 0
            val name = if (primary) "Stockage interne"
                else (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) manager.getStorageVolume(root)?.getDescription(activity) else null) ?: "Carte SD"
            val stats = runCatching { StatFs(root.absolutePath) }.getOrNull()
            mapOf("path" to root.absolutePath, "name" to name, "primary" to primary,
                "removable" to Environment.isExternalStorageRemovable(dir),
                "total" to stats?.totalBytes, "free" to stats?.availableBytes)
        }
    }

    /** MediaStore selection per home-screen category; hidden folders (trash, thumbnails) excluded. */
    private fun categorySelection(category: String): Pair<String, Array<String>> {
        fun extensions(vararg ext: String) =
            ext.joinToString(" OR ", "(", ")") { "${MediaStore.Files.FileColumns.DATA} LIKE ?" } to ext.map { "%.$it" }.toTypedArray()
        val (where, args) = when (category) {
            "images" -> "${MediaStore.Files.FileColumns.MEDIA_TYPE}=${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}" to emptyArray<String>()
            "videos" -> "${MediaStore.Files.FileColumns.MEDIA_TYPE}=${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}" to emptyArray<String>()
            "audio" -> "${MediaStore.Files.FileColumns.MEDIA_TYPE}=${MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO}" to emptyArray<String>()
            "documents" -> extensions("pdf", "doc", "docx", "odt", "rtf", "txt", "md", "xls", "xlsx", "ods", "csv", "ppt", "pptx", "odp")
            "books" -> extensions("epub", "cbz", "cbr", "cb7")
            "archives" -> extensions("zip", "rar", "7z", "tar", "gz")
            "apps" -> extensions("apk")
            else -> error("Catégorie inconnue")
        }
        return "($where) AND ${MediaStore.Files.FileColumns.DATA} NOT LIKE ?" to (args + "%/.%")
    }

    private val categories = listOf("images", "videos", "audio", "documents", "books", "archives", "apps")

    private fun categoryStats(): Map<String, Map<String, Long>> = categories.associateWith { category ->
        val (where, args) = categorySelection(category)
        var count = 0L
        var bytes = 0L
        activity.contentResolver.query(MediaStore.Files.getContentUri("external"), arrayOf(MediaStore.Files.FileColumns.SIZE), where, args, null)?.use { c ->
            while (c.moveToNext()) { count++; bytes += c.getLong(0) }
        }
        mapOf("count" to count, "bytes" to bytes)
    }

    private fun categoryFiles(category: String, limit: Int): List<Map<String, Any?>> {
        val (where, args) = categorySelection(category)
        val projection = arrayOf(
            MediaStore.Files.FileColumns.DATA, MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
        )
        val rows = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(
            MediaStore.Files.getContentUri("external"), projection, where, args,
            "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC",
        )?.use { c ->
            while (c.moveToNext() && rows.size < limit) {
                val path = c.getString(0) ?: continue
                rows.add(mapOf("path" to path, "size" to c.getLong(1), "modified" to c.getLong(2) * 1000))
            }
        }
        return rows
    }

    private fun mimeOf(file: File): String? =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase())

    private fun thumbnail(file: File): ByteArray? {
        val mime = mimeOf(file) ?: return null
        val bitmap: Bitmap? = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val size = Size(240, 240)
                when {
                    mime.startsWith("image/") -> ThumbnailUtils.createImageThumbnail(file, size, null)
                    mime.startsWith("video/") -> ThumbnailUtils.createVideoThumbnail(file, size, null)
                    mime.startsWith("audio/") -> ThumbnailUtils.createAudioThumbnail(file, size, null)
                    else -> null
                }
            } else when {
                mime.startsWith("image/") -> decodeSampled(file, 240)
                @Suppress("DEPRECATION")
                mime.startsWith("video/") -> ThumbnailUtils.createVideoThumbnail(file.absolutePath, MediaStore.Images.Thumbnails.MINI_KIND)
                else -> null
            }
        } catch (_: Exception) { null } // e.g. audio file without embedded art
        return bitmap?.let { bmp ->
            ByteArrayOutputStream().use { out -> bmp.compress(Bitmap.CompressFormat.JPEG, 82, out); bmp.recycle(); out.toByteArray() }
        }
    }

    private fun decodeSampled(file: File, target: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= target && bounds.outHeight / (sample * 2) >= target) sample *= 2
        return BitmapFactory.decodeFile(file.absolutePath, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    private fun contentUri(path: String): Uri = FileProvider.getUriForFile(activity, authority, File(path))

    private fun share(call: MethodCall) {
        val uris = call.argument<List<String>>("paths").orEmpty().map(::contentUri)
        require(uris.isNotEmpty()) { "Aucun fichier à partager" }
        val mime = call.argument<String>("mime") ?: "*/*"
        val intent = if (uris.size == 1) Intent(Intent.ACTION_SEND).apply { type = mime; putExtra(Intent.EXTRA_STREAM, uris.first()) }
            else Intent(Intent.ACTION_SEND_MULTIPLE).apply { type = mime; putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris)) }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = ClipData.newUri(activity.contentResolver, "NexaFiles", uris.first()).also { clip -> uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) } }
        activity.startActivity(Intent.createChooser(intent, null))
    }

    private fun openWith(call: MethodCall) {
        val path = call.argument<String>("path")!!
        val target = contentUri(path)
        val mime = call.argument<String>("mime") ?: mimeOf(File(path)) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(target, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        intent.clipData = ClipData.newUri(activity.contentResolver, "NexaFiles", target)
        activity.startActivity(Intent.createChooser(intent, null))
    }
}
