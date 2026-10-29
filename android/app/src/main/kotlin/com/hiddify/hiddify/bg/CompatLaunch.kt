package com.hiddify.hiddify.bg

// 穿云 1.7.0: everything the 兼容内核 process needs for one connection, handed over in the start
// intent by the app process. That process never reads stale preferences or writes any; the gRPC
// token is the app process's own, so the app talks to either core with the same token.
// Part of 穿云 (GPLv3).

import android.content.Intent
import com.hiddify.hiddify.Application
import org.json.JSONArray
import org.json.JSONObject
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

    /** For the system's restart of this service after the process was killed (CompatState.saveLaunch). */
    fun toJson(): String = JSONObject()
        .put(K_TOKEN, token).put(K_PORT, grpcPort).put(K_PATH, configPath).put(K_NAME, profileName)
        .put(K_BASE, baseDir).put(K_WORK, workingDir).put(K_TEMP, tempDir).put(K_DEBUG, debug)
        .put(K_START, startCore).put(K_IPV6, ipv6).put(K_PER_APP, perAppEnabled)
        .put(K_PER_APP_MODE, perAppMode).put(K_PER_APP_LIST, JSONArray(perAppList))
        .put(K_HIDE, hideNotification).put(K_STOP_BUTTON, notifyStopButton)
        .toString()

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

        /** The saved hand-over (toJson); null when missing, unreadable or without a token. */
        fun fromJson(text: String?): CompatLaunch? = try {
            val j = JSONObject(text ?: return null)
            val token = j.optString(K_TOKEN)
            if (token.isEmpty()) {
                null
            } else {
                val apps = j.optJSONArray(K_PER_APP_LIST)
                CompatLaunch(
                    token = token,
                    grpcPort = j.optInt(K_PORT, GRPC_PORT_BACK),
                    configPath = j.optString(K_PATH),
                    profileName = j.optString(K_NAME),
                    baseDir = j.optString(K_BASE),
                    workingDir = j.optString(K_WORK),
                    tempDir = j.optString(K_TEMP),
                    debug = j.optBoolean(K_DEBUG, false),
                    startCore = j.optBoolean(K_START, false),
                    ipv6 = j.optBoolean(K_IPV6, false),
                    perAppEnabled = j.optBoolean(K_PER_APP, false),
                    perAppMode = j.optString(K_PER_APP_MODE),
                    perAppList = if (apps == null) emptyList() else List(apps.length()) { apps.optString(it) }.filter { it.isNotBlank() },
                    hideNotification = j.optBoolean(K_HIDE, false),
                    notifyStopButton = j.optBoolean(K_STOP_BUTTON, true),
                )
            }
        } catch (_: Exception) {
            null
        }

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
    private const val LAUNCH = "compat_launch"

    /**
     * The running connection's hand-over (app-private file), so that when the system kills the
     * :compat process and re-creates the service (START_STICKY, no intent) the connection comes
     * back by itself, like the standard service does. Removed when the user disconnects, the VPN
     * permission is taken away, or a start fails; no timer or polling is involved.
     */
    fun saveLaunch(launch: CompatLaunch) = write(LAUNCH, launch.toJson())

    fun savedLaunch(): CompatLaunch? = try {
        val f = file(LAUNCH)
        if (f.exists()) CompatLaunch.fromJson(f.readText()) else null
    } catch (_: Exception) {
        null
    }

    fun clearLaunch() = delete(LAUNCH)

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
        delete(LAUNCH)
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
