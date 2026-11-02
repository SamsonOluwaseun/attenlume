package com.samlytics.attenlume

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Method channel for the Android photo picker [P1-58, FR-PHO-05, ADR-074].
 *
 * Uses the system photo picker (ActivityResultContracts.PickMultipleVisualMedia)
 * without requiring READ_MEDIA_IMAGES permission. Picked streams are copied
 * directly to the app cache without re-encoding, preserving original EXIF capture times.
 */
object PhotoPickerChannel : MethodChannel.MethodCallHandler {
    private const val CHANNEL = "com.samlytics.attenlume/photo_picker"
    const val MAX_ITEMS = 50

    private var channel: MethodChannel? = null
    private var activity: MainActivity? = null
    private var pendingResult: MethodChannel.Result? = null
    private val executor = Executors.newSingleThreadExecutor()

    fun attach(messenger: BinaryMessenger, mainActivity: MainActivity) {
        activity = mainActivity
        val ch = MethodChannel(messenger, CHANNEL)
        ch.setMethodCallHandler(this)
        channel = ch
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        activity = null
        pendingResult?.let {
            it.success(emptyList<Map<String, Any>>())
            pendingResult = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> {
                val act = activity
                if (act == null) {
                    result.error("UNAVAILABLE", "Activity not attached", null)
                    return
                }
                if (pendingResult != null) {
                    pendingResult?.success(emptyList<Map<String, Any>>())
                    pendingResult = null
                }
                pendingResult = result
                val max = (call.argument<Int>("maxItems") ?: MAX_ITEMS).coerceIn(1, MAX_ITEMS)
                try {
                    act.launchPhotoPicker(max)
                } catch (e: Exception) {
                    pendingResult?.error("LAUNCH_FAILED", e.message, null)
                    pendingResult = null
                }
            }
            "cleanUp" -> {
                val act = activity
                if (act != null) {
                    executor.execute {
                        cleanPickedDir(act)
                        act.runOnUiThread {
                            result.success(true)
                        }
                    }
                } else {
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onPickerResult(uris: List<Uri>) {
        val res = pendingResult ?: return
        pendingResult = null
        val act = activity ?: run {
            res.success(emptyList<Map<String, Any>>())
            return
        }
        if (uris.isEmpty()) {
            res.success(emptyList<Map<String, Any>>())
            return
        }

        executor.execute {
            val list = mutableListOf<Map<String, Any>>()
            val cacheDir = File(act.cacheDir, "picked").apply { mkdirs() }
            val resolver = act.contentResolver

            for (uri in uris) {
                var displayName: String? = null
                try {
                    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val col = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (col >= 0) {
                                displayName = cursor.getString(col)
                            }
                        }
                    }
                } catch (_: Exception) {}

                val ext = when {
                    displayName != null && displayName!!.contains(".") -> {
                        val sub = displayName!!.substringAfterLast('.', "")
                        if (sub.isNotEmpty()) ".$sub" else ".jpg"
                    }
                    else -> {
                        val mime = resolver.getType(uri)
                        when (mime) {
                            "image/png" -> ".png"
                            "image/webp" -> ".webp"
                            "image/heic" -> ".heic"
                            else -> ".jpg"
                        }
                    }
                }

                val safeName = displayName ?: "${UUID.randomUUID()}$ext"
                val destFile = File(cacheDir, "${UUID.randomUUID()}$ext")

                var bytesWritten = 0L
                try {
                    resolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(destFile).use { output ->
                            bytesWritten = input.copyTo(output)
                        }
                    }
                    if (destFile.exists() && bytesWritten > 0) {
                        list.add(
                            mapOf(
                                "path" to destFile.absolutePath,
                                "name" to safeName,
                                "bytes" to bytesWritten
                            )
                        )
                    }
                } catch (_: Exception) {
                    // skip unreadable
                }
            }

            act.runOnUiThread {
                res.success(list)
            }
        }
    }

    fun cleanPickedDir(context: Context) {
        try {
            val cacheDir = File(context.cacheDir, "picked")
            if (cacheDir.exists() && cacheDir.isDirectory) {
                cacheDir.listFiles()?.forEach { it.delete() }
            }
        } catch (_: Exception) {}
    }
}

