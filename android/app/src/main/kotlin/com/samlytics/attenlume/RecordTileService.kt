package com.samlytics.attenlume

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile that starts or stops a recording [P0-13, FR-HF-04].
 *
 * Default: a tap opens the app with `attenlume://record/toggle?source=tile`,
 * because a microphone foreground service must be started while the app is
 * visible on Android 14 and later. Spike mode ("direct", set from Dart): if
 * the app is already running, the command goes straight to it and the app
 * is not opened, so MT-22 can observe whether background capture is
 * allowed or silenced. Phase 2 (P2-03) adds tile state and confirmation.
 */
class RecordTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            label = getString(R.string.tile_record_label)
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val triggeredAt = System.currentTimeMillis()
        val appVisible = ShortcutChannel.visibleActivities > 0
        val uri = Uri.parse("${ShortcutChannel.SCHEME}://record/toggle?source=tile")

        if (ShortcutChannel.tileDirect(this) && ShortcutChannel.isAttached) {
            ShortcutChannel.deliver(
                mapOf(
                    "uri" to uri.toString(),
                    "triggeredAtMs" to triggeredAt,
                    "coldStart" to false,
                    "appVisible" to appVisible,
                    "direct" to true,
                ),
            )
            return
        }

        val open = Intent(Intent.ACTION_VIEW, uri, this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(ShortcutChannel.EXTRA_TRIGGERED_AT, triggeredAt)
            putExtra(ShortcutChannel.EXTRA_APP_VISIBLE, appVisible)
        }
        if (isLocked) {
            unlockAndRun { launch(open) }
        } else {
            launch(open)
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun launch(open: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pending = PendingIntent.getActivity(
                this,
                0,
                open,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(open)
        }
    }
}
