package com.hiddify.hiddify.bg

// 穿云: receives the system's network-change broadcasts registered by [NetworkAuto].

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

class NetworkChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        // give Wi-Fi a moment to report its name after the network comes up
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                NetworkAuto.evaluate(context.applicationContext)
            } finally {
                pending.finish()
            }
        }, 1500)
    }
}
