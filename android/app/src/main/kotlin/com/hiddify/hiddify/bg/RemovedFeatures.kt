package com.hiddify.hiddify.bg

// 穿云 1.2.1: clean-up for features that were removed, run at every process start.
// 「按网络自动开关」 (1.0–1.2.0) disconnected on a trusted Wi-Fi and reconnected when leaving it.
// After the update nothing of it may act again: its prefs are deleted, the system network
// watcher it registered with a PendingIntent (which outlives the process) is unregistered and
// cancelled, and its "tap to reconnect" notification and channel are removed. The receiver class
// it pointed at no longer exists either, so even a missed watcher would deliver nowhere.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.hiddify.hiddify.constant.SettingsKey

object RemovedFeatures {
    private const val TAG = "A/RemovedFeatures"

    /** Keys 1.2.0 wrote for 按网络自动开关 (FlutterSharedPreferences, "flutter." prefix). */
    val NET_AUTO_KEYS = listOf(SettingsKey.NET_AUTO_ENABLED, SettingsKey.NET_TRUSTED_SSIDS, SettingsKey.NET_AUTO_PAUSED)
    const val OLD_RECEIVER = "com.hiddify.hiddify.bg.NetworkChangeReceiver"
    const val OLD_NOTIFY_CHANNEL = "chuanyun_auto_connect"
    const val OLD_NOTIFY_ID = 7

    fun cleanUp(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (NET_AUTO_KEYS.any { prefs.contains(it) }) {
                prefs.edit().apply { NET_AUTO_KEYS.forEach { remove(it) } }.apply()
                DisconnectLog.record("已移除旧的「按网络自动开关」设置")
            }
        } catch (e: Exception) {
            Log.w(TAG, "prefs clean-up failed", e)
        }
        try {
            // the same PendingIntent 1.2.0 registered (same component + package = same identity)
            val intent = Intent().setComponent(ComponentName(context.packageName, OLD_RECEIVER))
                .setPackage(context.packageName)
            val flags = PendingIntent.FLAG_NO_CREATE or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val pi = PendingIntent.getBroadcast(context, 0, intent, flags)
            if (pi != null) {
                val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                try {
                    cm.unregisterNetworkCallback(pi)
                } catch (_: Exception) {
                }
                pi.cancel()
                Log.i(TAG, "old network watcher removed")
            }
        } catch (e: Exception) {
            Log.w(TAG, "network watcher clean-up failed", e)
        }
        try {
            val nm = NotificationManagerCompat.from(context)
            nm.cancel(OLD_NOTIFY_ID)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) nm.deleteNotificationChannel(OLD_NOTIFY_CHANNEL)
        } catch (_: Exception) {
        }
    }
}
