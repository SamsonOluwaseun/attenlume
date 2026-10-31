package com.samlytics.attenlume

import android.content.Intent
import android.os.Bundle
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity because local_auth shows the system biometric or
// device credential prompt as a fragment (FR-PRI-06, ADR-041).
class MainActivity : FlutterFragmentActivity() {
    private var supportLinkChannel: MethodChannel? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        val coldStart = !ShortcutChannel.activityEverCreated
        ShortcutChannel.activityEverCreated = true
        super.onCreate(savedInstanceState)
        // A recreated activity must not replay the trigger that opened it.
        if (savedInstanceState == null) {
            ShortcutChannel.payloadFor(intent, coldStart)?.let(ShortcutChannel::deliver)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ShortcutChannel.attach(flutterEngine.dartExecutor.binaryMessenger, this)
        ForegroundServiceChannel.attach(flutterEngine.dartExecutor.binaryMessenger, this)
        FreeSpaceChannel.attach(flutterEngine.dartExecutor.binaryMessenger)
        BatteryChannel.attach(flutterEngine.dartExecutor.binaryMessenger, this)
        supportLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.samlytics.attenlume/support_link"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                } else {
                    try {
                        val uri = Uri.parse(call.arguments as? String ?: "")
                        val hosts = setOf("paypal.me", "www.paypal.me", "paypal.com", "www.paypal.com")
                        if (uri.scheme != "https" || uri.host?.lowercase() !in hosts ||
                            uri.userInfo != null || (uri.port != -1 && uri.port != 443)) {
                            result.success(false)
                        } else {
                            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                            result.success(true)
                        }
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        supportLinkChannel?.setMethodCallHandler(null)
        supportLinkChannel = null
        BatteryChannel.detach()
        FreeSpaceChannel.detach()
        ForegroundServiceChannel.detach()
        ShortcutChannel.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ShortcutChannel.payloadFor(intent, coldStart = false)?.let(ShortcutChannel::deliver)
    }

    override fun onResume() {
        super.onResume()
        ShortcutChannel.visibleActivities++
    }

    override fun onPause() {
        ShortcutChannel.visibleActivities--
        super.onPause()
    }
}
