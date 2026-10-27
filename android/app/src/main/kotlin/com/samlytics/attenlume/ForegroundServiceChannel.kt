package com.samlytics.attenlume

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * MethodChannel bridge for controlling the Android Foreground Service and
 * receiving user notification actions [P1-11, FR-REC-10].
 */
object ForegroundServiceChannel {
    const val CHANNEL = "com.samlytics.attenlume/foreground_service"
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activity: WeakReference<Activity>? = null
    private var askedForNotifications = false
    private const val NOTIFICATION_REQUEST_CODE = 4211

    fun attach(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        activity = (context as? Activity)?.let { WeakReference(it) }
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        val ctx = appContext ?: return@setMethodCallHandler result.error("NO_CONTEXT", "No context", null)
                        val elapsedMs = (call.argument<Number>("elapsedMs"))?.toLong()
                        val baseTimeMs = (call.argument<Number>("baseTimeMs"))?.toLong()

                        val intent = Intent(ctx, RecordingForegroundService::class.java).apply {
                            action = RecordingForegroundService.ACTION_START
                            putExtra(RecordingForegroundService.EXTRA_ACTIVITY_ID, call.argument<String>("activityId"))
                            putExtra(RecordingForegroundService.EXTRA_TITLE, call.argument<String>("title"))
                            putExtra(RecordingForegroundService.EXTRA_STATE, call.argument<String>("state"))
                            elapsedMs?.let { putExtra(RecordingForegroundService.EXTRA_ELAPSED_MS, it) }
                            baseTimeMs?.let { putExtra(RecordingForegroundService.EXTRA_BASE_TIME_MS, it) }
                            putExtra(RecordingForegroundService.EXTRA_MESSAGE, call.argument<String>("message"))
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ctx.startForegroundService(intent)
                        } else {
                            ctx.startService(intent)
                        }
                        requestNotificationPermission()
                        result.success(null)
                    }

                    "updateNotification" -> {
                        val ctx = appContext ?: return@setMethodCallHandler result.error("NO_CONTEXT", "No context", null)
                        val elapsedMs = (call.argument<Number>("elapsedMs"))?.toLong()
                        val baseTimeMs = (call.argument<Number>("baseTimeMs"))?.toLong()

                        val intent = Intent(ctx, RecordingForegroundService::class.java).apply {
                            action = RecordingForegroundService.ACTION_UPDATE
                            putExtra(RecordingForegroundService.EXTRA_ACTIVITY_ID, call.argument<String>("activityId"))
                            putExtra(RecordingForegroundService.EXTRA_TITLE, call.argument<String>("title"))
                            putExtra(RecordingForegroundService.EXTRA_STATE, call.argument<String>("state"))
                            elapsedMs?.let { putExtra(RecordingForegroundService.EXTRA_ELAPSED_MS, it) }
                            baseTimeMs?.let { putExtra(RecordingForegroundService.EXTRA_BASE_TIME_MS, it) }
                            putExtra(RecordingForegroundService.EXTRA_MESSAGE, call.argument<String>("message"))
                        }
                        ctx.startService(intent)
                        result.success(null)
                    }

                    "stopService" -> {
                        val ctx = appContext ?: return@setMethodCallHandler result.error("NO_CONTEXT", "No context", null)
                        val intent = Intent(ctx, RecordingForegroundService::class.java).apply {
                            action = RecordingForegroundService.ACTION_STOP_SERVICE
                        }
                        ctx.startService(intent)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
        activity = null
    }

    /**
     * Android 13+ hides the recording notification, and its Pause, Stop and
     * Bookmark actions, until the user allows notifications (ADR-029).
     * Asks once per app run, the first time a recording starts. Recording
     * carries on whatever the answer.
     */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || askedForNotifications) return
        val host = activity?.get() ?: return
        if (host.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) return
        askedForNotifications = true
        host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST_CODE)
    }

    fun deliverAction(action: String, activityId: String? = null) {
        main.post {
            channel?.invokeMethod(
                "onAction",
                mapOf(
                    "action" to action,
                    "activityId" to activityId
                )
            )
        }
    }
}
