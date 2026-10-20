package com.example.nexa_file

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream
import java.io.File

/**
 * Sandboxed document view shared by the EPUB and Word readers.
 * - scroll mode (Word): plain HTML, JavaScript off.
 * - paginated mode (EPUB): CSS columns + a small injected page engine, driven
 *   through the "nexa_file/epub_<id>" channel (next/prev/load/style/go) and
 *   reporting "position" and "edge" back to Dart.
 * Network loads are blocked and file access is confined to the book folder.
 */
class EpubWebViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(ctx: Context, id: Int, args: Any?): PlatformView =
        EpubWebView(ctx, messenger, id, args as? Map<*, *> ?: emptyMap<Any, Any>())
}

private class Style(args: Map<*, *>) {
    val textZoom = (args["textZoom"] as? Int ?: 100).coerceIn(70, 220)
    val theme = args["theme"] as? String ?: "light"
    val margin = (args["margin"] as? Double ?: 20.0).coerceIn(4.0, 64.0)
    val lineHeight = (args["lineHeight"] as? Double ?: 1.5).coerceIn(1.0, 2.5)
    val font = if (args["font"] == "sans-serif") "sans-serif" else "serif"

    fun css(paginated: Boolean): String {
        val (fg, bg) = when (theme) { "dark" -> "#e8e8e8" to "#171717"; "sepia" -> "#4b382a" to "#fff3d6"; else -> "#202124" to "#ffffff" }
        val base = "html,body{color:$fg!important;background:$bg!important;}" +
            "body{line-height:$lineHeight!important;font-family:$font;}" +
            "a{color:inherit!important;}"
        if (!paginated) return base + "body{padding:0 ${margin}px!important;}img,svg{max-width:100%!important;height:auto!important;}"
        val v = 28
        return base +
            "html{height:100%!important;margin:0!important;padding:0!important;overflow:hidden!important;}" +
            "body{margin:0!important;box-sizing:border-box!important;height:100vh!important;" +
            "padding:${v}px ${margin}px!important;column-width:calc(100vw - ${2 * margin}px)!important;" +
            "column-gap:${2 * margin}px!important;column-fill:auto!important;overflow:visible!important;}" +
            "img,svg,video{max-width:100%!important;max-height:calc(100vh - ${2 * v}px)!important;" +
            "height:auto!important;object-fit:contain;break-inside:avoid;}"
    }
}

/** Page engine: columns are one screen wide; a page is a horizontal offset. */
private const val ENGINE = """
(function(){
  var page=0,count=1,ready=false;
  function W(){return window.innerWidth||document.documentElement.clientWidth||1;}
  function measure(){count=Math.max(1,Math.ceil((document.documentElement.scrollWidth-1)/W()));}
  function show(){page=Math.max(0,Math.min(page,count-1));document.scrollingElement.scrollLeft=page*W();NexaBridge.position(page,count);}
  window.nexaRelayout=function(f){measure();page=f<0?count-1:Math.min(count-1,Math.floor(f*count+1e-6));show();};
  window.nexaNext=function(){if(page<count-1){page++;show();}else{NexaBridge.edge(1);}};
  window.nexaPrev=function(){if(page>0){page--;show();}else{NexaBridge.edge(-1);}};
  window.nexaStyle=function(css){var f=page/count;document.getElementById('nexa-style').textContent=css;setTimeout(function(){nexaRelayout(f);},60);};
  function start(){nexaRelayout(__INITIAL__);ready=true;}
  if(document.readyState==='complete'){start();}else{window.addEventListener('load',start);}
  window.addEventListener('resize',function(){if(ready){nexaRelayout(page/count);}});
})();
"""

private class EpubWebView(context: Context, messenger: BinaryMessenger, id: Int, args: Map<*, *>) : PlatformView {
    private val view = WebView(context)
    private val root = File(args["root"] as String).canonicalFile
    private val paginated = args["paginated"] == true
    private val channel = MethodChannel(messenger, "nexa_file/epub_$id")
    private val main = Handler(Looper.getMainLooper())
    private var style = Style(args)

