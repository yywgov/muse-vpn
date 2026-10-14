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