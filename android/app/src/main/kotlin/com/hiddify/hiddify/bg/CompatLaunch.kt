package com.hiddify.hiddify.bg

// 穿云 1.7.0: everything the 兼容内核 process needs for one connection, handed over in the start
// intent by the app process. That process never reads stale preferences or writes any; the gRPC
// token is the app process's own, so the app talks to either core with the same token.
// Part of 穿云 (GPLv3).

import android.content.Intent
import com.hiddify.hiddify.Application
import com.hiddify.hiddify.Settings
import com.hiddify.hiddify.utils.GrpcAuth
import java.io.File

data class CompatLaunch(
    val token: String,
    val grpcPort: Int,
    val configPath: String,
    val profileName: String,
    val baseDir: String,
    val workingDir: String,
    val tempDir: String,
    val debug: Boolean,
    /** start the core right away (tile / boot / shortcut: no app around to do it) */
    val startCore: Boolean,
    val ipv6: Boolean,
    val perAppEnabled: Boolean,
    val perAppMode: String,
    val perAppList: List<String>,
    val hideNotification: Boolean,
    val notifyStopButton: Boolean,
) {
    fun putInto(intent: Intent) {
        intent.putExtra(K_TOKEN, token)
            .putExtra(K_PORT, grpcPort)
            .putExtra(K_PATH, configPath)
            .putExtra(K_NAME, profileName)
            .putExtra(K_BASE, baseDir)
            .putExtra(K_WORK, workingDir)
            .putExtra(K_TEMP, tempDir)
            .putExtra(K_DEBUG, debug)
            .putExtra(K_START, startCore)
            .putExtra(K_IPV6, ipv6)
            .putExtra(K_PER_APP, perAppEnabled)
            .putExtra(K_PER_APP_MODE, perAppMode)
            .putExtra(K_PER_APP_LIST, ArrayList(perAppList))
            .putExtra(K_HIDE, hideNotification)
            .putExtra(K_STOP_BUTTON, notifyStopButton)
    }

    companion object {
        private const val P = "com.chuanyun.compat."
        const val K_TOKEN = "${P}token"
        const val K_PORT = "${P}port"
        const val K_PATH = "${P}path"
        const val K_NAME = "${P}name"
        const val K_BASE = "${P}base"
        const val K_WORK = "${P}work"
        const val K_TEMP = "${P}temp"
        const val K_DEBUG = "${P}debug"
        const val K_START = "${P}start"
        const val K_IPV6 = "${P}ipv6"
        const val K_PER_APP = "${P}perApp"
        const val K_PER_APP_MODE = "${P}perAppMode"
        const val K_PER_APP_LIST = "${P}perAppList"
        const val K_HIDE = "${P}hide"
        const val K_STOP_BUTTON = "${P}stopButton"

        /** Port of the background core's control service (the app's bgClient). */
        const val GRPC_PORT_BACK = 17079

        /** Set by the app before each connect (MethodHandler); the tile path keeps the last one. */
        @Volatile
        var ipv6FromApp: Boolean = false

        /** In the app process: the current settings. */
        fun fromSettings(startCore: Boolean) = CompatLaunch(
            token = GrpcAuth.token,
            grpcPort = GRPC_PORT_BACK,
            configPath = Settings.activeConfigPath,
            profileName = Settings.activeProfileName,
            baseDir = Settings.baseDir,
            workingDir = Settings.workingDir,
            tempDir = Settings.tempDir,
            debug = Settings.debugMode,
            startCore = startCore,
            ipv6 = ipv6FromApp,
            perAppEnabled = Settings.perAppProxyEnabled,
            perAppMode = Settings.perAppProxyMode,
            perAppList = Settings.perAppProxyList.filter { it.isNotBlank() },
            hideNotification = Settings.hideNotification,
            notifyStopButton = Settings.notifyStopButton,
        )

        /** In the :compat process: null when the intent did not come from the app (no token). */
        fun from(intent: Intent?): CompatLaunch? {
            intent ?: return null
            val token = intent.getStringExtra(K_TOKEN).orEmpty()
            if (token.isEmpty()) return null
            return CompatLaunch(
                token = token,
                grpcPort = intent.getIntExtra(K_PORT, GRPC_PORT_BACK),
                configPath = intent.getStringExtra(K_PATH).orEmpty(),
                profileName = intent.getStringExtra(K_NAME).orEmpty(),
                baseDir = intent.getStringExtra(K_BASE).orEmpty(),
                workingDir = intent.getStringExtra(K_WORK).orEmpty(),
                tempDir = intent.getStringExtra(K_TEMP).orEmpty(),
                debug = intent.getBooleanExtra(K_DEBUG, false),
                startCore = intent.getBooleanExtra(K_START, false),
                ipv6 = intent.getBooleanExtra(K_IPV6, false),
                perAppEnabled = intent.getBooleanExtra(K_PER_APP, false),
                perAppMode = intent.getStringExtra(K_PER_APP_MODE).orEmpty(),
                perAppList = intent.getStringArrayListExtra(K_PER_APP_LIST).orEmpty(),
                hideNotification = intent.getBooleanExtra(K_HIDE, false),
                notifyStopButton = intent.getBooleanExtra(K_STOP_BUTTON, true),
            )
        }
    }
}

/**
 * State the :compat process leaves for the app process, in small files of their own (only that
 * process writes them; the app process reads them): when the connection came up (the app's
 * 「已连接」 timer and its killed-in-background check), and that the user disconnected it there
 * (so the boot start does not bring it back). Cleared each time the app starts a service.
 */
object CompatState {
    private fun file(name: String) = File(Application.application.filesDir, name)
    private const val SINCE = "compat_connected_since"
    private const val STOPPED = "compat_stopped_by_user"
    private const val TOKEN = "compat_token"

    fun connectedSince(): Long? = try {
        val f = file(SINCE)
        if (f.exists()) f.readText().trim().toLongOrNull() else null
    } catch (_: Exception) {
        null
    }

    fun markStarted(at: Long) = write(SINCE, at.toString())

    fun clearStarted() {
        delete(SINCE)
        delete(TOKEN)
    }

    /**
     * The running connection's gRPC token (app-private file). When the system ends the app process
     * while 兼容内核 keeps the connection, the restarted app process takes this token over, so it
     * can still reach that core.
     */
    fun saveToken(token: String) = write(TOKEN, token)

    fun runningToken(): String? = try {
        if (file(SINCE).exists()) file(TOKEN).takeIf { it.exists() }?.readText()?.trim()?.takeIf { it.isNotEmpty() } else null
    } catch (_: Exception) {
        null
    }

    fun markStoppedByUser() = write(STOPPED, System.currentTimeMillis().toString())

    fun stoppedByUser(): Boolean = try {
        file(STOPPED).exists()
    } catch (_: Exception) {
        false
    }

    fun clear() {
        delete(SINCE)
        delete(STOPPED)
        delete(TOKEN)
    }

    private fun write(name: String, text: String) {
        try {
            file(name).writeText(text)
        } catch (_: Exception) {
        }
    }

    private fun delete(name: String) {
        try {
            file(name).delete()
        } catch (_: Exception) {
        }
    }
}
