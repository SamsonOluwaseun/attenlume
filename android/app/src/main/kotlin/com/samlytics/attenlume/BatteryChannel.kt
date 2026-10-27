package com.samlytics.attenlume

import android.content.Context
import android.os.BatteryManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Method channel reporting battery level and charging state to Dart for the
 * low-battery safety prompt [P1-13, FR-REC-06].
 */
object BatteryChannel : MethodChannel.MethodCallHandler {
    private const val CHANNEL = "com.samlytics.attenlume/battery"
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    fun attach(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        val ch = MethodChannel(messenger, CHANNEL)
        ch.setMethodCallHandler(this)
        channel = ch
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "readBattery") {
            result.notImplemented()
            return
        }
        val manager = appContext?.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        if (manager == null) {
            result.success(null)
            return
        }
        val percent = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        if (percent < 0 || percent > 100) {
            result.success(null)
            return
        }
        result.success(mapOf("percent" to percent, "charging" to manager.isCharging))
    }
}
