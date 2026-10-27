package com.hiddify.hiddify.bg

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.annotation.StringRes
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.lifecycle.MutableLiveData
import com.hiddify.core.api.v2.config.Protocol
import com.hiddify.core.api.v2.hcommon.Empty
import com.hiddify.core.api.v2.hcore.CoreClient
import com.hiddify.core.api.v2.hcore.SystemInfo
import com.hiddify.core.api.v2.hello.HelloClient
import com.hiddify.core.api.v2.hello.HelloRequest
import com.hiddify.hiddify.Application
import com.hiddify.hiddify.MainActivity
import com.hiddify.hiddify.R
import com.hiddify.hiddify.Settings
import com.hiddify.hiddify.constant.Action
import com.hiddify.hiddify.constant.Status
//import com.hiddify.hiddify.utils.CommandClient
import com.hiddify.core.libbox.Libbox
import com.hiddify.hiddify.Application.Companion.notification
import com.hiddify.hiddify.utils.GrpcClientProvider
import com.squareup.wire.GrpcClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.isActive

import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import java.io.IOException
import kotlinx.coroutines.delay
import kotlinx.coroutines.CancellationException
class ServiceNotification(private val status: MutableLiveData<Status>, private val service: Service) : BroadcastReceiver(){
    companion object {
        private const val notificationId = 1
        // 穿云: two channels because a channel's importance can't change once created.
        // "隐藏通知" uses the MIN channel: no status-bar icon, folded into the silent section.
        private const val channelNormal = "chuanyun_status"
        private const val channelMin = "chuanyun_status_min"
        private val notificationChannel get() = if (Settings.hideNotification) channelMin else channelNormal
        var coreClient: CoreClient?=null
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        fun checkPermission(): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                return true
            }
            return Application.notification.areNotificationsEnabled()
        }
    }
    val streamingCoroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())


//
//    private val commandClient =
//            CommandClient(GlobalScope, CommandClient.ConnectionType.Status, this)
    private var receiverRegistered = false


    private val notificationBuilder by lazy {
        NotificationCompat.Builder(service, notificationChannel)
                .setShowWhen(false)
                .setOngoing(true)
                .setContentTitle(service.getString(R.string.app_name))
                .setOnlyAlertOnce(true)
                .setSmallIcon(R.drawable.ic_stat_logo)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setContentIntent(
                        PendingIntent.getActivity(
                                service,
                                0,
                                Intent(
                                        service,
                                        MainActivity::class.java
                                ).setFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
                                flags
                        )
                )
                .setPriority(if (Settings.hideNotification) NotificationCompat.PRIORITY_MIN else NotificationCompat.PRIORITY_LOW).apply {
                    // 穿云 1.6.0 C9: 设置 › 通知栏「断开」按钮 can turn it off (applies from the next connection)
                    if (Settings.notifyStopButton) addAction(
                            NotificationCompat.Action.Builder(
                                    0, service.getText(R.string.stop), PendingIntent.getBroadcast(
                                    service,
                                    0,
                                    Intent(Action.SERVICE_CLOSE).setPackage(
                                        Application.application.packageName
                                    ),
                                    flags
                            )
                            ).build()
                    )
                }
    }

    fun show(profileName: String, @StringRes contentTextId: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = if (Settings.hideNotification) NotificationManager.IMPORTANCE_MIN else NotificationManager.IMPORTANCE_LOW
            Application.notification.createNotificationChannel(
                NotificationChannel(
                    notificationChannel, service.getString(R.string.notification_channel_name), importance
                ).apply {
                    description = service.getString(R.string.notification_channel_desc)
                    setShowBadge(false)
                }
            )
        }
        activeTitle = profileName.takeIf { it.isNotBlank() }
        lastText = null
        service.startForeground(
            notificationId, notificationBuilder
                .setContentTitle(profileName.takeIf { it.isNotBlank() } ?: service.getString(R.string.app_name))
                .setContentText(service.getString(contentTextId)).build()
        )
    }


    suspend fun start() {
        // 穿云: the screen receiver also drives the core's screen-off test interval, so it is
        // registered even when notifications are not allowed
        withContext(Dispatchers.Main) {
            registerReceiver()
        }
        // the core keeps the last screen state; start from the real one
        ChuanyunLabels.screenChanged(Application.powerManager.isInteractive)
        if (checkPermission()) {
            startListenSystemInfo()
        }
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        service.registerReceiver(this, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        })
        receiverRegistered = true
    }

    private var lastText: String? = null

    /** 穿云: 「已连接 · 自动最快 · 节点」 under the profile name; no speed (it was always 0 and confusing). */
    fun updateStatus(status: SystemInfo) {
        val content = ChuanyunLabels.notificationText(status.current_outbound)
        val title = status.current_profile.ifBlank { activeTitle ?: service.getString(R.string.app_name) }
        val text = "$title\n$content"
        if (text == lastText) return
        lastText = text
        Application.notificationManager.notify(
                notificationId,
                notificationBuilder.setContentTitle(title).setContentText(content).build()
        )
    }

    private var activeTitle: String? = null

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> {
                ChuanyunLabels.screenChanged(true)
                if (checkPermission()) startListenSystemInfo()
            }

            Intent.ACTION_SCREEN_OFF -> {
                ChuanyunLabels.screenChanged(false)
                stopListenSystemInfo()
            }
        }
    }

    fun close() {
        stopListenSystemInfo()
        lastText = null
        ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE)
        if (receiverRegistered) {
            service.unregisterReceiver(this)
            receiverRegistered = false
        }
    }

    private var streamingJob: Job? = null

    fun startListenSystemInfo() {
        // Cancel any previous stream if still running
        Log.d("notification","startListenSystemInfo")
        streamingJob?.cancel()

        streamingJob = streamingCoroutineScope.launch(Dispatchers.IO) {
            Log.d("notification", "startListenSystemInfo-launch")

            val coreClient = GrpcClientProvider.grpcClient.create(CoreClient::class)

            // 穿云: this used to cancel the notification when polling stopped (screen off) or
            // one poll failed. That notification belongs to the foreground service: removing it
            // (some ROMs honour the cancel) leaves the VPN service looking like a background
            // app that ColorOS freezes or kills. Now a failed poll is just retried, and the
            // notification keeps its last text when polling stops.
            var failures = 0
            while (isActive) {
                try {
                    val current = coreClient.GetSystemInfo().executeBlocking(Empty())
                    updateStatus(current)
                    failures = 0
                    // only the node name is shown now, so a slow poll is enough
                    delay(3_000)
                } catch (e: CancellationException) {
                    Log.d("notification", "SystemInfo polling cancelled")
                    break
                } catch (e: Exception) {
                    failures++
                    Log.w("notification", "SystemInfo poll failed ($failures)", e)
                    delay(if (failures < 5) 2_000L else 10_000L)
                }
            }
        }
    }
    fun stopListenSystemInfo(){
        try {
            streamingJob?.cancel()
        }catch (e: Exception){
            Log.d("notification", "Exception ${e}")
        }
    }
}