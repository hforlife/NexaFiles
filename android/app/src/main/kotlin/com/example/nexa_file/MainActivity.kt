package com.example.nexa_file

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var storageBridge: StorageBridge
    private lateinit var archiveBridge: ArchiveBridge
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        storageBridge = StorageBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        archiveBridge = ArchiveBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        flutterEngine.platformViewsController.registry.registerViewFactory("nexa_file/epub", EpubWebViewFactory(flutterEngine.dartExecutor.binaryMessenger))
    }
}
