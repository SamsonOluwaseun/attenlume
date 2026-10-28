package com.samlytics.attenlume

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat

/**
 * Android foreground service running with type `microphone` [P1-11, FR-REC-10, BUILD_GUIDE 10.2].
 *
 * Keeps audio capture alive when the app leaves the screen or device is locked,
 * presenting an ongoing persistent notification with live timer and actions:
 * Pause/Resume, Stop, Bookmark, and Photo.
 */
class RecordingForegroundService : Service() {

    companion object {
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "attenlume_recording_channel"

        const val ACTION_START = "com.samlytics.attenlume.START_SERVICE"
        const val ACTION_UPDATE = "com.samlytics.attenlume.UPDATE_NOTIFICATION"
        const val ACTION_STOP_SERVICE = "com.samlytics.attenlume.STOP_SERVICE"

        const val ACTION_PAUSE = "com.samlytics.attenlume.ACTION_PAUSE"
        const val ACTION_RESUME = "com.samlytics.attenlume.ACTION_RESUME"
        const val ACTION_STOP = "com.samlytics.attenlume.ACTION_STOP"
        const val ACTION_BOOKMARK = "com.samlytics.attenlume.ACTION_BOOKMARK"
        const val ACTION_PHOTO = "com.samlytics.attenlume.ACTION_PHOTO"

        const val EXTRA_ACTIVITY_ID = "activityId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_STATE = "state"
        const val EXTRA_ELAPSED_MS = "elapsedMs"
        const val EXTRA_BASE_TIME_MS = "baseTimeMs"
        const val EXTRA_MESSAGE = "message"
    }

    private var currentTitle: String = ""
    private var currentState: String = "idle"
    private var currentActivityId: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_NOT_STICKY

        when (action) {
            ACTION_START -> {
                currentActivityId = intent.getStringExtra(EXTRA_ACTIVITY_ID)
                currentTitle = intent.getStringExtra(EXTRA_TITLE) ?: ""
                currentState = intent.getStringExtra(EXTRA_STATE) ?: "recording"
                val elapsedMs = if (intent.hasExtra(EXTRA_ELAPSED_MS)) intent.getLongExtra(EXTRA_ELAPSED_MS, 0L) else null
                val baseTimeMs = if (intent.hasExtra(EXTRA_BASE_TIME_MS)) intent.getLongExtra(EXTRA_BASE_TIME_MS, 0L) else null
                val message = intent.getStringExtra(EXTRA_MESSAGE)

                val notification = buildNotification(currentTitle, currentState, elapsedMs, baseTimeMs, message)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ServiceCompat.startForeground(
                        this,
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }

            ACTION_UPDATE -> {
                intent.getStringExtra(EXTRA_ACTIVITY_ID)?.let { currentActivityId = it }
                intent.getStringExtra(EXTRA_TITLE)?.let { currentTitle = it }
                intent.getStringExtra(EXTRA_STATE)?.let { currentState = it }
                val elapsedMs = if (intent.hasExtra(EXTRA_ELAPSED_MS)) intent.getLongExtra(EXTRA_ELAPSED_MS, 0L) else null
                val baseTimeMs = if (intent.hasExtra(EXTRA_BASE_TIME_MS)) intent.getLongExtra(EXTRA_BASE_TIME_MS, 0L) else null
                val message = intent.getStringExtra(EXTRA_MESSAGE)

                val notification = buildNotification(currentTitle, currentState, elapsedMs, baseTimeMs, message)
                try {
                    NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
                } catch (_: SecurityException) {
                    // Ignored if notification permission revoked while running
                }
            }

            ACTION_STOP_SERVICE -> {
                ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelf()
            }

            ACTION_PAUSE -> ForegroundServiceChannel.deliverAction("pause", currentActivityId)
            ACTION_RESUME -> ForegroundServiceChannel.deliverAction("resume", currentActivityId)
            ACTION_STOP -> ForegroundServiceChannel.deliverAction("stop", currentActivityId)
            ACTION_BOOKMARK -> ForegroundServiceChannel.deliverAction("bookmark", currentActivityId)
            ACTION_PHOTO -> ForegroundServiceChannel.deliverAction("photo", currentActivityId)
        }

        return START_NOT_STICKY
    }

