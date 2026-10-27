package com.samlytics.attenlume

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
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
