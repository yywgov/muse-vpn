package com.hiddify.hiddify.bg

// 穿云 1.7.0: which of the app's processes this is. 兼容内核 runs in its own process (:compat) so
// its Go runtime never meets the standard core's in one process; that process skips everything
// the app process sets up for the standard core.
// Part of 穿云 (GPLv3).

import android.app.Application
import android.content.SharedPreferences
import android.os.Build
import java.io.File

object ChuanyunProcess {
    const val COMPAT_SUFFIX = ":compat"

    val name: String by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            Application.getProcessName()
        } else {
            try {
                File("/proc/self/cmdline").readText().trimEnd('\u0000').substringBefore('\u0000')
            } catch (_: Exception) {
                ""
            }
        }
    }

    /** This is the 兼容内核 process. */
    val isCompat: Boolean by lazy { isCompatName(name) }

    fun isCompatName(processName: String): Boolean = processName.endsWith(COMPAT_SUFFIX)
}

/** Editor that drops every change (preferences are read-only in the :compat process). */
object NoopEditor : SharedPreferences.Editor {
    override fun putString(key: String?, value: String?) = this
    override fun putStringSet(key: String?, values: MutableSet<String>?) = this
    override fun putInt(key: String?, value: Int) = this
    override fun putLong(key: String?, value: Long) = this
    override fun putFloat(key: String?, value: Float) = this
    override fun putBoolean(key: String?, value: Boolean) = this
    override fun remove(key: String?) = this
    override fun clear() = this
    override fun commit() = true
    override fun apply() {}
}
