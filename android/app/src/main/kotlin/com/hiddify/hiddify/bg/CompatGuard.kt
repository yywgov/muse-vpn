package com.hiddify.hiddify.bg

// 穿云 1.9.0: keeps a 兼容内核 connection up, like the standard service does for its core.
//  · Watchdog: follows the core's state stream (CoreWatch, a blocking stream that is quiet while
//    all is well) and, when the core stops by itself while the user still wants the tunnel,
//    starts it again with the same backoff as the standard service (2 s, 5 s, 10 s, 30 s, 60 s),
//    each time first waiting (up to 30 s) for a usable network.
//  · Network: the system's default-network callback (DefaultNetworkListener) tells the core when
//    the network changed (Wi-Fi ↔ mobile data, or back after an outage), so connections made on
//    the old network are dropped at once instead of hanging until their own timeouts.
// Everything is event driven: no timer, no periodic check. Waiting for a network is a suspended
// coroutine woken by the network callback.
// Part of 穿云 (GPLv3).

import android.net.Network
import com.hiddify.core.api.v2.hcore.CoreClient
import com.hiddify.core.api.v2.hcore.MessageType
import com.hiddify.core.api.v2.hcore.StartRequest
import com.hiddify.hiddify.utils.GrpcClientProvider
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

class CompatGuard(
    /** The service is up (or coming up) and nobody asked it to stop. */
    private val wanted: () -> Boolean,
    /** Config of the running connection, for a restart. */
    private val launch: () -> CompatLaunch?,
    /** Every attempt failed: tell the user and end the connection. */
    private val giveUp: suspend () -> Unit,
) {
    private var watchdogJob: Job? = null

    @Volatile
    private var reconnectAttempts = 0

    @Volatile
    private var lastStartedAt = 0L

    // network state, written by the callback only
    @Volatile
    private var network: Network? = null

    @Volatile
    private var networkWaiter: CompletableDeferred<Unit>? = null
    private var listening = false

    // the callback's first answer only tells the current network; nothing changed yet
    @Volatile
    private var primed = false

    @OptIn(DelicateCoroutinesApi::class)
    fun start() {
        stop()
        lastStartedAt = System.currentTimeMillis()
        runBlocking { DefaultNetworkListener.start(this@CompatGuard) { onNetwork(it) } }
        listening = true
        watchdogJob = GlobalScope.launch(Dispatchers.IO) { watch() }
    }

    fun stop() {
        watchdogJob?.cancel()
        watchdogJob = null
        if (listening) {
            listening = false
            runBlocking { DefaultNetworkListener.stop(this@CompatGuard) }
        }
        network = null
        primed = false
        networkWaiter?.cancel()
        networkWaiter = null
    }

    /** Called by the system's network callback (default network changed, or lost: null). */
    internal fun onNetwork(next: Network?) {
        val previous = network
        network = next
        if (!primed) {
            primed = true
            if (next != null) networkWaiter?.complete(Unit)
            return
        }
        when (networkChange(previous, next)) {
            NetworkChange.LOST -> DisconnectLog.record("网络断开（兼容内核）")
            NetworkChange.SWITCHED, NetworkChange.RESTORED -> {
                if (next != null) networkWaiter?.complete(Unit)
                if (!wanted()) return
                val closed = try {
                    CompatCore.nativeNetworkChanged()
                } catch (_: Throwable) {
                    -1
                }
                DisconnectLog.record(
                    if (previous == null) "网络恢复（兼容内核），已重置 $closed 个连接"
                    else "网络切换（兼容内核），已重置 $closed 个连接",
                )
            }
            NetworkChange.NONE -> {}
        }
    }

    private suspend fun waitForNetwork(maxMillis: Long) {
        if (network != null) return
        val waiter = CompletableDeferred<Unit>()
        networkWaiter = waiter
        if (network == null) withTimeoutOrNull(maxMillis) { waiter.await() }
        networkWaiter = null
    }

    private suspend fun kotlinx.coroutines.CoroutineScope.watch() {
        var brokenStreams = 0
        while (isActive && wanted()) {
            val stopped = try {
                CoreWatch.awaitUnexpectedStop {
                    lastStartedAt = System.currentTimeMillis()
                    brokenStreams = 0
                }
            } catch (_: Exception) {
                // the stream broke: look again a few times, then give up watching (no endless retries)
                if (++brokenStreams > MAX_BROKEN_STREAMS) {
                    DisconnectLog.record("兼容内核状态流多次中断，停止看门狗")
                    return
                }
                delay(2_000)
                continue
            }
            if (!isActive || !wanted()) return
            if (stopped == null) {
                if (++brokenStreams > MAX_BROKEN_STREAMS) return
                delay(2_000)
                continue
            }
            // a long healthy run resets the backoff
            if (System.currentTimeMillis() - lastStartedAt > HEALTHY_MILLIS) reconnectAttempts = 0
            DisconnectLog.record("兼容内核意外停止: ${stopped.message_type} ${stopped.message}".trim())
            if (CompatState.stoppedByUser()) return
            var recovered = false
            while (!recovered && reconnectAttempts < BACKOFF_MILLIS.size) {
                val wait = BACKOFF_MILLIS[reconnectAttempts++]
                delay(wait)
                waitForNetwork(30_000)
                if (!isActive || !wanted() || CompatState.stoppedByUser()) return
                DisconnectLog.record("自动重连（兼容内核，第 $reconnectAttempts 次，等待 ${wait / 1000} 秒后）")
                recovered = restartCore()
            }
            if (!recovered) {
                DisconnectLog.record("自动重连 ${BACKOFF_MILLIS.size} 次都失败（兼容内核），已断开")
                giveUp()
                return
            }
            DisconnectLog.record("自动重连成功（兼容内核）")
        }
    }

    private fun restartCore(): Boolean {
        val l = launch() ?: return false
        return try {
            val res = GrpcClientProvider.grpcClient.create(CoreClient::class).Start()
                .executeBlocking(StartRequest(config_path = l.configPath, config_name = l.profileName))
            res.message_type == MessageType.EMPTY || res.message_type == MessageType.ALREADY_STARTED
        } catch (e: Exception) {
            DisconnectLog.record("自动重连失败（兼容内核）: ${e.message}")
            false
        }
    }

    enum class NetworkChange { NONE, LOST, RESTORED, SWITCHED }

    companion object {
        /** Same backoff as the standard service's watchdog. */
        val BACKOFF_MILLIS = longArrayOf(2_000, 5_000, 10_000, 30_000, 60_000)
        const val HEALTHY_MILLIS = 120_000L
        const val MAX_BROKEN_STREAMS = 5

        /** What a default-network callback means for the running core. */
        fun <T> networkChange(previous: T?, next: T?): NetworkChange = when {
            previous == next -> NetworkChange.NONE
            next == null -> NetworkChange.LOST
            previous == null -> NetworkChange.RESTORED
            else -> NetworkChange.SWITCHED
        }
    }
}
