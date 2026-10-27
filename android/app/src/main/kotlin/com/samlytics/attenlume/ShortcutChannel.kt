package com.samlytics.attenlume

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Carries shortcut triggers (Quick Settings tile, launcher shortcuts, deep
 * links) to Dart as `attenlume://` URIs [P0-13, FR-HF-04, FR-HF-05].
 *
 * Kept thin on purpose: Dart's `ShortcutCommand.parse` decides what a URI
 * means. A command that arrives before Dart asks is held as the initial
 * command; later ones go straight over the channel.
 */
object ShortcutChannel {
    const val CHANNEL = "com.samlytics.attenlume/shortcuts"
    const val SCHEME = "attenlume"
    const val EXTRA_TRIGGERED_AT = "com.samlytics.attenlume.TRIGGERED_AT_MS"
    const val EXTRA_APP_VISIBLE = "com.samlytics.attenlume.APP_VISIBLE"
    private const val PREFS = "attenlume_shortcuts"
    private const val KEY_TILE_DIRECT = "tile_direct"

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var initial: Map<String, Any?>? = null
    private var dartAskedForInitial = false

    /** Number of app screens in the resumed state. Main thread only. */
    var visibleActivities = 0

    /** True once any activity of this process has been created. */
    var activityEverCreated = false

    /** Dart is running and has asked for its initial command. */
    val isAttached: Boolean
        get() = channel != null && dartAskedForInitial

    fun attach(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeInitialCommand" -> {
                        dartAskedForInitial = true
                        result.success(initial)
                        initial = null
                    }
                    "setTileDirect" -> {
                        val direct = call.argument<Boolean>("direct") == true
                        prefs(appContext).edit().putBoolean(KEY_TILE_DIRECT, direct).apply()
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
        dartAskedForInitial = false
    }

    fun tileDirect(context: Context): Boolean =
        prefs(context.applicationContext).getBoolean(KEY_TILE_DIRECT, false)

    /** The payload for [intent], or null if it carries no `attenlume://` URI. */
    fun payloadFor(intent: Intent?, coldStart: Boolean): Map<String, Any?>? {
        val data = intent?.data ?: return null
        if (!data.scheme.equals(SCHEME, ignoreCase = true)) return null
        val triggeredAt = intent.getLongExtra(EXTRA_TRIGGERED_AT, 0L)
        return mapOf(
            "uri" to data.toString(),
            "triggeredAtMs" to if (triggeredAt > 0L) triggeredAt else null,
            "coldStart" to coldStart,
            "appVisible" to if (intent.hasExtra(EXTRA_APP_VISIBLE)) {
                intent.getBooleanExtra(EXTRA_APP_VISIBLE, false)
            } else {
                null
            },
            "direct" to false,
        )
    }

    /** Sends [payload] now if Dart is listening, otherwise keeps it as the initial command. */
    fun deliver(payload: Map<String, Any?>) {
        main.post {
            val ch = channel
            if (ch != null && dartAskedForInitial) {
                ch.invokeMethod("command", payload)
            } else {
                initial = payload
            }
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
