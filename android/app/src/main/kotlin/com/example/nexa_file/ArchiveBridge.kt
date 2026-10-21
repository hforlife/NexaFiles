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

    class PasswordRequired : Exception("Mot de passe requis")
    class WrongPassword : Exception("Mot de passe incorrect")

    private class RarSession(file: File, private val password: String?) : Session {
        private val archive = try {
            if (password == null) Archive(file) else Archive(file, password)
        } catch (e: com.github.junrar.exception.NotRarArchiveException) {
            throw e
        } catch (e: com.github.junrar.exception.UnsupportedRarEncryptedException) {
            throw e
        } catch (e: com.github.junrar.exception.RarException) {
            // Header-encrypted archives cannot even be indexed without the key.
            val headerLocked = e is com.github.junrar.exception.CorruptHeaderException ||
                e is com.github.junrar.exception.MainHeaderNullException
            when {
                password != null -> throw WrongPassword()
                headerLocked -> throw PasswordRequired()
                else -> throw e
            }
        }
        private val headers: Map<String, FileHeader> = archive.fileHeaders.associateBy { it.fileName }
        override val entries = archive.fileHeaders.map { h ->
            mapOf("name" to h.fileName, "size" to h.fullUnpackSize, "compressedSize" to h.fullPackSize,
                "directory" to h.isDirectory, "encrypted" to h.isEncrypted)
        }
        override fun read(name: String): ByteArray {
            val header = headers[name] ?: error("Entrée absente")
            if (header.isEncrypted && password == null) throw PasswordRequired()
            return try {
                ByteArrayOutputStream().use { out -> archive.extractFile(header, out); out.toByteArray() }
            } catch (e: Exception) {
                if (header.isEncrypted) throw WrongPassword() else throw e
            }
        }
        override fun close() = archive.close()
    }

    private class SevenZipSession(file: File, password: String?) : Session {
        private val seven = try {
            SevenZFile.builder().setFile(file).apply { if (password != null) setPassword(password.toCharArray()) }.get()
        } catch (_: org.apache.commons.compress.PasswordRequiredException) {
            throw PasswordRequired()
        } catch (e: java.io.IOException) {
            // Encrypted headers with a wrong key fail while reading the index.
            if (password != null) throw WrongPassword() else throw e
        }
        private val byName: Map<String, SevenZArchiveEntry> = seven.entries.associateBy { it.name }
        private fun encrypted(e: SevenZArchiveEntry) = runCatching {
            e.contentMethods.any { it.method == org.apache.commons.compress.archivers.sevenz.SevenZMethod.AES256SHA256 }
        }.getOrDefault(false)
        private val locked = password == null
        override val entries = seven.entries.map { e ->
            mapOf("name" to e.name, "size" to e.size, "compressedSize" to e.size,
                "directory" to e.isDirectory, "encrypted" to encrypted(e))
        }
        override fun read(name: String): ByteArray {
            val entry = byName[name] ?: error("Entrée absente")
            require(entry.size in 0..536870912) { "Entrée trop volumineuse" }
            return try {
                seven.getInputStream(entry).use { it.readBytes() }
            } catch (_: org.apache.commons.compress.PasswordRequiredException) {
                throw PasswordRequired()
            } catch (e: java.io.IOException) {
                if (encrypted(entry)) { if (locked) throw PasswordRequired() else throw WrongPassword() } else throw e
            }
        }
        override fun close() = seven.close()
    }

    private val channel = MethodChannel(messenger, "nexa_file/archives")
    private val cancelled = java.util.Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())

    init {
        channel.setMethodCallHandler { call, result ->
            io.execute {
                try {
                    val value = handle(call)
                    main.post { result.success(value) }
                } catch (e: PasswordRequired) {
                    main.post { result.error("PASSWORD_REQUIRED", e.message, null) }
                } catch (e: WrongPassword) {
                    main.post { result.error("WRONG_PASSWORD", e.message, null) }
                } catch (e: Exception) {
                    main.post { result.error("ARCHIVE", e.message ?: "Archive illisible", e.javaClass.name) }
                }
            }
        }
    }

    private fun handle(call: MethodCall): Any? = when (call.method) {
        "open" -> {
            val file = materialize(Uri.parse(call.argument<String>("uri")!!))
            val password = call.argument<String>("password")
            val session = when (call.argument<String>("format")) {
                "rar" -> RarSession(file, password)
                "sevenZip" -> SevenZipSession(file, password)
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
        "create7z" -> {
            create7z(
                call.argument<String>("job")!!,
                call.argument<List<String>>("sources")!!.map(::File),
                File(call.argument<String>("output")!!),
            )
            null
        }
        "cancel" -> { cancelled.add(call.argument<String>("job")!!); null }
        else -> error("Méthode archive inconnue")
    }

    /** Writes a 7z of [sources] (folders recursively), reporting each entry. */
    private fun create7z(job: String, sources: List<File>, output: File) {
        cancelled.remove(job)
        val items = mutableListOf<Pair<File, String>>()
        fun walk(file: File, name: String) {
            items += file to name
            if (file.isDirectory) file.listFiles()?.sortedBy { it.name }?.forEach { walk(it, "$name/${it.name}") }
        }
        sources.forEach { walk(it, it.name) }
        val total = items.size
        try {
            org.apache.commons.compress.archivers.sevenz.SevenZOutputFile(output).use { out ->
                val buffer = ByteArray(64 * 1024)
                items.forEachIndexed { index, (file, name) ->
                    if (job in cancelled) throw java.util.concurrent.CancellationException()
                    out.putArchiveEntry(out.createArchiveEntry(file, name))
                    if (file.isFile) file.inputStream().use { input ->
                        while (true) {
                            if (job in cancelled) throw java.util.concurrent.CancellationException()
                            val read = input.read(buffer)
                            if (read < 0) break
                            out.write(buffer, 0, read)
                        }
                    }
                    out.closeArchiveEntry()
                    main.post {
                        channel.invokeMethod("progress", mapOf("job" to job, "done" to index + 1, "total" to total, "current" to name))
                    }
                }
            }
        } catch (e: Exception) {
            output.delete()
            throw e
        } finally {
            cancelled.remove(job)
        }
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
