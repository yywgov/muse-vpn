package com.hiddify.hiddify.bg

// 穿云 1.7.0: the 兼容内核 connection, run by CompatVpnService / CompatProxyService in the :compat
// process. Same contract with the app as the standard service (the IService binder, the
// notification, the close broadcast, the gRPC control service on the background port with the
// app's token); what differs: the VPN service builds the TUN itself and hands the descriptor to
// the core, and nothing here touches the app's preferences.
// Part of 穿云 (GPLv3).

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.IBinder
import android.os.ParcelFileDescriptor
import androidx.core.content.ContextCompat
import androidx.lifecycle.MutableLiveData
import com.hiddify.core.api.v2.hcore.CoreClient
import com.hiddify.core.api.v2.hcore.MessageType
import com.hiddify.core.api.v2.hcore.StartRequest
import com.hiddify.hiddify.R
import com.hiddify.hiddify.Settings
import com.hiddify.hiddify.constant.Action
import com.hiddify.hiddify.constant.Alert
import com.hiddify.hiddify.constant.PerAppProxyMode
import com.hiddify.hiddify.constant.Status
import com.hiddify.hiddify.utils.GrpcAuth
import com.hiddify.hiddify.utils.GrpcClientProvider
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class CompatService(
    private val service: Service,
    /** VPN mode: builds the TUN for this connection; null in proxy mode */
    private val openTun: ((CompatLaunch) -> ParcelFileDescriptor)?,
) {
    private val status = MutableLiveData(Status.Stopped)
    private val binder = ServiceBinder(status)
    private val notification = ServiceNotification(status, service)
    private var tun: ParcelFileDescriptor? = null
    private var coreSetUp = false
    private var receiverRegistered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Action.SERVICE_CLOSE) {
                DisconnectLog.record("断开（兼容内核）")
                CompatState.markStoppedByUser()
                CompatState.clearLaunch()
                stopService()
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    fun onStartCommand(intent: Intent?): Int {
        if (status.value != Status.Stopped) return Service.START_STICKY
        val launch = CompatLaunch.from(intent) ?: run {
            // Re-created by the system after it killed the :compat process (START_STICKY): bring
            // the connection back with the hand-over the last start saved, unless the user
            // disconnected since. The core starts here, as no app may be around to do it.
            val saved = if (CompatState.stoppedByUser()) null else CompatState.savedLaunch()
            if (saved == null) {
                service.stopSelf()
                return Service.START_NOT_STICKY
            }
            DisconnectLog.record("兼容内核进程曾被系统结束，服务已被系统重新拉起，自动恢复连接")
            saved.copy(startCore = true)
        }
        Settings.compatLaunch = launch
        GrpcAuth.override = launch.token
        status.value = Status.Starting
        if (!receiverRegistered) {
            ContextCompat.registerReceiver(
                service, receiver, IntentFilter(Action.SERVICE_CLOSE), ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            receiverRegistered = true
        }
        GlobalScope.launch(Dispatchers.IO) { start(launch) }
        // sticky: the system re-creates the service after killing the process (see above)
        return Service.START_STICKY
    }

    private suspend fun start(launch: CompatLaunch) {
        try {
            withContext(Dispatchers.Main) { notification.show(launch.profileName, R.string.status_starting) }
            if (launch.configPath.isBlank()) {
                stopAndAlert(Alert.EmptyConfiguration)
                return
            }
            val fd = openTun?.let { open ->
                val pfd = open(launch)
                tun = pfd
                pfd.fd
            } ?: 0
            val err = CompatCore.nativeSetup(
                launch.baseDir, launch.workingDir, launch.tempDir,
                "127.0.0.1:${launch.grpcPort}", launch.token, launch.debug,
            )
            coreSetUp = true
            if (err.isNotEmpty()) {
                stopAndAlert(Alert.CreateService, err)
                return
            }
            CompatCore.nativeSetTunFd(fd)
            if (launch.startCore) {
                // tile / boot / shortcut: the core starts with the last profile and settings it saved
                val res = GrpcClientProvider.grpcClient.create(CoreClient::class).Start()
                    .executeBlocking(StartRequest(config_path = launch.configPath, config_name = launch.profileName))
                if (res.message_type != MessageType.EMPTY && res.message_type != MessageType.ALREADY_STARTED) {
                    stopAndAlert(Alert.StartService, "${res.message_type} ${res.message}".trim())
                    return
                }
            }
            status.postValue(Status.Started)
            CompatState.saveToken(launch.token)
            CompatState.saveLaunch(launch)
            CompatState.markStarted(System.currentTimeMillis())
            DisconnectLog.record("VPN 服务已启动（兼容内核）")
            ChuanyunAlerts.cancel(ChuanyunAlerts.ID_DISCONNECTED)
            withContext(Dispatchers.Main) { notification.show(launch.profileName, R.string.status_started) }
            notification.start()
        } catch (e: Throwable) {
            // also UnsatisfiedLinkError when the library cannot load
            stopAndAlert(Alert.StartService, e.message ?: e.javaClass.simpleName)
        }
    }

    private suspend fun stopAndAlert(type: Alert, message: String? = null) {
        DisconnectLog.record("启动失败（兼容内核）: ${type.name} ${message ?: ""}".trim())
        // no retry loop: a failed start is not brought back by the system
        CompatState.clearLaunch()
        releaseCore()
        withContext(Dispatchers.Main) {
            unregisterReceiver()
            notification.close()
            binder.broadcast { it.onServiceAlert(type.ordinal, message) }
            status.value = Status.Stopped
            service.stopSelf()
        }
    }

    /** Stops the core (if it was set up) and closes this connection's TUN. */
    private fun releaseCore() {
        if (coreSetUp) {
            try {
                CompatCore.nativeStop()
            } catch (_: Throwable) {
            }
            coreSetUp = false
        }
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
        CompatState.clearStarted()
    }

    private fun unregisterReceiver() {
        if (receiverRegistered) {
            try {
                service.unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    fun stopService() {
        if (status.value == Status.Stopped || status.value == Status.Stopping) return
        status.value = Status.Stopping
        unregisterReceiver()
        notification.close()
        GlobalScope.launch(Dispatchers.IO) {
            releaseCore()
            withContext(Dispatchers.Main) {
                status.value = Status.Stopped
                service.stopSelf()
            }
        }
    }

    fun onBind(intent: Intent): IBinder = binder

    fun onRevoke() {
        DisconnectLog.record("VPN 权限被收回（兼容内核）")
        CompatState.markStoppedByUser()
        CompatState.clearLaunch()
        stopService()
    }

    fun onDestroy() {
        if (status.value == Status.Started || status.value == Status.Starting) {
            DisconnectLog.record("服务被系统销毁（兼容内核，未经用户断开）")
            releaseCore()
        }
        unregisterReceiver()
        binder.close()
    }

    companion object {
        /** Address of the TUN this VPN service builds (the core answers DNS sent anywhere on port 53). */
        const val TUN_ADDRESS_V4 = "172.19.0.1"
        const val TUN_DNS_V4 = "172.19.0.2"
        const val TUN_ADDRESS_V6 = "fdfe:dcba:9876::1"
        const val TUN_MTU = 9000

        /**
         * Which apps the TUN covers: (allowed, disallowed); Android takes one list or the other.
         * The app itself is always outside, so the core's own connections never loop back in.
         */
        fun appLists(enabled: Boolean, mode: String, list: List<String>, self: String): Pair<List<String>, List<String>> {
            val apps = list.filter { it.isNotBlank() && it != self }.distinct()
            if (enabled && mode == PerAppProxyMode.INCLUDE && apps.isNotEmpty()) return apps to emptyList()
            val excluded = if (enabled && mode == PerAppProxyMode.EXCLUDE) apps else emptyList()
            return emptyList<String>() to (excluded + self)
        }
    }
}
