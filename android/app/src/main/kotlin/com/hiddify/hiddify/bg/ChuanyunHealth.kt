package com.hiddify.hiddify.bg

// 穿云 1.13.0 - 本地崩溃自检 / 安全模式 / 被其他 VPN 顶掉.
// Everything stays in the app's private storage (filesDir/diagnostics): nothing is uploaded and
// nothing is read by another app. Files:
//   crash.log / crash.1.log  uncaught Kotlin exceptions and failed service starts (≤ 128 KB each)
//   crash.unseen             one line about the newest problem, until 首页「上次异常」 is closed
//   start_failures           consecutive failed starts (a successful start resets it)
//   safe_mode                present = 安全模式 (2 failed starts in a row)
//   revoked                  when another VPN app took over (onRevoke), until 首页 closes the hint
// No timer, no polling: written when something happens, read when 首页 asks.
//
// Rule (1.11.1 / 1.12.1 lessons): nothing here may touch a Context while a Service or the widget is
// being constructed. The widget only reads [safeModeCached], loaded once in Application.onCreate.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.util.Log
import com.hiddify.hiddify.Application
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object ChuanyunHealth {
    private const val TAG = "A/ChuanyunHealth"
    const val MAX_BYTES = 128 * 1024L

    /** Two failed starts in a row → 安全模式. */
    const val SAFE_MODE_AFTER = 2

    /** The same failure reported by the service and by the app within this window counts once. */
    const val SAME_FAILURE_MS = 5_000L

    /** 安全模式, as loaded in Application.onCreate (no file read while a service is constructed). */
    @Volatile
    var safeModeCached = false
        private set

    @Volatile
    private var lastFailureAt = 0L

    private val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS Z", Locale.US)

    private fun dir(): File = File(Application.application.filesDir, "diagnostics").apply { mkdirs() }
    private fun f(name: String) = File(dir(), name)

    /** Pure: the next consecutive-failure count. */
    fun nextFailures(count: Int, lastAt: Long, now: Long): Int =
        if (lastAt > 0 && now - lastAt in 0 until SAME_FAILURE_MS) count else count + 1

    /** Pure: is that many failures in a row enough for 安全模式? */
    fun entersSafeMode(failures: Int): Boolean = failures >= SAFE_MODE_AFTER

    /** Application.onCreate (every process): crash handler + cached 安全模式. Never throws. */
    fun install(process: String) {
        try {
            safeModeCached = f("safe_mode").exists()
        } catch (_: Throwable) {
        }
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            try {
                recordCrash("$process 进程未捕获异常（线程 ${thread.name}）", e)
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, e)
        }
    }

    @Synchronized
    private fun append(text: String) {
        try {
            val log = f("crash.log")
            if (log.length() > MAX_BYTES) {
                f("crash.1.log").delete()
                log.renameTo(f("crash.1.log"))
            }
            f("crash.log").appendText("${format.format(Date())}  $text\n")
        } catch (e: Throwable) {
            Log.w(TAG, "could not write the crash log", e)
        }
    }

    private fun markUnseen(summary: String) {
        try {
            f("crash.unseen").writeText("${System.currentTimeMillis()}\n${summary.take(300)}")
        } catch (_: Throwable) {
        }
    }

    /** An uncaught exception: stack trace (cut to 16 KB) into the log, 首页 shows 「上次异常」. */
    fun recordCrash(where: String, e: Throwable) {
        val sw = StringWriter()
        e.printStackTrace(PrintWriter(sw))
        append("$where\n${sw.toString().take(16 * 1024)}")
        markUnseen("$where：${e.javaClass.simpleName}${e.message?.let { "：$it" } ?: ""}")
    }

    /** A start of the VPN service failed (service or app). Counts towards 安全模式. */
    @Synchronized
    fun startFailed(reason: String) {
        try {
            val now = System.currentTimeMillis()
            val count = nextFailures(failures(), lastFailureAt, now)
            lastFailureAt = now
            f("start_failures").writeText("$count")
            append("启动失败（连续第 $count 次）：$reason")
            markUnseen("启动失败：$reason")
            if (entersSafeMode(count) && !f("safe_mode").exists()) {
                f("safe_mode").writeText("$now")
                safeModeCached = true
                append("连续 $count 次启动失败，下次以安全模式启动（停用小组件更新与自定义规则）")
            }
        } catch (e: Throwable) {
            Log.w(TAG, "start failed bookkeeping", e)
        }
    }

    /** The core really runs: the failure streak ends (安全模式 stays until the user leaves it). */
    @Synchronized
    fun startSucceeded() {
        try {
            lastFailureAt = 0L
            f("start_failures").delete()
        } catch (_: Throwable) {
        }
    }

    fun failures(): Int = try {
        f("start_failures").takeIf { it.exists() }?.readText()?.trim()?.toIntOrNull() ?: 0
    } catch (_: Throwable) {
        0
    }

    @Synchronized
    fun exitSafeMode() {
        try {
            f("safe_mode").delete()
            f("start_failures").delete()
            lastFailureAt = 0L
            safeModeCached = false
            append("用户退出安全模式")
        } catch (_: Throwable) {
        }
    }

    /** onRevoke: another VPN app (or the system) took the VPN away. Never reconnects by itself. */
    fun markRevoked() {
        try {
            f("revoked").writeText("${System.currentTimeMillis()}")
        } catch (_: Throwable) {
        }
        try {
            ChuanyunAlerts.show(
                Application.application,
                ChuanyunAlerts.ID_REVOKED,
                "穿云已被其他 VPN 断开",
                "另一个 VPN 应用开启后，系统收回了穿云的 VPN。穿云不会自动重连，需要时请回到穿云点「连接」。",
            )
        } catch (_: Throwable) {
        }
    }

    fun dismissRevoked() {
        runCatching { f("revoked").delete() }
        ChuanyunAlerts.cancel(ChuanyunAlerts.ID_REVOKED)
    }

    fun dismissCrash() {
        runCatching { f("crash.unseen").delete() }
    }

    /** For 首页: what to show. */
    fun state(): Map<String, Any?> {
        val unseen = try {
            f("crash.unseen").takeIf { it.exists() }?.readText()?.split('\n', limit = 2)
        } catch (_: Throwable) {
            null
        }
        val revoked = try {
            f("revoked").takeIf { it.exists() }?.readText()?.trim()?.toLongOrNull()
        } catch (_: Throwable) {
            null
        }
        val safe = try {
            f("safe_mode").exists()
        } catch (_: Throwable) {
            false
        }
        safeModeCached = safe
        return mapOf(
            "crashAt" to unseen?.getOrNull(0)?.toLongOrNull(),
            "crash" to unseen?.getOrNull(1),
            "safeMode" to safe,
            "failures" to failures(),
            "revokedAt" to revoked,
        )
    }

    /** The crash log (older part first), for 「复制日志」. */
    @Synchronized
    fun read(): String = buildString {
        try {
            for (name in listOf("crash.1.log", "crash.log")) {
                val file = f(name)
                if (file.exists()) append(file.readText())
            }
        } catch (e: Throwable) {
            append("（读取失败：${e.message}）\n")
        }
    }
}
