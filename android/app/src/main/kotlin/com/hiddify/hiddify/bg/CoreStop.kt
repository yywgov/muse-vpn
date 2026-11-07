package com.hiddify.hiddify.bg

// 穿云 1.13.0 - 停止内核有上限，且从不占用主线程。
//
// e2e #16: two in-app disconnects each froze the whole app for 120 s (Stopping → Stopped). The
// service called Mobile.close(4) on the main thread, which since Flutter 3.29 is also the Dart UI
// thread, so the screen, the method channels and every Dart timer stood still until the core came
// back; sing-box closes each of its parts with a 10 s timeout (12 parts ≈ 120 s). 穿云's process was
// in front the whole time and never frozen by the system (logcat: only other apps were frozen).
//
// Now: the core is closed on its own thread; the caller waits at most [TIMEOUT_MILLIS]. Past that
// the service reports 已停止 anyway, the loopback port 17079 is released by shutting down the
// sockets bound to it in this process (the next connect sees it closed), and the late close keeps
// running in the background. A new setup waits for that close first ([awaitIdle]) so the old close
// can never take the new connection's gRPC server down with it.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import android.util.Log
import com.hiddify.core.mobile.Mobile
import java.io.File
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object CoreStop {
    private const val TAG = "A/CoreStop"

    /** How long a stop may take before 穿云 reports 已停止 and releases the port itself. */
    const val TIMEOUT_MILLIS = 10_000L

    /** The background core's gRPC port (mode 4). */
    const val PORT = 17079

    /** A new setup waits at most this long for a late close (sing-box gives up after ~120 s). */
    const val IDLE_WAIT_MILLIS = 150_000L

    private val lock = Any()

    @Volatile
    private var inFlight: CountDownLatch? = null

    /** Whether a close of the background core is still running. */
    fun busy(): Boolean = (inFlight?.count ?: 0L) > 0L

    /**
     * Closes the background core (mode 4) on its own thread and waits at most [timeoutMillis].
     * Returns true when the close finished in time. A close already running is waited on, never
     * started twice. Never throws. Must not be called on the main thread.
     */
    fun closeWithin(reason: String, timeoutMillis: Long = TIMEOUT_MILLIS): Boolean =
        runWithin("后台内核", reason, timeoutMillis, releasePort = true) { Mobile.close(4L) }

    /**
     * Runs [close] on its own thread and waits at most [timeoutMillis]; true when it finished.
     * On a timeout: one line in the disconnect log, the port released when [releasePort], and
     * another line once the late close is done. Never throws.
     */
    fun runWithin(
        what: String,
        reason: String,
        timeoutMillis: Long = TIMEOUT_MILLIS,
        releasePort: Boolean = false,
        close: () -> Unit,
    ): Boolean {
        val startedAt = SystemClock.elapsedRealtime()
        val latch: CountDownLatch = synchronized(lock) {
            val running = inFlight
            if (running != null && running.count > 0L) {
                running
            } else {
                val fresh = CountDownLatch(1)
                inFlight = fresh
                val thread = Thread({
                    try {
                        close()
                    } catch (e: Throwable) {
                        Log.w(TAG, "close $what: ${e.javaClass.simpleName}: ${e.message}")
                    } finally {
                        fresh.countDown()
                        val took = SystemClock.elapsedRealtime() - startedAt
                        if (took > timeoutMillis) {
                            DisconnectLog.record("$what 在 ${took / 1000} 秒后才退出（$reason）")
                        }
                    }
                }, "chuanyun-core-close")
                thread.isDaemon = true
                thread.start()
                fresh
            }
        }
        val done = try {
            latch.await(timeoutMillis, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            false
        }
        if (!done) {
            val released = if (releasePort) forceReleasePort(PORT) else 0
            DisconnectLog.record(
                "停止$what 超过 ${timeoutMillis / 1000} 秒仍未结束（$reason），已按已停止处理" +
                    (if (releasePort) "，强制释放端口 $PORT（$released 个连接）" else "") +
                    "，内核在后台继续退出",
            )
        }
        return done
    }

    /** Before the background core is set up again: wait for a late close (bounded). */
    fun awaitIdle(maxMillis: Long = IDLE_WAIT_MILLIS): Boolean {
        val latch = inFlight ?: return true
        if (latch.count == 0L) return true
        DisconnectLog.record("等待上一次的内核退出后再连接")
        return try {
            latch.await(maxMillis, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            false
        }
    }

    /**
     * Shuts down every socket of this process bound to 127.0.0.1:[port] (the listener and its
     * accepted connections; a client's own end has another local port). Afterwards a connect to the
     * port is refused, which is what the app and the next start check. Returns how many it shut.
     * Never throws.
     */
    fun forceReleasePort(port: Int): Int {
        var shut = 0
        val names: Array<String> = (try {
            File("/proc/self/fd").list()
        } catch (_: Throwable) {
            null
        }) ?: return 0
        for (name in names) {
            val fd = name.toIntOrNull() ?: continue
            val target = try {
                Os.readlink("/proc/self/fd/$name")
            } catch (_: Throwable) {
                continue
            }
            if (!target.startsWith("socket:")) continue
            var dup: ParcelFileDescriptor? = null
            try {
                dup = ParcelFileDescriptor.fromFd(fd)
                val local = Os.getsockname(dup.fileDescriptor) as? InetSocketAddress
                if (local != null && local.port == port && local.address?.isLoopbackAddress == true) {
                    Os.shutdown(dup.fileDescriptor, OsConstants.SHUT_RDWR)
                    shut++
                }
            } catch (_: Throwable) {
            } finally {
                try {
                    dup?.close()
                } catch (_: Throwable) {
                }
            }
        }
        Log.w(TAG, "released port $port: $shut socket(s)")
        return shut
    }
}
