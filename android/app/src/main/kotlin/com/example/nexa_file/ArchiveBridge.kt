package com.example.nexa_file

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.github.junrar.Archive
import com.github.junrar.rarfile.FileHeader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * RAR/7Z read-only bridge. An archive is opened and indexed once per session
 * ("open"), entries are then read by name ("readEntry") until "close".
 */
class ArchiveBridge(private val context: Context, messenger: BinaryMessenger) {
    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val sessions = ConcurrentHashMap<Long, Session>()
    private val nextId = AtomicLong(1)

    private interface Session : Closeable {
        val entries: List<Map<String, Any?>>
        fun read(name: String): ByteArray
    }

    private class RarSession(file: File) : Session {
        private val archive = Archive(file)
        private val headers: Map<String, FileHeader> = archive.fileHeaders.associateBy { it.fileName }
        override val entries = archive.fileHeaders.map { h ->
            mapOf("name" to h.fileName, "size" to h.fullUnpackSize, "compressedSize" to h.fullPackSize, "directory" to h.isDirectory)
        }
        override fun read(name: String): ByteArray {
            val header = headers[name] ?: error("Entrée absente")
            return ByteArrayOutputStream().use { out -> archive.extractFile(header, out); out.toByteArray() }
        }
        override fun close() = archive.close()
    }

    private class SevenZipSession(file: File) : Session {
        private val seven = SevenZFile(file)
        private val byName: Map<String, SevenZArchiveEntry> = seven.entries.associateBy { it.name }
        override val entries = seven.entries.map { e ->
            mapOf("name" to e.name, "size" to e.size, "compressedSize" to e.size, "directory" to e.isDirectory)
        }
        override fun read(name: String): ByteArray {
            val entry = byName[name] ?: error("Entrée absente")
            require(entry.size in 0..536870912) { "Entrée trop volumineuse" }
            return seven.getInputStream(entry).use { it.readBytes() }
        }
        override fun close() = seven.close()
    }

    init {
        MethodChannel(messenger, "nexa_file/archives").setMethodCallHandler { call, result ->
            io.execute {
                try {
                    val value = handle(call)
                    main.post { result.success(value) }
                } catch (e: Exception) {
                    main.post { result.error("ARCHIVE", e.message ?: "Archive illisible", e.javaClass.name) }
                }
            }
        }
    }

    private fun handle(call: MethodCall): Any? = when (call.method) {
        "open" -> {
            val file = materialize(Uri.parse(call.argument<String>("uri")!!))
            val session = when (call.argument<String>("format")) {
                "rar" -> RarSession(file)
                "sevenZip" -> SevenZipSession(file)
                else -> error("Format natif non pris en charge")
            }
            val id = nextId.getAndIncrement()
            sessions[id] = session
            mapOf("session" to id, "entries" to session.entries)
        }
        "readEntry" -> {
            val session = sessions[call.argument<Number>("session")!!.toLong()] ?: error("Archive fermée")
            // Archive readers are not thread-safe; one read at a time per session.
            synchronized(session) { session.read(call.argument<String>("name")!!) }
        }
        "close" -> {
            sessions.remove(call.argument<Number>("session")!!.toLong())?.let { synchronized(it) { it.close() } }
            null
        }
        else -> error("Méthode archive inconnue")
    }

    /** Local files are used in place; only content:// sources are copied to the cache. */
    @Synchronized private fun materialize(uri: Uri): File {
        if (uri.scheme == "file") return File(requireNotNull(uri.path)).also { require(it.isFile && it.length() > 0L) { "Fichier introuvable ou vide" } }
        val dir = File(context.cacheDir, "archive_sources").apply { mkdirs() }
        val file = File(dir, "${uri.toString().hashCode().toUInt()}.source")
        if (!file.exists() || file.length() == 0L) {
            context.contentResolver.openInputStream(uri).use { input -> requireNotNull(input) { "Source inaccessible" }; file.outputStream().use { input.copyTo(it) } }
        }
        require(file.length() > 0L) { "Le fichier source est vide" }
        return file
    }
}
