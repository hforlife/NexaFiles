package com.hdeveloppement.nexafiles

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var storageBridge: StorageBridge
    private lateinit var archiveBridge: ArchiveBridge
    private lateinit var operationsBridge: OperationsBridge
    private var homeBridge: HomeBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        storageBridge = StorageBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        archiveBridge = ArchiveBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        operationsBridge = OperationsBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        homeBridge = HomeBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        flutterEngine.platformViewsController.registry.registerViewFactory("nexa_file/epub", EpubWebViewFactory(flutterEngine.dartExecutor.binaryMessenger))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        homeBridge?.onNewIntent(intent)
    }

    override fun onDestroy() {
        homeBridge?.detach()
        super.onDestroy()
    }
}
