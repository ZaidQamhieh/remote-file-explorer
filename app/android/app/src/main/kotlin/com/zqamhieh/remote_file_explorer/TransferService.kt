package com.zqamhieh.remote_file_explorer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the app process alive while file transfers run,
 * so they survive the user switching away from the app, and shows an ongoing
 * progress notification. The transfer logic itself lives in Dart; this service
 * is driven entirely by [MainActivity]'s `rfe/transfers` MethodChannel via
 * start/update/stop intents.
 */
class TransferService : Service() {
    companion object {
        const val ACTION_UPDATE = "com.zqamhieh.remote_file_explorer.UPDATE"
        const val ACTION_STOP = "com.zqamhieh.remote_file_explorer.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress"

        const val CHANNEL_ONGOING = "transfers"
        const val NOTIFICATION_ID = 0x5254 // "RT"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Transferring…"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, 0) ?: 0

        ensureChannel()
        val notification = buildNotification(title, text, progress)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(title: String, text: String, progress: Int): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ONGOING)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress.coerceIn(0, 100), progress <= 0)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ONGOING) == null) {
                mgr.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ONGOING,
                        "Transfers",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply { description = "Ongoing file transfers" },
                )
            }
        }
    }
}
