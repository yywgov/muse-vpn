package com.hiddify.hiddify

// 穿云 1.6.0 C9 - automation entry: other apps (Tasker, MacroDroid, a launcher gesture…) can send
// com.chuanyun.app.action.START / STOP / TOGGLE to connect, disconnect or switch. No screen: the
// activity is translucent, asks the VPN service for its status, forwards to the same start / stop
// entry points as the quick-settings tile and finishes right away. When the VPN permission is not
// granted yet, START opens 穿云 with chuanyun://connect so the normal connect flow asks for it.
// The VPN service itself is not changed. Part of 穿云 (GPLv3).

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.hiddify.hiddify.bg.BoxService
import com.hiddify.hiddify.bg.ServiceConnection
import com.hiddify.hiddify.constant.ServiceMode
import com.hiddify.hiddify.constant.Status

/** What one automation action does. */
enum class QuickStep { START, STOP, NONE }

class QuickActionActivity : Activity(), ServiceConnection.Callback {

    companion object {
        const val ACTION_START = "com.chuanyun.app.action.START"
        const val ACTION_STOP = "com.chuanyun.app.action.STOP"
        const val ACTION_TOGGLE = "com.chuanyun.app.action.TOGGLE"

        val actions = setOf(ACTION_START, ACTION_STOP, ACTION_TOGGLE)

        /** What an action does in a given service state (starting / stopping: nothing). */
        fun decide(action: String?, status: Status): QuickStep = when (action) {
            ACTION_START -> if (status == Status.Stopped) QuickStep.START else QuickStep.NONE
            ACTION_STOP -> if (status == Status.Started) QuickStep.STOP else QuickStep.NONE
            ACTION_TOGGLE -> when (status) {
                Status.Stopped -> QuickStep.START
                Status.Started -> QuickStep.STOP
                else -> QuickStep.NONE
            }
            else -> QuickStep.NONE
        }
    }

    private val connection = ServiceConnection(this, this, false)
    private val handler = Handler(Looper.getMainLooper())
    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val action = intent?.action
        if (action == null || action !in actions) {
            finish()
            return
        }
        connection.connect()
        // the service answers within a moment; never stay around if it does not
        handler.postDelayed({ done() }, 5_000)
    }

    override fun onServiceStatusChanged(status: Status) {
        handler.post {
            if (handled) return@post
            when (decide(intent?.action, status)) {
                QuickStep.START -> start()
                QuickStep.STOP -> BoxService.stop("自动化指令断开")
                QuickStep.NONE -> {}
            }
            done()
        }
    }

    private fun start() {
        if (Settings.serviceMode == ServiceMode.VPN && VpnService.prepare(this) != null) {
            // the system dialog needs 穿云's own screen
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("chuanyun://connect"), this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return
        }
        Settings.startCoreAfterStartingService = true
        BoxService.start()
    }

    private fun done() {
        handled = true
        if (isFinishing) return
        finish()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        connection.disconnect()
        super.onDestroy()
    }
}
