package com.example.nexa_file

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
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
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * Platform side of local storage. File I/O itself happens in Dart (dart:io);
 * this bridge only covers what needs Android APIs: the all-files permission,
 * volume discovery, thumbnails, media index refresh and sharing via FileProvider.
 */
class StorageBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val io = Executors.newFixedThreadPool(2)

    /**
     * Thumbnails run on their own pool, newest request first (LIFO): while
     * scrolling, what is on screen now is served before rows already gone.
     */
    private val thumbs = ThreadPoolExecutor(
        3, 3, 30, TimeUnit.SECONDS,
        object : LinkedBlockingDeque<Runnable>() {
            override fun offer(e: Runnable): Boolean { offerFirst(e); return true }
        },
    )
    private val thumbDir by lazy { File(activity.cacheDir, "thumbs").apply { mkdirs() } }
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
                "thumbnail" -> background(result, thumbs) { cachedThumbnail(File(call.argument<String>("path")!!)) }
                "audioInfo" -> background(result) { audioInfo(File(call.argument<String>("path")!!)) }
                "search" -> background(result) {
                    search(
                        call.argument<String>("query") ?: "",
                        call.argument<List<String>>("categories").orEmpty(),
                        call.argument<Number>("minSize")?.toLong(),
                        call.argument<Number>("modifiedAfter")?.toLong(),
                        call.argument<Number>("modifiedBefore")?.toLong(),
                        call.argument<String>("under"),
                        call.argument<Boolean>("folders") ?: true,
                        call.argument<String>("sort") ?: "date",
                        call.argument<Int>("limit") ?: 500,
                    )
                }
                "duplicates" -> background(result) { duplicates(call.argument<Number>("minSize")?.toLong() ?: 102400L) }
                "apkStatus" -> background(result) { apkStatus(call.argument<List<String>>("paths").orEmpty()) }
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

    private fun background(
        result: MethodChannel.Result,
        pool: java.util.concurrent.Executor = io,
        task: () -> Any?,
    ) {
        pool.execute {
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
            "archives" -> extensions("zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz")
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

    /**
     * Indexed search over the whole storage (MediaStore files table): name,
     * categories, size and date filters. Folders match on their name too.
     */
    private fun search(
        query: String, categories: List<String>, minSize: Long?, modifiedAfter: Long?,
        modifiedBefore: Long?, under: String?, folders: Boolean, sort: String, limit: Int,
    ): List<Map<String, Any?>> {
        val data = MediaStore.Files.FileColumns.DATA
        val clauses = mutableListOf("$data NOT LIKE ?")
        val args = mutableListOf("%/.%")
        if (query.isNotBlank()) {
            // Every word must appear in the name, in any order.
            query.trim().split(Regex("\\s+")).forEach { word ->
                clauses += "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? ESCAPE '\\'"
                args += "%" + word.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            }
        }
        if (categories.isNotEmpty()) {
            val parts = categories.filter { it != "folders" }.map { categorySelection(it) }
            val any = mutableListOf<String>()
            parts.forEach { (w, a) -> any += "($w)"; args.addAll(a) }
            if ("folders" in categories) any += "${MediaStore.Files.FileColumns.MIME_TYPE} IS NULL"
            if (any.isNotEmpty()) clauses += any.joinToString(" OR ", "(", ")")
        } else if (!folders) {
            clauses += "${MediaStore.Files.FileColumns.MIME_TYPE} IS NOT NULL"
        }
        if (minSize != null) { clauses += "${MediaStore.Files.FileColumns.SIZE} >= ?"; args += minSize.toString() }
        if (modifiedAfter != null) { clauses += "${MediaStore.Files.FileColumns.DATE_MODIFIED} >= ?"; args += (modifiedAfter / 1000).toString() }
        if (modifiedBefore != null) { clauses += "${MediaStore.Files.FileColumns.DATE_MODIFIED} < ?"; args += (modifiedBefore / 1000).toString() }
        if (under != null) { clauses += "$data LIKE ?"; args += "${under.trimEnd('/')}/%" }
        val order = when (sort) {
            "size" -> "${MediaStore.Files.FileColumns.SIZE} DESC"
            "name" -> "${MediaStore.Files.FileColumns.DISPLAY_NAME} COLLATE NOCASE ASC"
            else -> "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
        }
        val rows = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(
            MediaStore.Files.getContentUri("external"),
            arrayOf(data, MediaStore.Files.FileColumns.SIZE, MediaStore.Files.FileColumns.DATE_MODIFIED, MediaStore.Files.FileColumns.MIME_TYPE),
            clauses.joinToString(" AND "), args.toTypedArray(), order,
        )?.use { c ->
            while (c.moveToNext() && rows.size < limit) {
                val path = c.getString(0) ?: continue
                val file = File(path)
                val directory = c.isNull(3) && file.isDirectory
                if (c.isNull(3) && !directory) continue // stale index row
                rows.add(mapOf("path" to path, "size" to c.getLong(1), "modified" to c.getLong(2) * 1000, "directory" to directory))
            }
        }
        return rows
    }

    /**
     * Groups of identical files: same size, then same head + tail digest,
     * then same full digest (files over 512 MB stop at the quick digest).
     */
    private fun duplicates(minSize: Long): List<Map<String, Any?>> {
        val bySize = HashMap<Long, MutableList<String>>()
        activity.contentResolver.query(
            MediaStore.Files.getContentUri("external"),
            arrayOf(MediaStore.Files.FileColumns.DATA, MediaStore.Files.FileColumns.SIZE),
            "${MediaStore.Files.FileColumns.SIZE} >= ? AND ${MediaStore.Files.FileColumns.MIME_TYPE} IS NOT NULL AND ${MediaStore.Files.FileColumns.DATA} NOT LIKE ?",
            arrayOf(minSize.toString(), "%/.%"), null,
        )?.use { c ->
            while (c.moveToNext()) {
                val path = c.getString(0) ?: continue
                bySize.getOrPut(c.getLong(1)) { mutableListOf() }.add(path)
            }
        }
        fun digest(file: File, full: Boolean): String? = try {
            val md = java.security.MessageDigest.getInstance("MD5")
            java.io.RandomAccessFile(file, "r").use { raf ->
                val buffer = ByteArray(64 * 1024)
                if (full) {
                    while (true) { val n = raf.read(buffer); if (n < 0) break; md.update(buffer, 0, n) }
                } else {
                    val n = raf.read(buffer, 0, 16 * 1024); if (n > 0) md.update(buffer, 0, n)
                    if (raf.length() > 32 * 1024) {
                        raf.seek(raf.length() - 16 * 1024)
                        val m = raf.read(buffer, 0, 16 * 1024); if (m > 0) md.update(buffer, 0, m)
                    }
                }
            }
            md.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) { null }
        val groups = mutableListOf<Map<String, Any?>>()
        for ((size, paths) in bySize) {
            if (paths.size < 2) continue
            val existing = paths.filter { File(it).isFile }
            if (existing.size < 2) continue
            val quick = existing.groupBy { digest(File(it), false) }.filterKeys { it != null }.values.filter { it.size > 1 }
            for (candidates in quick) {
                val confirmed = if (size <= 512L * 1024 * 1024)
                    candidates.groupBy { digest(File(it), true) }.filterKeys { it != null }.values.filter { it.size > 1 }
                else listOf(candidates)
                confirmed.forEach { same ->
                    groups += mapOf(
                        "size" to size,
                        "paths" to same.sortedBy { File(it).lastModified() },
                        "certain" to (size <= 512L * 1024 * 1024),
                    )
                }
            }
            if (groups.size >= 300) break
        }
        return groups.sortedByDescending { (it["size"] as Long) * ((it["paths"] as List<*>).size - 1) }
    }

    /** For each APK: package, label, version and whether it is installed. */
    private fun apkStatus(paths: List<String>): List<Map<String, Any?>> {
        val pm = activity.packageManager
        return paths.mapNotNull { path ->
            try {
                val info = pm.getPackageArchiveInfo(path, 0) ?: return@mapNotNull mapOf("path" to path, "status" to "invalid")
                info.applicationInfo?.let { it.sourceDir = path; it.publicSourceDir = path }
                val label = info.applicationInfo?.loadLabel(pm)?.toString()
                @Suppress("DEPRECATION")
                val version = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                val installed = try {
                    val i = pm.getPackageInfo(info.packageName, 0)
                    @Suppress("DEPRECATION")
                    if (Build.VERSION.SDK_INT >= 28) i.longVersionCode else i.versionCode.toLong()
                } catch (_: PackageManager.NameNotFoundException) { null }
                mapOf(
                    "path" to path, "package" to info.packageName, "label" to label,
                    "version" to info.versionName,
                    "status" to when {
                        installed == null -> "notInstalled"
                        installed >= version -> "installed"
                        else -> "update"
                    },
                )
            } catch (_: Exception) { mapOf("path" to path, "status" to "invalid") }
        }
    }

    private fun mimeOf(file: File): String? =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase())

    /** Disk cache keyed by path, size and date: each thumbnail is built once. */
    private fun cachedThumbnail(file: File): ByteArray? {
        val key = "${file.absolutePath}|${file.length()}|${file.lastModified()}".hashCode().toUInt()
        val cached = File(thumbDir, "$key.jpg")
        if (cached.exists()) return if (cached.length() == 0L) null else cached.readBytes()
        val bytes = mediaStoreThumbnail(file) ?: thumbnail(file)
        // An empty file remembers "no thumbnail" (e.g. audio without art).
        runCatching { cached.writeBytes(bytes ?: ByteArray(0)) }
        trimThumbCache()
        return bytes
    }

    private fun trimThumbCache() {
        val files = thumbDir.listFiles() ?: return
        if (files.size <= 4000) return
        files.sortedBy { it.lastModified() }.take(files.size - 3000).forEach { it.delete() }
    }

    /** Thumbnails the gallery already generated: by far the fastest path. */
    private fun mediaStoreThumbnail(file: File): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val mime = mimeOf(file) ?: return null
        val base = when {
            mime.startsWith("image/") -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            mime.startsWith("video/") -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else -> return null
        }
        return try {
            @Suppress("DEPRECATION")
            val id = activity.contentResolver.query(
                base, arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DATA}=?", arrayOf(file.absolutePath), null,
            )?.use { c -> if (c.moveToFirst()) c.getLong(0) else null } ?: return null
            val bmp = activity.contentResolver.loadThumbnail(
                android.content.ContentUris.withAppendedId(base, id), Size(240, 240), null,
            )
            ByteArrayOutputStream().use { out -> bmp.compress(Bitmap.CompressFormat.JPEG, 82, out); bmp.recycle(); out.toByteArray() }
        } catch (_: Exception) { null }
    }

    /** Tags and embedded cover of an audio file. */
    private fun audioInfo(file: File): Map<String, Any?> {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(file.absolutePath)
            mapOf(
                "title" to r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE),
                "artist" to (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                    ?: r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)),
                "album" to r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                "art" to r.embeddedPicture,
            )
        } catch (_: Exception) {
            emptyMap()
        } finally {
            runCatching { r.release() }
        }
    }

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