    /** Called by the injected engine (on the JavaBridge thread). */
    private inner class Bridge {
        @JavascriptInterface fun position(page: Int, count: Int) {
            main.post { channel.invokeMethod("position", mapOf("page" to page, "count" to count)) }
        }
        @JavascriptInterface fun edge(direction: Int) {
            main.post { channel.invokeMethod("edge", direction) }
        }
    }

    init {
        configure()
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "next" -> view.evaluateJavascript("nexaNext()", null)
                "prev" -> view.evaluateJavascript("nexaPrev()", null)
                "go" -> view.evaluateJavascript("nexaRelayout(${call.argument<Double>("fraction") ?: 0.0})", null)
                "load" -> load(call.argument<String>("path")!!, call.argument<Double>("fraction") ?: 0.0)
                "style" -> {
                    style = Style(call.arguments as Map<*, *>)
                    view.settings.textZoom = style.textZoom
                    val css = org.json.JSONObject.quote(style.css(paginated))
                    view.evaluateJavascript(if (paginated) "nexaStyle($css)" else "document.getElementById('nexa-style').textContent=$css", null)
                }
                else -> { result.notImplemented(); return@setMethodCallHandler }
            }
            result.success(null)
        }
        load(args["path"] as String, (args["fraction"] as? Double) ?: 0.0)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configure() {
        view.isVerticalScrollBarEnabled = !paginated
        view.isHorizontalScrollBarEnabled = false
        view.settings.apply {
            javaScriptEnabled = paginated
            javaScriptCanOpenWindowsAutomatically = false
            domStorageEnabled = false
            allowContentAccess = false
            allowFileAccess = true
            @Suppress("DEPRECATION") allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION") allowUniversalAccessFromFileURLs = false
            blockNetworkLoads = true
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            textZoom = style.textZoom
            builtInZoomControls = false
            displayZoomControls = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) view.settings.safeBrowsingEnabled = true
        if (paginated) view.addJavascriptInterface(Bridge(), "NexaBridge")
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean = true
            override fun shouldInterceptRequest(v: WebView, request: WebResourceRequest): WebResourceResponse? {
                val uri = request.url
                if (uri.scheme == "file") {
                    val candidate = File(Uri.decode(uri.path ?: "")).canonicalFile
                    if (candidate.path.startsWith(root.path + File.separator)) return null
                }
                return WebResourceResponse("text/plain", "UTF-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(ByteArray(0)))
            }
        }
    }

    /** [fraction] < 0 opens on the last page (coming back from the next chapter). */
    private fun load(path: String, fraction: Double) {
        val target = File(path).canonicalFile
        require(target.path.startsWith(root.path + File.separator)) { "Chemin de document invalide" }
        val clean = target.readText()
            .replace(Regex("<script\\b[^>]*>.*?</script>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)), "")
            .replace(Regex("\\s+on[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)", RegexOption.IGNORE_CASE), "")
        val head = "<style id=\"nexa-style\">${style.css(paginated)}</style>"
        var html = if (clean.contains("</head>", true)) clean.replaceFirst(Regex("</head>", RegexOption.IGNORE_CASE), "$head</head>") else head + clean
        if (paginated) {
            val engine = "<script>${ENGINE.replace("__INITIAL__", fraction.toString())}</script>"
            html = if (html.contains("</body>", true)) html.replaceFirst(Regex("</body>", RegexOption.IGNORE_CASE), "$engine</body>") else html + engine
        }
        view.loadDataWithBaseURL(Uri.fromFile(target.parentFile).toString() + "/", html, "text/html", "UTF-8", null)
    }

    override fun getView() = view
    override fun dispose() {
        channel.setMethodCallHandler(null)
        view.stopLoading()
        view.loadUrl("about:blank")
        view.destroy()
    }
}
