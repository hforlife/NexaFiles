package com.example.nexa_file

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Environment
import android.os.StatFs
import android.text.format.Formatter
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Home-screen integration: pinned folder shortcuts, the two widgets and the
 * "deep link" actions they send to the app (open a folder, search, music…).
 */
class HomeBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "nexa_file/home")
    private var pending: Map<String, String?>? = actionOf(activity.intent)

    companion object {
        const val EXTRA_ACTION = "nexa.action"
        const val EXTRA_PATH = "nexa.path"
        @Volatile var instance: HomeBridge? = null

        fun actionOf(intent: Intent?): Map<String, String?>? {
            val action = intent?.getStringExtra(EXTRA_ACTION) ?: return null
            return mapOf("action" to action, "path" to intent.getStringExtra(EXTRA_PATH))
        }

        /** Intent opening the app on [action]. */
        fun launch(context: Context, action: String, path: String? = null): Intent =
            Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_ACTION, action)
                .apply { if (path != null) putExtra(EXTRA_PATH, path) }

        /** Player widget button → running app (or the app itself). */
        fun control(context: Context, command: String) {
            val bridge = instance
            if (bridge != null) {
                bridge.activity.runOnUiThread { bridge.channel.invokeMethod("control", command) }
            } else {
                context.startActivity(launch(context, "player"))
            }
        }
    }

    init {
        instance = this
        // A new app process has an empty player: drop what the widget still
        // shows from the previous run.
        PlayerWidget.save(activity, false, null, null, false)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initialAction" -> { result.success(pending); pending = null }
                    "canPinShortcuts" -> result.success(ShortcutManagerCompat.isRequestPinShortcutSupported(activity))
                    "pinFolder" -> {
                        val path = call.argument<String>("path")!!
                        val label = call.argument<String>("label") ?: java.io.File(path).name
                        val info = ShortcutInfoCompat.Builder(activity, "folder:$path")
                            .setShortLabel(label.take(24))
                            .setLongLabel(label)
                            .setIcon(IconCompat.createWithResource(activity, R.mipmap.ic_shortcut_folder))
                            .setIntent(launch(activity, "open_path", path))
                            .build()
                        result.success(ShortcutManagerCompat.requestPinShortcut(activity, info, null))
                    }
                    "updatePlayer" -> {
                        PlayerWidget.save(
                            activity,
                            call.argument<Boolean>("active") ?: false,
                            call.argument<String>("title"),
                            call.argument<String>("subtitle"),
                            call.argument<Boolean>("playing") ?: false,
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("HOME", e.message, null)
            }
        }
    }

    /** New intent while the app runs (shortcut or widget tapped). */
    fun onNewIntent(intent: Intent) {
        actionOf(intent)?.let { channel.invokeMethod("action", it) }
    }

    fun detach() { if (instance === this) instance = null }
}

/** Widget: storage gauge and four shortcuts. */
class QuickWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = RemoteViews(context.packageName, R.layout.widget_quick)
        runCatching {
            val stats = StatFs(Environment.getExternalStorageDirectory().absolutePath)
            val total = stats.totalBytes
            val free = stats.availableBytes
            val percent = if (total > 0) ((total - free) * 100 / total).toInt() else 0
            views.setProgressBar(R.id.quick_gauge, 100, percent, false)
            views.setTextViewText(R.id.quick_usage, "$percent % utilisés")
            views.setTextViewText(R.id.quick_free, "${Formatter.formatShortFileSize(context, free)} libres")
        }
        fun open(viewId: Int, action: String, code: Int) = views.setOnClickPendingIntent(
            viewId,
            PendingIntent.getActivity(
                context, code, HomeBridge.launch(context, action),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        )
        open(R.id.quick_root, "home", 10)
        open(R.id.quick_search, "search", 11)
        open(R.id.quick_music, "category:audio", 12)
        open(R.id.quick_videos, "category:videos", 13)
        open(R.id.quick_clean, "cleaner", 14)
        ids.forEach { manager.updateAppWidget(it, views) }
    }
}

/** Widget: what the in-app player is playing, with controls. */
class PlayerWidget : AppWidgetProvider() {
    companion object {
        private const val PREFS = "player_widget"
        const val ACTION_TOGGLE = "nexa.player.TOGGLE"
        const val ACTION_NEXT = "nexa.player.NEXT"
        const val ACTION_PREVIOUS = "nexa.player.PREVIOUS"

        fun save(context: Context, active: Boolean, title: String?, subtitle: String?, playing: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("active", active).putString("title", title)
                .putString("subtitle", subtitle).putBoolean("playing", playing).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PlayerWidget::class.java))
            if (ids.isNotEmpty()) render(context, manager, ids)
        }

        fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val active = prefs.getBoolean("active", false)
            val playing = prefs.getBoolean("playing", false)
            val views = RemoteViews(context.packageName, R.layout.widget_player)
            views.setTextViewText(
                R.id.player_title,
                if (active) prefs.getString("title", "") else "Rien en lecture",
            )
            views.setTextViewText(
                R.id.player_subtitle,
                if (active) prefs.getString("subtitle", null) ?: "NexaFiles" else "Touchez pour ouvrir NexaFiles",
            )
            views.setImageViewResource(
                R.id.player_toggle,
                if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
            )
            val controls = if (active) View.VISIBLE else View.GONE
            views.setViewVisibility(R.id.player_controls, controls)
            fun button(viewId: Int, action: String, code: Int) = views.setOnClickPendingIntent(
                viewId,
                PendingIntent.getBroadcast(
                    context, code,
                    Intent(context, PlayerWidget::class.java).setAction(action),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            button(R.id.player_toggle, ACTION_TOGGLE, 21)
            button(R.id.player_next, ACTION_NEXT, 22)
            button(R.id.player_previous, ACTION_PREVIOUS, 23)
            views.setOnClickPendingIntent(
                R.id.player_root,
                PendingIntent.getActivity(
                    context, 20, HomeBridge.launch(context, if (active) "player" else "category:audio"),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            ids.forEach { manager.updateAppWidget(it, views) }
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        render(context, manager, ids)

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TOGGLE -> HomeBridge.control(context, "toggle")
            ACTION_NEXT -> HomeBridge.control(context, "next")
            ACTION_PREVIOUS -> HomeBridge.control(context, "previous")
            else -> super.onReceive(context, intent)
        }
    }
}
