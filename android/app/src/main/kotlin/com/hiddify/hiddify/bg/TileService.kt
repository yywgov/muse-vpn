package com.hiddify.hiddify.bg

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.hiddify.hiddify.Application
import com.hiddify.hiddify.MainActivity
import com.hiddify.hiddify.Settings
import com.hiddify.hiddify.constant.ServiceMode
import com.hiddify.hiddify.constant.Status
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@RequiresApi(24)
class TileService : TileService(), ServiceConnection.Callback {

    companion object {
        // 穿云 1.12.0: the node / delay 穿云 last sent for the home-screen widget (same store)
        private const val WIDGET_PREFS = "chuanyun_widget"

        /** The tile's second line: 「节点 · 延迟」 when connected, else 未连接 (pure, unit-testable). */
        fun subtitle(on: Boolean, node: String, delay: Int): String = when {
            !on -> "未连接"
            node.isBlank() -> "已连接"
            delay in 1..64999 -> "$node · $delay ms"
            else -> node
        }

        /** 穿云 says the node or delay changed: ask the system to refresh the tile (event, no polling). */
        fun refresh(context: android.content.Context) {
            try {
                requestListeningState(context, android.content.ComponentName(context, com.hiddify.hiddify.bg.TileService::class.java))
            } catch (_: Exception) {
            }
        }
    }

    private val connection = ServiceConnection(this, this)

    // 穿云 1.2: the tile always reads 穿云 and stays tappable while the service starts or stops
    // (it used to grey out as "unavailable" then).
    override fun onServiceStatusChanged(status: Status) {
        qsTile?.apply {
            label = getString(com.hiddify.hiddify.R.string.app_name)
            state =
                when (status) {
                    Status.Started, Status.Starting -> Tile.STATE_ACTIVE
                    else -> Tile.STATE_INACTIVE
                }
            // 穿云 1.12.0: 「节点 · 延迟」 under the name (Android 10+)
            if (android.os.Build.VERSION.SDK_INT >= 29) {
                val prefs = getSharedPreferences(WIDGET_PREFS, android.content.Context.MODE_PRIVATE)
                subtitle = subtitle(
                    status == Status.Started,
                    prefs.getString("node", "") ?: "",
                    prefs.getInt("delay", 0),
                )
            }
            updateTile()
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        onServiceStatusChanged(connection.status)
        connection.connect()
    }

    /** Without the VPN permission the tile can't start the service: open 穿云 to ask for it. */
    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (android.os.Build.VERSION.SDK_INT >= 34) {
            val pending = android.app.PendingIntent.getActivity(
                this, 0, intent, android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }

    override fun onStopListening() {
        connection.disconnect()
        super.onStopListening()
    }
    private fun toggleService() {
        when (connection.status) {
            Status.Stopped -> {
                if (android.net.VpnService.prepare(this) != null) {
                    openApp()
                    return
                }
                Settings.startCoreAfterStartingService = true
                BoxService.start()
                qsTile?.apply {
                    state = Tile.STATE_ACTIVE
                    updateTile()
                }
            }
            Status.Started -> {
                BoxService.stop("用户通过快捷开关断开")
                qsTile?.apply {
                    state = Tile.STATE_INACTIVE
                    updateTile()
                }
            }
            else -> {}
        }
    }

    override fun onClick() {
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (keyguardManager.isKeyguardLocked) {
            unlockAndRun {
                toggleService()
            }
        } else {
            toggleService()
        }
    }

}