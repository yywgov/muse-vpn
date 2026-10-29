package com.hiddify.hiddify.bg

// 穿云 1.7.0: proxy-only service of 兼容内核 (no TUN), in the :compat process.
// Part of 穿云 (GPLv3).

import android.app.Service
import android.content.Intent
import android.os.IBinder

class CompatProxyService : Service() {
    private val runner = CompatService(this, null)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = runner.onStartCommand(intent)

    override fun onBind(intent: Intent): IBinder = runner.onBind(intent)

    override fun onDestroy() {
        runner.onDestroy()
        super.onDestroy()
    }
}
