package com.example.nexa_file

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import android.util.Log
import android.os.Handler
import android.os.Looper
import android.graphics.Matrix
import java.util.concurrent.Executors

class PdfBridge(messenger: BinaryMessenger) {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    init { MethodChannel(messenger, "nexa_file/pdf").setMethodCallHandler { call, result ->
        io.execute { try { val value=handle(call); main.post { result.success(value) } }
            catch(error:Exception){ Log.e("NexaFiles","PDF ${call.method} failed",error);main.post{result.error("INVALID_PDF","Impossible d’ouvrir ce PDF (${error.message ?: error.javaClass.simpleName}).",error.javaClass.name)} } }
    } }

    private fun handle(call: MethodCall): Any? {
            val path = call.argument<String>("path") ?: error("Chemin PDF absent")
            val source = File(path)
            require(source.exists() && source.length() > 0L) { "PDF matérialisé absent ou vide" }
            val started = System.currentTimeMillis()
            if (call.method == "search") {
                val query = call.argument<String>("query")?.trim().orEmpty()
                if (query.isEmpty()) return emptyList<Map<String, Any>>()
                val rows = mutableListOf<Map<String, Any>>()
                PDDocument.load(File(path)).use { document ->
                    val stripper = PDFTextStripper().apply { sortByPosition = true }
                    for (page in 1..document.numberOfPages) {
                        stripper.startPage = page; stripper.endPage = page
                        val text = stripper.getText(document).replace(Regex("\\s+"), " ").trim()
                        val index = text.lowercase().indexOf(query.lowercase())
                        if (index >= 0) {
                            val from = (index - 45).coerceAtLeast(0); val to = (index + query.length + 70).coerceAtMost(text.length)
                            rows.add(mapOf("page" to page - 1, "snippet" to text.substring(from, to)))
                        }
                    }
                }
                return rows
            }
            ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    when (call.method) {
                        "pageCount" -> { Log.d("NexaFiles", "[PERF] PDF open pages=${renderer.pageCount} path=$path exists=${source.exists()} bytes=${source.length()} ms=${System.currentTimeMillis()-started}"); return renderer.pageCount }
                        "render" -> {
                            val index = call.argument<Int>("page") ?: 0
                            val targetWidth = (call.argument<Int>("width") ?: 1400).coerceIn(320, 2400)
                            renderer.openPage(index.coerceIn(0, renderer.pageCount - 1)).use { page ->
                                val height = (targetWidth.toDouble() * page.height / page.width).toInt().coerceAtLeast(1)
                                val bitmap = Bitmap.createBitmap(targetWidth, height, Bitmap.Config.ARGB_8888)
                                bitmap.eraseColor(android.graphics.Color.WHITE)
                                val matrix=Matrix().apply { postScale(targetWidth.toFloat()/page.width,height.toFloat()/page.height) }
                                page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                val output = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.PNG, 92, output)
                                val png=output.toByteArray()
                                val nonEmpty=png.size>100
                                Log.d("NexaFiles", "[PERF] PDF render page=$index pageSize=${page.width}x${page.height} bitmap=${bitmap.width}x${bitmap.height} png=${png.size} nonEmpty=$nonEmpty ms=${System.currentTimeMillis()-started}")
                                bitmap.recycle()
                                return mapOf("bytes" to png,"page" to index,"pageWidth" to page.width,"pageHeight" to page.height,"bitmapWidth" to targetWidth,"bitmapHeight" to height,"durationMs" to System.currentTimeMillis()-started,"nonEmpty" to nonEmpty)
                            }
                        }
                        else -> error("Méthode PDF inconnue")
                    }
                }
            }
    }
}
