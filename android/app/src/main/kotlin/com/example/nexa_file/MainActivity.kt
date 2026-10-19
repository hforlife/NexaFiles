package com.example.nexa_file

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader

class MainActivity : FlutterActivity() {
    private lateinit var safBridge: SafBridge
    private lateinit var archiveBridge: ArchiveBridge
    private lateinit var pdfBridge: PdfBridge
    private lateinit var mediaBridge: MediaBridge
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PDFBoxResourceLoader.init(applicationContext)
        safBridge = SafBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        archiveBridge = ArchiveBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        pdfBridge = PdfBridge(flutterEngine.dartExecutor.binaryMessenger)
        mediaBridge = MediaBridge(this,flutterEngine.dartExecutor.binaryMessenger)
        flutterEngine.platformViewsController.registry.registerViewFactory("nexa_file/epub", EpubWebViewFactory(this))
        flutterEngine.platformViewsController.registry.registerViewFactory("nexa_file/video", VideoViewFactory(this))
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (!safBridge.onActivityResult(requestCode, resultCode, data)) super.onActivityResult(requestCode, resultCode, data)
    }
}
