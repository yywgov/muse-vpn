package com.hiddify.hiddify.bg

// 穿云: 按网络自动开关 — disconnect on trusted Wi-Fi, reconnect when leaving it.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.hiddify.hiddify.Application
import com.hiddify.hiddify.R
import com.hiddify.hiddify.Settings
import com.hiddify.hiddify.ShortcutActivity

object NetworkAuto {
    private const val TAG = "A/NetworkAuto"
    private const val NOTIFY_CHANNEL = "chuanyun_auto_connect"
    private const val NOTIFY_ID = 7

    /** True while 穿云 itself is stopping the tunnel, so the stop isn't taken as the user's. */
    @Volatile
    var autoStopping = false

    private fun pendingIntent(context: Context): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, NetworkChangeReceiver::class.java).setPackage(context.packageName),
            flags,
        )
    }

    /** (Re)registers or removes the system network watcher. It survives the app process being killed. */
    fun apply(context: Context) {
        val cm = Application.connectivity
        val pi = pendingIntent(context)
        try {
            cm.unregisterNetworkCallback(pi)
        } catch (_: Exception) {
        }
        if (!Settings.netAutoEnabled) return
        try {
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build()
            cm.registerNetworkCallback(request, pi)
        } catch (e: Exception) {
            Log.w(TAG, "registerNetworkCallback failed", e)
        }
    }

    fun hasLocationPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

    fun hasBackgroundLocationPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

    /** The connected Wi-Fi's name, or null when not on Wi-Fi or Android hides it (no location access). */
    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    fun currentSsid(context: Context): String? {
        if (!hasLocationPermission(context)) return null
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return null
        val info = wifi.connectionInfo ?: return null
        if (info.networkId == -1) return null
        val ssid = info.ssid?.trim()?.removePrefix("\"")?.removeSuffix("\"") ?: return null
        if (ssid.isEmpty() || ssid == "<unknown ssid>") return null
        return ssid
    }

    /** Whether a non-VPN network with internet access is up right now. */
    fun hasUsableNetworkNow(): Boolean = hasUsableNetwork()

    private fun hasUsableNetwork(): Boolean {
        val cm = Application.connectivity
        @Suppress("DEPRECATION")
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            ) return true
        }
        return false
    }

    /** Decides what to do for the network the device is on now. */
    fun evaluate(context: Context) {
        if (!Settings.netAutoEnabled) return
        val ssid = currentSsid(context)
        val trusted = ssid != null && Settings.netTrustedSsids.contains(ssid)
        val running = Settings.startedByUser
        Log.d(TAG, "evaluate ssid=$ssid trusted=$trusted running=$running paused=${Settings.netAutoPaused}")
        if (running && trusted) {
            autoStopping = true
            Settings.netAutoPaused = true
            BoxService.stop("按网络自动开关：连上可信 Wi-Fi「$ssid」，自动断开")
            return
        }
        if (!running && !trusted && Settings.netAutoPaused && hasUsableNetwork()) {
            reconnect(context)
        }
    }

    private fun reconnect(context: Context) {
        if (VpnService.prepare(context) != null) {
            // VPN permission was revoked; only the user can grant it again
            notifyTapToConnect(context)
            return
        }
        try {
            Settings.startCoreAfterStartingService = true
            BoxService.start()
            cancelNotification()
        } catch (e: Exception) {
            // Android 12+ may refuse to start a foreground service from the background
            Log.w(TAG, "background start refused", e)
            notifyTapToConnect(context)
        }
    }

    private fun notifyTapToConnect(context: Context) {
        val nm = Application.notification
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    NOTIFY_CHANNEL,
                    context.getString(R.string.auto_connect_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val tap = PendingIntent.getActivity(
            context,
            1,
            Intent(context, ShortcutActivity::class.java).setAction(Intent.ACTION_MAIN)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            flags,
        )
        val notification = NotificationCompat.Builder(context, NOTIFY_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_logo)
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText(context.getString(R.string.auto_connect_tap))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(NOTIFY_ID, notification)
        } catch (_: SecurityException) {
        }
    }

    fun cancelNotification() {
        try {
            Application.notification.cancel(NOTIFY_ID)
        } catch (_: Exception) {
        }
    }
}
