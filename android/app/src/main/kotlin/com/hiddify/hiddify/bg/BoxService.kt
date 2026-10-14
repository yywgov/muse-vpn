package com.hiddify.hiddify.bg

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.MutableLiveData
import com.hiddify.hiddify.Application
import com.hiddify.hiddify.R
import com.hiddify.hiddify.Settings
import com.hiddify.hiddify.constant.Action
import com.hiddify.hiddify.constant.Alert
import com.hiddify.hiddify.constant.Status
import com.hiddify.core.mobile.SetupOptions

import go.Seq
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.mobile.Mobile


import com.hiddify.core.libbox.CommandServer
import com.hiddify.core.libbox.CommandServerHandler
import com.hiddify.core.libbox.Notification
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.libbox.SystemProxyStatus
import com.hiddify.hiddify.BuildConfig
import com.hiddify.hiddify.MainActivity
import com.hiddify.hiddify.constant.Bugs
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.io.File

class BoxService(
        private val service: Service,
        private val platformInterface: PlatformInterface
)  {

    companion object {
        private const val TAG = "A/BoxService"

        private var initializeOnce = false
        private lateinit var workingDir: File
        private fun initialize() {
            System.setProperty("GODEBUG", "efence=1,stacktraceback=2");
            System.setProperty("GOGC", "off");
            if (initializeOnce) return
            val baseDir = Application.application.filesDir

            baseDir.mkdirs()
            workingDir = Application.application.getExternalFilesDir(null) ?: return
            workingDir.mkdirs()
            val tempDir = Application.application.cacheDir
            tempDir.mkdirs()
            Log.d(TAG, "base dir: ${baseDir.path}")
            Log.d(TAG, "working dir: ${workingDir.path}")
            Log.d(TAG, "temp dir: ${tempDir.path}")

//
            //Mobile.setup(baseDir.path, workingDir.path, tempDir.path,  2L ,"127.0.0.1:{Setting}","",false,this)
//            Libbox.setup(baseDir.path, workingDir.path, tempDir.path, false)

//            Libbox.setup(SetupOptions().also {
//                it.basePath = baseDir.path
//                it.workingPath = workingDir.path
//                it.tempPath = tempDir.path
//                it.fixAndroidStack = Bugs.fixAndroidStack
//
//            })
            DisconnectLog.preserveCrashTraces()
            Libbox.redirectStderr(File(Settings.workingDir, "stderr.log").path)
            initializeOnce = true
            return
        }

        fun start() {
            val intent = runBlocking {
                withContext(Dispatchers.IO) {
                    Intent(Application.application, Settings.serviceClass())
                }
            }
            ContextCompat.startForegroundService(Application.application, intent)
        }

        /** Why the next stop happens, for the disconnect log (set by whoever asks for it). */
        @Volatile
        var pendingStopReason: String? = null

        fun stop(reason: String? = null) {
            if (reason != null) pendingStopReason = reason
            Application.application.sendBroadcast(
                    Intent(Action.SERVICE_CLOSE).setPackage(
                            Application.application.packageName
                    )
            )
        }


    }

    var fileDescriptor: ParcelFileDescriptor? = null

    private val status = MutableLiveData(Status.Stopped)
    private val binder = ServiceBinder(status)
    private val notification = ServiceNotification(status, service)
//    private var boxService: BoxService? = null
    private var commandServer: CommandServer? = null
    private var receiverRegistered = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Action.SERVICE_CLOSE -> {
                    val reason = pendingStopReason ?: "用户在通知栏点了断开"
                    pendingStopReason = null
                    DisconnectLog.record(reason)
                    stopService()
                }

                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        serviceUpdateIdleMode()
                    }
                }
            }
        }
    }
    


    private var activeProfileName = ""
    private suspend fun startService() {
        try {
            status.postValue(Status.Starting)
            Log.d(TAG, "starting service")
            withContext(Dispatchers.Main) {
                notification.show(activeProfileName, R.string.status_starting)
            }

            val selectedConfigPath = Settings.activeConfigPath
            if (selectedConfigPath.isBlank()) {
                stopAndAlert(Alert.EmptyConfiguration)
                return
            }

            activeProfileName = Settings.activeProfileName

            withContext(Dispatchers.Main) {
                notification.show(activeProfileName, R.string.status_starting)
                binder.broadcast {
                    it.onServiceResetLogs(listOf())
                }
            }

            DefaultNetworkMonitor.start()
            Libbox.setMemoryLimit(!Settings.disableMemoryLimit)
            DisconnectLog.preserveCrashTraces()
            val newService = try {
                Mobile.setup(
                    SetupOptions().also {
                        it.basePath = Settings.baseDir
                        it.workingDir = Settings.workingDir
                        it.tempDir = Settings.tempDir
                        it.fixAndroidStack = com.hiddify.hiddify.bg.Bugs.fixAndroidStack
                        it.mode=4L//mode.toLong()
                        it.listen= "127.0.0.1:${Settings.grpcServiceModePort}"
                        it.secret = com.hiddify.hiddify.utils.GrpcAuth.token
                        it.debug = Settings.debugMode
                    },platformInterface)


//                Libbox.newService(content,platformInterface)

            } catch (e: Exception) {
                stopAndAlert(Alert.CreateService, e.message)
                return
            }
            status.postValue(Status.Started)
            DisconnectLog.record("VPN 服务已启动")
            // 穿云: real connect time for the 首页 timer (survives app/engine restarts)
            Settings.connectedSince = System.currentTimeMillis()
            ChuanyunAlerts.cancel(ChuanyunAlerts.ID_DISCONNECTED)

            if (Settings.startCoreAfterStartingService){
                Mobile.start("","")
                }
//            if (delayStart) {
//                delay(1000L)
//            }

//            newService.start()
//            boxService = newService
//            commandServer?.setService(boxService)


            withContext(Dispatchers.Main) {
                notification.show(activeProfileName, R.string.status_started)
            }
            notification.start()
            startWatchdog()
        } catch (e: Exception) {
            stopAndAlert(Alert.StartService, e.message)
            return
        }
    }

    // ------------------------------------------------------------------------------------
    // 穿云: watchdog — when the core stops by itself while the user still wants the tunnel,
    // start it again with backoff (2 s, 5 s, 10 s, 30 s, 60 s), waiting for a usable network.
    // A stop the user asked for never reaches here (normal stops carry an EMPTY message type).

    private var watchdogJob: Job? = null
    @Volatile
    private var reconnectAttempts = 0
    @Volatile
    private var lastStartedAt = 0L
    private val backoffMillis = longArrayOf(2_000, 5_000, 10_000, 30_000, 60_000)

    @OptIn(DelicateCoroutinesApi::class)
    private fun startWatchdog() {
        watchdogJob?.cancel()
        watchdogJob = GlobalScope.launch(Dispatchers.IO) {
            while (isActive && serviceWanted()) {
                val stopped = try {
                    CoreWatch.awaitUnexpectedStop {
                        lastStartedAt = System.currentTimeMillis()
                    }
                } catch (e: Exception) {
                    // the stream broke (e.g. core restarting); look again shortly
                    null
                }
                if (!isActive || !serviceWanted()) break
                if (stopped == null) {
                    delay(2_000)
                    continue
                }
                // a long healthy run resets the backoff
                if (System.currentTimeMillis() - lastStartedAt > 120_000) reconnectAttempts = 0
                DisconnectLog.record("内核意外停止: ${stopped.message_type} ${stopped.message}".trim())
                if (!Settings.startedByUser) break
                var recovered = false
                while (!recovered && reconnectAttempts < backoffMillis.size) {
                    val wait = backoffMillis[reconnectAttempts++]
                    delay(wait)
                    waitForNetwork(30_000)
                    if (!isActive || !serviceWanted() || !Settings.startedByUser) return@launch
                    DisconnectLog.record("自动重连（第 $reconnectAttempts 次，等待 ${wait / 1000} 秒后）")
                    recovered = try {
                        Mobile.start(Settings.activeConfigPath, "")
                        true
                    } catch (e: Exception) {
                        DisconnectLog.record("自动重连失败: ${e.message}")
                        false
                    }
                }
                if (!recovered) {
                    DisconnectLog.record("自动重连 ${backoffMillis.size} 次都失败，已断开")
                    // 穿云 1.1: tell the user once; otherwise the tunnel is silently gone
                    ChuanyunAlerts.show(
                        service,
                        ChuanyunAlerts.ID_DISCONNECTED,
                        "穿云已断开",
                        "自动重连 ${backoffMillis.size} 次都没有成功，点这里打开穿云重新连接",
                    )
                    withContext(Dispatchers.Main) { stopService() }
                    break
                }
                DisconnectLog.record("自动重连成功")
            }
        }
    }

    /** The service is up (or coming up) and nobody asked it to stop. */
    private fun serviceWanted(): Boolean = status.value == Status.Started || status.value == Status.Starting

    private fun stopWatchdog() {
        watchdogJob?.cancel()
        watchdogJob = null
    }

    /** Whether a non-VPN network with internet access is up right now. */
    private fun hasUsableNetwork(): Boolean {
        val cm = Application.connectivity
        @Suppress("DEPRECATION")
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                !caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN)
            ) return true
        }
        return false
    }

    private suspend fun waitForNetwork(maxMillis: Long) {
        val until = System.currentTimeMillis() + maxMillis
        while (System.currentTimeMillis() < until && !hasUsableNetwork()) {
            delay(1_000)
        }
    }

    fun serviceReload() {
        runBlocking {
            serviceReload0()
        }
    }

    suspend fun serviceReload0() {
        notification.close()
        status.postValue(Status.Starting)

        val pfd = fileDescriptor
        if (pfd != null) {
            pfd.close()
            fileDescriptor = null
        }
        
//        boxService?.apply {
//            runCatching {
//                close()
//            }.onFailure {
//                writeLog("service: error when closing: $it")
//            }
//            Seq.destroyRef(refnum)
//        }
        Mobile.stop()
//        boxService = null
        
            startService()
        
    }

    fun getSystemProxyStatus(): SystemProxyStatus {
        val status = SystemProxyStatus()
        if (service is VPNService) {
            status.available = service.systemProxyAvailable
            status.enabled = service.systemProxyEnabled
        }
        return status
    }

    fun setSystemProxyEnabled(isEnabled: Boolean) {
        serviceReload()
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun serviceUpdateIdleMode() {
        if (Application.powerManager.isDeviceIdleMode) {
//            boxService?.pause()
            //Mobile.pause()
        } else {
            Mobile.wake()
//            boxService?.wake()
        }
    }

    private fun stopService() {
        if (status.value == Status.Stopped) return
        status.value = Status.Stopping
        stopWatchdog()
        if (receiverRegistered) {
            service.unregisterReceiver(receiver)
            receiverRegistered = false
        }
        notification.close()
        GlobalScope.launch(Dispatchers.IO) {
            val pfd = fileDescriptor
            if (pfd != null) {
                pfd.close()
                fileDescriptor = null
            }
//            commandServer?.setService(null)
//            boxService?.apply {
//                runCatching {
//                    close()
//                }.onFailure {
//                    writeLog("service: error when closing: $it")
//                }
//                //Seq.destroyRef(refnum)
//            }

//            boxService = null
//            Libbox.registerLocalDNSTransport(null)
            DefaultNetworkMonitor.stop()

//            commandServer?.apply {
//                close()
//                Seq.destroyRef(refnum)
//            }
//            commandServer = null
            Settings.startedByUser = false
            withContext(Dispatchers.Main) {
                Mobile.close(4L)
                Settings.connectedSince = 0L
                status.value = Status.Stopped
                service.stopSelf()
            }
            notification.close()
        }
    }

    private suspend fun stopAndAlert(type: Alert, message: String? = null) {
        DisconnectLog.record("启动失败: ${type.name} ${message ?: ""}".trim())
        stopWatchdog()
        Settings.startedByUser = false
        withContext(Dispatchers.Main) {
            if (receiverRegistered) {
                service.unregisterReceiver(receiver)
                receiverRegistered = false
            }
            notification.close()
            binder.broadcast { callback ->
                callback.onServiceAlert(type.ordinal, message)
            }
            Settings.connectedSince = 0L
            status.value = Status.Stopped
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    @Suppress("SameReturnValue")
    internal fun onStartCommand(intent: Intent?): Int {
        if (status.value != Status.Stopped) return Service.START_STICKY
        if (intent == null) {
            // 穿云: the system re-created the service after killing the process (START_STICKY).
            // Bring the tunnel back only if the user still wants it; the core is started here
            // because no app UI is around to do it.
            if (!Settings.startedByUser || Settings.activeConfigPath.isBlank()) {
                service.stopSelf()
                return Service.START_NOT_STICKY
            }
            DisconnectLog.record("穿云进程曾被系统结束，服务已被系统重新拉起，自动恢复连接")
            Settings.startCoreAfterStartingService = true
        }
        status.value = Status.Starting
        pendingStopReason = null

        if (!receiverRegistered) {
            ContextCompat.registerReceiver(service, receiver, IntentFilter().apply {
                addAction(Action.SERVICE_CLOSE)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
                }
            }, ContextCompat.RECEIVER_NOT_EXPORTED)
            receiverRegistered = true
        }

        GlobalScope.launch(Dispatchers.IO) {
            Settings.startedByUser = true
            initialize()
//            try {
//                startCommandServer()
//            } catch (e: Exception) {
//                stopAndAlert(Alert.StartCommandServer, e.message)
//                return@launch
//            }
            startService()
        }
        // 穿云: sticky, so the system restarts the tunnel after killing the process
        return Service.START_STICKY
    }

    fun onBind(intent: Intent): IBinder {
        return binder
    }

    fun onDestroy() {
        if (status.value == Status.Started || status.value == Status.Starting) {
            DisconnectLog.record("服务被系统销毁（未经用户断开）")
        }
        stopWatchdog()
        binder.close()
    }

    fun onRevoke() {
        DisconnectLog.record("VPN 权限被收回（其他 VPN 应用启动，或系统收回了权限）")
        stopService()
    }

    internal fun sendNotification(notification: Notification) {
        return
        val builder =
            NotificationCompat.Builder(service, notification.identifier).setShowWhen(false)
                .setContentTitle(notification.title).setContentText(notification.body)
                .setOnlyAlertOnce(true).setSmallIcon(R.drawable.ic_launcher_foreground)
                .setCategory(NotificationCompat.CATEGORY_EVENT)
                .setPriority(NotificationCompat.PRIORITY_HIGH).setAutoCancel(true)
        if (!notification.subtitle.isNullOrBlank()) {
            builder.setContentInfo(notification.subtitle)
        }
        if (!notification.openURL.isNullOrBlank()) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    service,
                    0,
                    Intent(
                        service,
                        MainActivity::class.java,
                    ).apply {
                        setAction(Action.SERVICE).setData(Uri.parse(notification.openURL))
                        setFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    },
                    ServiceNotification.flags,
                ),
            )
        }
        GlobalScope.launch(Dispatchers.Main) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Application.notification.createNotificationChannel(
                    NotificationChannel(
                        notification.identifier,
                        notification.typeName,
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                )
            }
            Application.notification.notify(notification.identifier, notification.typeID, builder.build())
        }
    }

    internal fun cancelNotification(identifier: String, typeID: Int) {
        GlobalScope.launch(Dispatchers.Main) {
            Application.notification.cancel(identifier, typeID)
        }
    }

     fun writeDebugMessage(message: String?) {
        Log.d("BoxService", message!!)
        binder.broadcast {
            it.onServiceWriteLog(message)
        }
    }

}