package com.samlytics.attenlume

import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Method channel bridging free and total volume space to Dart [P1-12, FR-STO-01].
 */
object FreeSpaceChannel : MethodChannel.MethodCallHandler {
    private const val CHANNEL = "com.samlytics.attenlume/free_space"
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL)
        ch.setMethodCallHandler(this)
        channel = ch
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "queryFreeSpace") {
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("INVALID_ARGUMENT", "Path is required", null)
                return
            }
            try {
                var file = File(path)
                while (!file.exists()) {
                    val parent = file.parentFile ?: break
                    file = parent
                }
                if (!file.exists()) {
                    result.success(null)
                    return
                }
                val stat = StatFs(file.absolutePath)
                val availableBytes = stat.availableBytes
                val totalBytes = stat.totalBytes
                result.success(
                    mapOf(
                        "availableBytes" to availableBytes,
                        "totalBytes" to totalBytes
                    )
                )
            } catch (e: Exception) {
                result.error("STATFS_FAILED", e.localizedMessage, null)
            }
        } else {
            result.notImplemented()
        }
    }
}
