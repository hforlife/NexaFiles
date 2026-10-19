package com.example.nexa_file

import android.content.Context
import android.net.Uri
import com.github.junrar.Archive
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import android.util.Log
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/** RAR/7Z read-only bridge. Archives are materialized in private cache, never as public paths. */
class ArchiveBridge(private val context: Context, messenger: BinaryMessenger) {
    private val io=Executors.newFixedThreadPool(2)
    private val main=Handler(Looper.getMainLooper())
    init { MethodChannel(messenger, "nexa_file/archives").setMethodCallHandler { call,result -> io.execute {
        val started=System.currentTimeMillis()
        try { val value=when(call.method) {
            "materialize" -> materialize(Uri.parse(call.argument<String>("uri")!!)).absolutePath
            "list" -> list(call)
            "readEntry" -> readEntry(call)
            else -> error("Méthode archive inconnue")
        };Log.d("NexaFiles","[PERF] archive ${call.method} = ${System.currentTimeMillis()-started} ms");main.post{result.success(value)} }
        catch(e:Exception){main.post{result.error("ARCHIVE",e.message ?: "Archive illisible",e.javaClass.name)}}
    } } }
    @Synchronized private fun materialize(uri: Uri): File {
        if (uri.scheme == "file") return File(requireNotNull(uri.path)).also { require(it.isFile && it.length() > 0L) { "Fichier introuvable ou vide" } }
        val dir = File(context.cacheDir, "archive_sources").apply { mkdirs() }
        val file = File(dir, "${uri.toString().hashCode().toUInt()}.source")
        if (!file.exists() || file.length() == 0L) {
            val started = System.currentTimeMillis()
            context.contentResolver.openInputStream(uri).use { input -> requireNotNull(input) { "Source SAF inaccessible" }; file.outputStream().use { input.copyTo(it) } }
            Log.d("NexaFiles", "SAF materialize bytes=${file.length()} ms=${System.currentTimeMillis()-started}")
        }
        require(file.length() > 0L) { "Le fichier source est vide" }
        return file
    }
    private fun list(call: MethodCall): List<Map<String, Any?>> {
        val file = materialize(Uri.parse(call.argument<String>("uri")!!))
        return when(call.argument<String>("format")) {
            "rar" -> Archive(file).use { archive -> archive.fileHeaders.map { h -> mapOf("name" to h.fileName, "size" to h.fullUnpackSize, "compressedSize" to h.fullPackSize, "directory" to h.isDirectory) } }
            "sevenZip" -> SevenZFile(file).use { seven -> buildList { while(true) { val e=seven.nextEntry ?: break; add(mapOf("name" to e.name, "size" to e.size, "compressedSize" to e.size, "directory" to e.isDirectory)) } } }
            else -> error("Format natif non pris en charge")
        }
    }
    private fun readEntry(call: MethodCall): ByteArray {
        val file = materialize(Uri.parse(call.argument<String>("uri")!!)); val name=call.argument<String>("name")!!
        return when(call.argument<String>("format")) {
            "rar" -> Archive(file).use { archive -> val header=archive.fileHeaders.firstOrNull { it.fileName==name } ?: error("Entrée absente"); ByteArrayOutputStream().use { out -> archive.extractFile(header,out);out.toByteArray() } }
            "sevenZip" -> readSevenZip(file, name)
            else -> error("Format natif non pris en charge")
        }
    }
    private fun readSevenZip(file: File, name: String): ByteArray {
        SevenZFile(file).use { seven ->
            while (true) {
                val entry = seven.nextEntry ?: error("Entrée absente")
                if (entry.name != name) continue
                require(entry.size in 0..536870912) { "Entrée trop volumineuse" }
                val out = ByteArrayOutputStream(); val buffer = ByteArray(65536)
                while (true) { val read = seven.read(buffer); if (read < 0) break; out.write(buffer, 0, read) }
                return out.toByteArray()
            }
        }
    }
}
