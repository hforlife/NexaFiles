package com.example.nexa_file

import android.app.Activity
import android.content.Intent
import android.content.ClipData
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.Executors
import android.os.Build
import android.util.Size
import android.graphics.Bitmap
import java.io.ByteArrayOutputStream

/** Production boundary for Android SAF. No content URI is converted to a path. */
class SafBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val resolver get() = activity.contentResolver
    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val pickCode = 4701
    private var pendingPick: MethodChannel.Result? = null
    init { MethodChannel(messenger, "nexa_file/storage").setMethodCallHandler(::handle) }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try { when (call.method) {
            "pickTree" -> pickTree(result)
            "persisted" -> result.success(resolver.persistedUriPermissions.map { mapOf("uri" to it.uri.toString(), "read" to it.isReadPermission, "write" to it.isWritePermission) })
            "releaseTree" -> { val target=uri(call,"uri");resolver.releasePersistableUriPermission(target,Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION);result.success(null) }
            "list" -> background(result, "SAF listChildren") { document(uri(call, "uri")).listFiles().map(::metadata) }
            "metadata" -> background(result, "SAF metadata") { metadata(document(uri(call, "uri"))) }
            "read" -> background(result, "SAF read") { resolver.openInputStream(uri(call, "uri")).use { it?.readBytes() } }
            "readPrefix" -> background(result, "format prefix") {
                val length=(call.argument<Int>("length") ?: 32).coerceIn(8,4096)
                resolver.openInputStream(uri(call,"uri")).use { input ->
                    requireNotNull(input); val bytes=ByteArray(length); val read=input.read(bytes)
                    if(read <= 0) byteArrayOf() else bytes.copyOf(read)
                }
            }
            "thumbnail" -> background(result, "image thumbnail") {
                if(Build.VERSION.SDK_INT<29) null else ByteArrayOutputStream().use { out -> resolver.loadThumbnail(uri(call,"uri"),Size(240,240),null).compress(Bitmap.CompressFormat.JPEG,82,out);out.toByteArray() }
            }
            "createDirectory" -> result.success(requireNotNull(document(uri(call, "uri")).createDirectory(call.argument<String>("name")!!)).uri.toString())
            "createFile" -> createFile(call, result)
            "rename" -> result.success(requireNotNull(DocumentsContract.renameDocument(resolver, uri(call, "uri"), call.argument<String>("name")!!)).toString())
            "copy" -> result.success(copy(call, false).toString())
            "move" -> result.success(copy(call, true).toString())
            "delete" -> { if (!DocumentsContract.deleteDocument(resolver, uri(call, "uri"))) error("Suppression refusée"); result.success(null) }
            "share" -> { share(call); result.success(null) }
            "openWith" -> { openWith(call); result.success(null) }
            else -> result.notImplemented()
        }} catch (e: SecurityException) { result.error("PERMISSION", e.message, null) }
          catch (e: Exception) { result.error("STORAGE", e.message, e.javaClass.name) }
    }
    private fun background(result: MethodChannel.Result, label: String, task: () -> Any?) {
        io.execute {
            val started=System.currentTimeMillis()
            try { val value=task(); Log.d("NexaFiles", "[PERF] $label = ${System.currentTimeMillis()-started} ms"); main.post { result.success(value) } }
            catch(e: SecurityException) { main.post { result.error("PERMISSION",e.message,null) } }
            catch(e: Exception) { main.post { result.error("STORAGE",e.message,e.javaClass.name) } }
        }
    }
    private fun pickTree(result: MethodChannel.Result) {
        if (pendingPick != null) { result.error("BUSY", "Sélecteur déjà ouvert", null); return }
        pendingPick = result
        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply { addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION) }, pickCode)
    }
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != pickCode) return false
        val callback = pendingPick.also { pendingPick = null } ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { callback.success(null); return true }
        val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        resolver.takePersistableUriPermission(uri, flags); callback.success(uri.toString()); return true
    }
    private fun createFile(call: MethodCall, result: MethodChannel.Result) {
        val file = requireNotNull(document(uri(call, "uri")).createFile(call.argument<String>("mime") ?: "application/octet-stream", call.argument<String>("name")!!))
        try {
            resolver.openOutputStream(file.uri, "w").use { it!!.write(call.argument<ByteArray>("bytes") ?: byteArrayOf()) }
            result.success(file.uri.toString())
        } catch (e: Exception) {
            file.delete()
            throw e
        }
    }
    private fun copy(call: MethodCall, deleteSource: Boolean): Uri {
        val source = document(uri(call, "sourceUri")); require(source.isFile) { "Copie récursive de dossiers non disponible" }
        val target = requireNotNull(document(uri(call, "targetUri")).createFile(source.type ?: "application/octet-stream", call.argument<String>("targetName") ?: source.name ?: "file"))
        try { resolver.openInputStream(source.uri).use { input -> resolver.openOutputStream(target.uri, "w").use { output -> requireNotNull(input).copyTo(requireNotNull(output)) } }; if (deleteSource && !source.delete()) error("Suppression source refusée") }
        catch (e: Exception) { target.delete(); throw e }
        return target.uri
    }
    private fun share(call: MethodCall) {
        val uris = (call.argument<List<String>>("uris") ?: emptyList()).map(Uri::parse)
        require(uris.isNotEmpty()) { "Aucun fichier à partager" }
        val mime = call.argument<String>("mime") ?: "*/*"
        val intent = if (uris.size == 1) Intent(Intent.ACTION_SEND).apply { type = mime; putExtra(Intent.EXTRA_STREAM, uris.first()) }
        else Intent(Intent.ACTION_SEND_MULTIPLE).apply { type = mime; putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris)) }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = ClipData.newUri(resolver, "NexaFiles", uris.first()).also { clip -> uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) } }
        activity.startActivity(Intent.createChooser(intent, null))
    }
    private fun openWith(call: MethodCall) {
        val target = uri(call, "uri")
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(target, call.argument<String>("mime") ?: "*/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = ClipData.newUri(resolver, "NexaFiles", target)
        activity.startActivity(Intent.createChooser(intent, null))
    }
    private fun uri(call: MethodCall, key: String) = Uri.parse(call.argument<String>(key)!!)
    private fun document(uri: Uri): DocumentFile = (if (DocumentsContract.isTreeUri(uri)) DocumentFile.fromTreeUri(activity, uri) else DocumentFile.fromSingleUri(activity, uri)) ?: error("Document indisponible")
    private fun metadata(file: DocumentFile) = mapOf("uri" to file.uri.toString(), "name" to file.name, "mime" to file.type, "size" to file.length(), "modified" to file.lastModified(), "directory" to file.isDirectory, "read" to file.canRead(), "write" to file.canWrite())
}
