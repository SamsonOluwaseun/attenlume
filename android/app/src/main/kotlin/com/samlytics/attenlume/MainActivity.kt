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
    private var policyLinkChannel: MethodChannel? = null
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
        // Opens only the published privacy policy (FR-PRI-07), in every build,
        // including Play builds where the support link is disabled.
        policyLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.samlytics.attenlume/policy_link"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                } else if (call.arguments as? String != PRIVACY_POLICY_URL) {
                    result.success(false)
                } else {
                    try {
                        startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_POLICY_URL))
                                .addCategory(Intent.CATEGORY_BROWSABLE)
                        )
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        policyLinkChannel?.setMethodCallHandler(null)
        policyLinkChannel = null
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

    private companion object {
        // Must match privacyPolicyUrl in lib/features/privacy/privacy_policy_link.dart.
        const val PRIVACY_POLICY_URL =
            "https://www.samlytics.co.uk/attenlume-policy/attenlume-privacy.html"
    }
}
