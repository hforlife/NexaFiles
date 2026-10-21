package com.example.nexa_file

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service kept alive while copies, moves, extractions or
 * compressions run, so Android does not kill the process when the user
 * leaves the app. The work itself runs in Dart; this only shows progress.
 */
class OperationService : Service() {
    companion object {
        private const val CHANNEL_ID = "operations"
        private const val NOTIFICATION_ID = 4711
        const val ACTION_CANCEL = "nexa.operations.CANCEL"
        @Volatile var running = false
        var onCancel: (() -> Unit)? = null

        fun build(context: Context, title: String, text: String, percent: Int): android.app.Notification {
            ensureChannel(context)
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val cancel = PendingIntent.getService(
                context, 1,
                Intent(context, OperationService::class.java).setAction(ACTION_CANCEL),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_operation)
                .setContentTitle(title)
                .setContentText(text)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setProgress(100, percent.coerceIn(0, 100), percent < 0)
                .setContentIntent(open)
                .addAction(0, "Annuler", cancel)
                .build()
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Opérations sur les fichiers", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "Progression des copies, extractions et compressions" },
            )
        }

        fun update(context: Context, title: String, text: String, percent: Int) {
            if (!running) {
                val intent = Intent(context, OperationService::class.java)
                    .putExtra("title", title).putExtra("text", text).putExtra("percent", percent)
                ContextCompat.startForegroundService(context, intent)
            } else if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                try {
                    NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, build(context, title, text, percent))
                } catch (_: SecurityException) { }
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, OperationService::class.java))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            onCancel?.invoke()
            return START_NOT_STICKY
        }
        val notification = build(
            this,
            intent?.getStringExtra("title") ?: "NexaFiles",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("percent", -1) ?: -1,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

/** Dart side of [OperationService]: update / stop, and cancel callbacks. */
class OperationsBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "nexa_file/operations")

    init {
        OperationService.onCancel = { activity.runOnUiThread { channel.invokeMethod("cancelAll", null) } }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "update" -> OperationService.update(
                        activity,
                        call.argument<String>("title") ?: "NexaFiles",
                        call.argument<String>("text") ?: "",
                        call.argument<Int>("percent") ?: -1,
                    )
                    "stop" -> OperationService.stop(activity)
                    "requestPermission" -> if (Build.VERSION.SDK_INT >= 33 &&
                        ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4711)
                    }
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            } catch (e: Exception) {
                result.error("OPERATIONS", e.message, null)
            }
        }
    }
}
