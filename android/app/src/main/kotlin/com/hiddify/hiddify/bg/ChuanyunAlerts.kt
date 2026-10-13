package com.hiddify.hiddify.bg

// 穿云 1.1: one-off system notifications (穿云已断开, subscription running out) on their own
// channel, separate from the foreground-service status notification.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.hiddify.hiddify.Application
import com.hiddify.hiddify.MainActivity
import com.hiddify.hiddify.R

object ChuanyunAlerts {
    private const val CHANNEL = "chuanyun_alerts"
    const val ID_DISCONNECTED = 2101
    const val ID_SUBSCRIPTION = 2102

    fun show(context: Context, id: Int, title: String, text: String) {
        val nm = Application.notification
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "提醒", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val tap = PendingIntent.getActivity(
            context,
            id,
            Intent(context, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NEW_TASK),
            flags,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_logo)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(id, notification)
        } catch (_: SecurityException) {
        }
    }

    fun cancel(id: Int) {
        try {
            Application.notification.cancel(id)
        } catch (_: Exception) {
        }
    }
}
