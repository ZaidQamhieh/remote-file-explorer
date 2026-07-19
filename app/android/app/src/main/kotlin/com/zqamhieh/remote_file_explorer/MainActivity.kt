package com.zqamhieh.remote_file_explorer

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "rfe/downloads"
    private val transfersChannelName = "rfe/transfers"
    private val intentsChannelName = "rfe/intents"

    /** Set by Tasker's "Send Intent" (or any caller) to jump to a host's explorer. */
    private val actionOpenHost = "com.zqamhieh.remote_file_explorer.OPEN_HOST"
    private val extraHostId = "hostId"

    private var intentChannel: MethodChannel? = null

    /**
     * Host id from an [actionOpenHost] intent that started the activity cold —
     * stashed here and pulled by the Dart side via `getInitialHostId` once its
     * method-channel handler is ready, the same pull-for-cold-start pattern
     * `receive_sharing_intent` uses for share intents (a push at this point
     * would race the Dart handler and be silently dropped).
     */
    private var pendingHostId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingHostId = hostIdFromIntent(intent)
    }

    /**
     * POST_NOTIFICATIONS (API 33+) gates whether the transfer progress /
     * completion notifications are visible. The foreground service still
     * runs without it; this just makes its notification show. Requested
     * contextually — right before the first transfer notification — rather
     * than unconditionally at cold start (PR-76: premature prompts reduce
     * opt-in).
     */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0x504E)
        }
    }

    /**
     * Fires when the activity is already running (`singleTop`) and receives a
     * new intent, e.g. a warm-start Tasker "Send Intent". The Dart side's
     * method-channel handler is already registered by now, so this pushes
     * directly instead of stashing for a pull.
     *
     * Calls `super.onNewIntent` first so plugins that hook this lifecycle
     * method themselves (e.g. `receive_sharing_intent`) still see the intent.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val hostId = hostIdFromIntent(intent) ?: return
        intentChannel?.invokeMethod("openHost", hostId)
    }

    private fun hostIdFromIntent(intent: Intent?): String? {
        if (intent?.action != actionOpenHost) return null
        return intent.getStringExtra(extraHostId)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        intentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, intentsChannelName)
        intentChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialHostId" -> {
                    result.success(pendingHostId)
                    pendingHostId = null
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, transfersChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        ensureNotificationPermission()
                        val intent = Intent(this, TransferService::class.java).apply {
                            action = TransferService.ACTION_UPDATE
                            putExtra(TransferService.EXTRA_TITLE, call.argument<String>("title"))
                            putExtra(TransferService.EXTRA_TEXT, call.argument<String>("text"))
                            putExtra(
                                TransferService.EXTRA_PROGRESS,
                                call.argument<Int>("progress") ?: 0,
                            )
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(true)
                    }
                    "stop" -> {
                        val intent = Intent(this, TransferService::class.java).apply {
                            action = TransferService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "complete" -> {
                        postCompletion(call.argument<String>("text") ?: "Transfers finished")
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val fileName = call.argument<String>("fileName")
                        val mimeType =
                            call.argument<String>("mimeType") ?: "application/octet-stream"
                        if (sourcePath == null || fileName == null) {
                            result.error("ARGS", "sourcePath and fileName are required", null)
                        } else {
                            try {
                                result.success(saveToDownloads(sourcePath, fileName, mimeType))
                            } catch (e: Exception) {
                                result.error("SAVE_FAILED", e.message, null)
                            }
                        }
                    }
                    "getDeviceId" -> {
                        // Settings.Secure.ANDROID_ID: a stable per-device,
                        // per-signing-key id that survives clearing app data and
                        // reinstalls, so re-pairing reuses the same device row.
                        val id = Settings.Secure.getString(
                            contentResolver, Settings.Secure.ANDROID_ID)
                        result.success(id)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("ARGS", "path is required", null)
                        } else {
                            try {
                                installApk(path)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_FAILED", e.message, null)
                            }
                        }
                    }
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        val mimeType = call.argument<String>("mimeType")
                            ?: "application/octet-stream"
                        if (path == null) {
                            result.error("ARGS", "path is required", null)
                        } else {
                            try {
                                openFile(path, mimeType)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("OPEN_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Hands the downloaded [path] APK to Android's package installer via our own
     * FileProvider + ACTION_VIEW. The system installer then prompts the user
     * natively — including the "install unknown apps" permission if needed — so
     * we don't pre-check the permission ourselves (that check is unreliable on
     * Android 16 and was wrongly reporting "denied" even when granted).
     */
    /**
     * Posts a one-off, auto-dismissing notification summarising a finished
     * transfer batch (e.g. "3 done · 1 failed"), on its own channel separate
     * from the ongoing foreground-service notification.
     */
    private fun postCompletion(text: String) {
        val channelId = "transfers_done"
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            mgr.getNotificationChannel(channelId) == null
        ) {
            mgr.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Transfer results",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply { description = "Completed file transfers" },
            )
        }
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Transfers complete")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setAutoCancel(true)
            .build()
        mgr.notify(0x5255, notification)
    }

    private fun installApk(path: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    /**
     * Opens a file with the system's default handler via ACTION_VIEW. Uses
     * FileProvider so the receiving app gets read permission to our app-private
     * cache directory.
     */
    private fun openFile(path: String, mimeType: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        // Let the user choose an app if multiple handlers exist.
        startActivity(Intent.createChooser(intent, null))
    }

    /**
     * Copies [sourcePath] into the public Downloads collection so it is visible
     * in the system Files app. Uses MediaStore on API 29+ (scoped storage) and
     * the legacy public directory on older devices. Returns a human-readable
     * location like "Downloads/report.pdf".
     */
    private fun saveToDownloads(sourcePath: String, fileName: String, mimeType: String): String {
        val src = File(sourcePath)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val collection =
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("MediaStore insert returned null")
            // If anything below throws, the inserted row would otherwise stay
            // behind forever with IS_PENDING=1 — invisible in the Files app but
            // still occupying the display name (PR-76). Clean it up unless the
            // publish actually completes.
            var published = false
            try {
                resolver.openOutputStream(uri).use { out ->
                    src.inputStream().use { input -> input.copyTo(out!!) }
                }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                published = true
            } finally {
                if (!published) resolver.delete(uri, null, null)
            }
            return "Downloads/$fileName"
        } else {
            @Suppress("DEPRECATION")
            val dir =
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!dir.exists()) dir.mkdirs()
            val dest = File(dir, fileName)
            src.copyTo(dest, overwrite = true)
            return "Downloads/$fileName"
        }
    }
}