    private fun ensureChannelCreated() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.notification_channel_name),
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = getString(R.string.notification_channel_description)
                    setShowBadge(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(
        title: String,
        state: String,
        elapsedMs: Long?,
        baseTimeMs: Long?,
        message: String?
    ): Notification {
        ensureChannelCreated()

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_tile_record)
            .setContentTitle(if (title.isNotBlank()) title else "Attenlume")
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        val isActivelyRecording = state.equals("recording", ignoreCase = true)
        if (isActivelyRecording) {
            // The chronometer counts up from `when`, which is wall-clock time
            // (System.currentTimeMillis), not SystemClock.elapsedRealtime.
            val startedAt = if (baseTimeMs != null && baseTimeMs > 0) {
                baseTimeMs
            } else if (elapsedMs != null && elapsedMs > 0) {
                System.currentTimeMillis() - elapsedMs
            } else {
                System.currentTimeMillis()
            }
            builder.setUsesChronometer(true)
            builder.setShowWhen(true)
            builder.setWhen(startedAt)
            builder.setContentText(message ?: "Recording")
        } else {
            builder.setUsesChronometer(false)
            val statusText = when {
                message != null && message.isNotBlank() -> message
                state.equals("paused", ignoreCase = true) -> "Recording paused"
                state.equals("interrupted", ignoreCase = true) || state.equals("userResumeRequired", ignoreCase = true) ->
                    "Recording interrupted. Tap Resume to continue."
                else -> state.replaceFirstChar { it.uppercase() }
            }
            builder.setContentText(statusText)
        }

        val isPaused = state.equals("paused", ignoreCase = true)
        val isInterrupted = state.equals("interrupted", ignoreCase = true) || state.equals("userResumeRequired", ignoreCase = true)

        if (isActivelyRecording) {
            builder.addAction(
                android.R.drawable.ic_media_pause,
                getString(R.string.notification_action_pause),
                actionPendingIntent(ACTION_PAUSE, 1)
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.notification_action_stop),
                actionPendingIntent(ACTION_STOP, 2)
            )
            builder.addAction(
                android.R.drawable.star_off,
                getString(R.string.notification_action_bookmark),
                actionPendingIntent(ACTION_BOOKMARK, 3)
            )
            builder.addAction(
                android.R.drawable.ic_menu_camera,
                getString(R.string.notification_action_photo),
                photoPendingIntent()
            )
        } else if (isPaused) {
            builder.addAction(
                android.R.drawable.ic_media_play,
                getString(R.string.notification_action_resume),
                actionPendingIntent(ACTION_RESUME, 1)
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.notification_action_stop),
                actionPendingIntent(ACTION_STOP, 2)
            )
            builder.addAction(
                android.R.drawable.star_off,
                getString(R.string.notification_action_bookmark),
                actionPendingIntent(ACTION_BOOKMARK, 3)
            )
            builder.addAction(
                android.R.drawable.ic_menu_camera,
                getString(R.string.notification_action_photo),
                photoPendingIntent()
            )
        } else if (isInterrupted) {
            builder.addAction(
                android.R.drawable.ic_media_play,
                getString(R.string.notification_action_resume),
                actionPendingIntent(ACTION_RESUME, 1)
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.notification_action_stop),
                actionPendingIntent(ACTION_STOP, 2)
            )
        }

        return builder.build()
    }

    private fun actionPendingIntent(actionName: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, RecordingForegroundService::class.java).apply {
            action = actionName
        }
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun photoPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            data = Uri.parse("attenlume://photo?source=notification")
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            4,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
