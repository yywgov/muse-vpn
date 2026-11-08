package com.hiddify.hiddify.bg

// 穿云 1.18.0 P6: 省电模式开关通知 Dart（动效降为「精简」）。只在 Dart 订阅时（外观 › 动效 =
// 跟随系统）动态注册 ACTION_POWER_SAVE_MODE_CHANGED（该广播只发给动态注册的接收器），取消订阅即注销；
// 不轮询；构造时不碰 Context。
// Part of 穿云 (GPLv3).

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

class ChuanyunPowerWatch(private val contextOf: () -> Context) : EventChannel.StreamHandler {
    companion object {
        const val channelName = "com.chuanyun.app/power"

        fun isPowerSave(context: Context): Boolean = try {
            (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode == true
        } catch (_: Exception) {
            false
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        unregister()
        val ctx = try {
            contextOf().applicationContext
        } catch (_: Exception) {
            null
        } ?: return
        emit(isPowerSave(ctx))
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) = emit(isPowerSave(c))
        }
        try {
            ContextCompat.registerReceiver(
                ctx, r, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED), ContextCompat.RECEIVER_NOT_EXPORTED
            )
            receiver = r
        } catch (_: Exception) {
            // no receiver: the level is read again the next time Dart subscribes
        }
    }

    override fun onCancel(arguments: Any?) {
        unregister()
        sink = null
    }

    private fun emit(on: Boolean) {
        main.post {
            try {
                sink?.success(on)
            } catch (_: Exception) {
            }
        }
    }

    fun unregister() {
        val r = receiver ?: return
        receiver = null
        try {
            contextOf().applicationContext.unregisterReceiver(r)
        } catch (_: Exception) {
        }
    }
}
