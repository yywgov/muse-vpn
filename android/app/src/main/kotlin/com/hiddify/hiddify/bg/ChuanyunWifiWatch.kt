package com.hiddify.hiddify.bg

// 穿云 1.15.0 R23: 按 Wi‑Fi 切换模式——Wi‑Fi 连上 / 断开时通知 Dart（事件，不轮询）。
// 只在 Dart 订阅时（列表里有 Wi‑Fi）才注册系统网络回调，取消订阅即注销；构造时不碰 Context。
// Part of 穿云 (GPLv3).

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

class ChuanyunWifiWatch(private val contextOf: () -> Context) : EventChannel.StreamHandler {
    companion object {
        const val channelName = "com.chuanyun.app/network"
    }

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        unregister()
        val cm = try {
            contextOf().getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        } catch (_: Exception) {
            null
        } ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = emit("wifi_on")
            override fun onLost(network: Network) = emit("wifi_off")
        }
        try {
            val req = NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build()
            cm.registerNetworkCallback(req, cb)
            callback = cb
        } catch (_: Exception) {
            // no callback: the app still checks when it comes back to the front
        }
    }

    override fun onCancel(arguments: Any?) {
        unregister()
        sink = null
    }

    private fun emit(e: String) {
        main.post {
            try {
                sink?.success(e)
            } catch (_: Exception) {
            }
        }
    }

    fun unregister() {
        val cb = callback ?: return
        callback = null
        try {
            (contextOf().getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager)?.unregisterNetworkCallback(cb)
        } catch (_: Exception) {
        }
    }
}
