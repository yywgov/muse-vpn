package com.hiddify.hiddify.bg

// 穿云: why the tunnel stopped or recovered, one line per event, kept in the app's private
// storage (filesDir/diagnostics/disconnects.log, ~256 KB with one rotated copy). Read only by
// 设置 › 关于 › 导出诊断. Never leaves the phone unless the user shares that export.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.util.Log
import com.hiddify.hiddify.Application
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object DisconnectLog {
    private const val TAG = "A/DisconnectLog"
    private const val MAX_BYTES = 256 * 1024L

    private val dir: File
        get() = File(Application.application.filesDir, "diagnostics").apply { mkdirs() }

    val file: File
        get() = File(dir, "disconnects.log")

    private val previous: File
        get() = File(dir, "disconnects.1.log")

    private val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS Z", Locale.US)

    @Synchronized
    fun record(reason: String) {
        Log.i(TAG, reason)
        try {
            val f = file
            if (f.length() > MAX_BYTES) {
                previous.delete()
                f.renameTo(previous)
            }
            file.appendText("${format.format(Date())}  ${reason.replace('\n', ' ')}\n")
        } catch (e: Exception) {
            Log.w(TAG, "could not write the disconnect log", e)
        }
    }

    /** The older rotated part first, then the current one. */
    @Synchronized
    fun read(): String = buildString {
        try {
            if (previous.exists()) append(previous.readText())
            if (file.exists()) append(file.readText())
        } catch (e: Exception) {
            append("(读取失败: ${e.message})\n")
        }
    }

    private fun stderrFiles(): List<File> {
        val working = try {
            com.hiddify.hiddify.Settings.workingDir
        } catch (_: Exception) {
            ""
        }
        if (working.isBlank()) return emptyList()
        return listOf("stderr.log", "stderr2.log", "data/stderr3.log", "data/stderr4.log").map { File(working, it) }
    }

    /**
     * The core sends Go crash traces to stderr files that are truncated each time it is set up,
     * so a crash would be lost on the next start. Keep the previous content as *.prev and note
     * a panic in the disconnect log. Called right before the core is set up.
     */
    @Synchronized
    fun preserveCrashTraces() {
        for (f in stderrFiles()) {
            try {
                if (!f.exists() || f.length() == 0L) continue
                val text = f.readText().takeLast(64 * 1024)
                val prev = File(f.parentFile, f.name + ".prev")
                // already kept (the file is not truncated until the core redirects to it again)
                if (prev.exists() && prev.readText() == text) continue
                val panic = Regex("(panic|fatal error):[^\n]*").find(text)?.value
                if (panic != null) record("上次内核崩溃（${f.name}）：${panic.take(300)}")
                prev.writeText(text)
            } catch (_: Exception) {
            }
        }
    }

    /** The current and previous stderr files of the core (tails), for the diagnostics export. */
    fun readCrashTraces(): String = buildString {
        for (f in stderrFiles().flatMap { listOf(File(it.parentFile, it.name + ".prev"), it) }) {
            try {
                if (!f.exists() || f.length() == 0L) continue
                append("----- ${f.name} -----\n")
                append(f.readText().takeLast(32 * 1024))
                append("\n")
            } catch (_: Exception) {
            }
        }
    }
}
