package com.example.nexa_file

import android.content.Context
import android.net.Uri
import android.os.Build
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream
import java.io.File

class EpubWebViewFactory(private val context: Context): PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(ctx: Context, id: Int, args: Any?): PlatformView = EpubWebView(ctx, args as? Map<*, *> ?: emptyMap<Any, Any>())
}

private class EpubWebView(context: Context, args: Map<*, *>): PlatformView {
    private val view = WebView(context)
    private val root = File(args["root"] as String).canonicalFile
    init {
        val target = File(args["path"] as String).canonicalFile
        require(target.path.startsWith(root.path + File.separator)) { "Chemin EPUB invalide" }
        view.settings.apply {
            javaScriptEnabled = false
            domStorageEnabled = false
            allowContentAccess = false
            allowFileAccess = true
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            blockNetworkLoads = true
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            textZoom = (args["textZoom"] as? Int ?: 100).coerceIn(70, 220)
            builtInZoomControls = false
            displayZoomControls = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) view.settings.safeBrowsingEnabled = true
        view.webViewClient = object: WebViewClient() {
            override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean = request.url.scheme !in listOf("file", "about")
            override fun shouldInterceptRequest(v: WebView, request: WebResourceRequest): WebResourceResponse? {
                val uri = request.url
                if (uri.scheme == "file") {
                    val candidate = File(Uri.decode(uri.path ?: "")).canonicalFile
                    if (candidate.path.startsWith(root.path + File.separator)) return null
                }
                return WebResourceResponse("text/plain", "UTF-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(ByteArray(0)))
            }
        }
        val theme = args["theme"] as? String ?: "light"
        val colors = when (theme) { "dark" -> "#f1f1f1" to "#171717"; "sepia" -> "#4b382a" to "#fff3d6"; else -> "#202124" to "#ffffff" }
        val margin = (args["margin"] as? Double ?: 20.0).coerceIn(4.0, 64.0)
        val lineHeight = (args["lineHeight"] as? Double ?: 1.5).coerceIn(1.0, 2.5)
        val family = if (args["font"] == "sans-serif") "sans-serif" else "serif"
        val style = "<style>html,body{color:${colors.first}!important;background:${colors.second}!important;line-height:$lineHeight!important;padding:0 ${margin}px!important;font-family:$family;}img,svg{max-width:100%!important;height:auto!important;}</style>"
        val clean = target.readText().replace(Regex("<script\\b[^>]*>.*?</script>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)), "")
        val html = if (clean.contains("</head>", true)) clean.replace(Regex("</head>", RegexOption.IGNORE_CASE), "$style</head>") else style + clean
        view.loadDataWithBaseURL(Uri.fromFile(target.parentFile).toString() + "/", html, "text/html", "UTF-8", null)
    }
    override fun getView() = view
    override fun dispose() { view.stopLoading(); view.loadUrl("about:blank"); view.destroy() }
}
