package com.hiddify.hiddify

// 穿云: platform bits for the privacy and keep-alive settings (1.2.1: 按网络自动开关 removed).
// 1.6.0 C9: the current Wi‑Fi name for 按需运行 (asks for 「位置信息」 only when the user turns it
// on — Android hides Wi‑Fi names from apps without it), and which apps may use the network
// (分应用代理 › 只看联网应用).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import android.os.Build
import com.hiddify.hiddify.bg.ChuanyunAlerts
import com.hiddify.hiddify.bg.DisconnectLog
import androidx.core.content.FileProvider
import java.io.File
import android.os.PowerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class ChuanyunHandler : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val channelName = "com.chuanyun.app/system"

        fun launcherAlias(context: Context) = ComponentName(context.packageName, "com.hiddify.hiddify.LauncherAlias")

        fun isLauncherHidden(context: Context): Boolean =
            context.packageManager.getComponentEnabledSetting(launcherAlias(context)) ==
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED

        /** Applies 「不在最近任务显示」 to the app's current tasks. */
        fun applyExcludeFromRecents(context: Context, exclude: Boolean) {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return
            try {
                am.appTasks.forEach { it.setExcludeFromRecents(exclude) }
            } catch (_: Exception) {
            }
        }
    }

    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, channelName)
        channel!!.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun attach(b: ActivityPluginBinding) {
        binding = b
        activity = b.activity
        b.addRequestPermissionsResultListener(this)
    }

    private fun detach() {
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        activity = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attach(binding)
    override fun onDetachedFromActivityForConfigChanges() = detach()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attach(binding)
    override fun onDetachedFromActivity() = detach()

    private val wifiPermissionRequest = 1601
    private var pendingWifiPermission: MethodChannel.Result? = null

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != wifiPermissionRequest) return false
        val r = pendingWifiPermission ?: return true
        pendingWifiPermission = null
        r.success(wifiPermissionState(afterRequest = true))
        return true
    }

    private fun hasFineLocation() =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /** granted / denied / blocked (denied with 「不再询问」: only the app's settings page helps). */
    private fun wifiPermissionState(afterRequest: Boolean): String {
        if (hasFineLocation()) return "granted"
        val a = activity
        if (afterRequest && a != null &&
            !androidx.core.app.ActivityCompat.shouldShowRequestPermissionRationale(a, Manifest.permission.ACCESS_FINE_LOCATION)
        ) return "blocked"
        return "denied"
    }

    /** {ok, ssid} — ok false with a reason when Android won't say (permission, location off…). */
    @Suppress("DEPRECATION")
    private fun readWifi(): Map<String, Any?> {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val onWifi = cm.allNetworks.any { n ->
            cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
        if (!onWifi) return mapOf("ok" to true, "ssid" to null)
        if (!hasFineLocation()) return mapOf("ok" to false, "reason" to "permission")
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && lm != null && !lm.isLocationEnabled) {
            return mapOf("ok" to false, "reason" to "location_off")
        }
        val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val ssid = wm?.connectionInfo?.ssid?.removeSurrounding("\"")
        if (ssid.isNullOrBlank() || ssid == "<unknown ssid>") return mapOf("ok" to false, "reason" to "unknown")
        return mapOf("ok" to true, "ssid" to ssid)
    }

    private val context: Context get() = activity ?: Application.application

    private fun startFirst(intents: List<Intent>): Boolean {
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun appDetailsIntent() =
        Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "is_launcher_icon_hidden" -> result.success(isLauncherHidden(context))

                "set_launcher_icon_hidden" -> {
                    val hidden = call.argument<Boolean>("hidden") ?: false
                    context.packageManager.setComponentEnabledSetting(
                        launcherAlias(context),
                        if (hidden) PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                        else PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                    result.success(true)
                }

                "set_exclude_from_recents" -> {
                    applyExcludeFromRecents(context, call.argument<Boolean>("exclude") ?: false)
                    result.success(true)
                }

                "open_notification_settings" -> {
                    val intents = mutableListOf<Intent>()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        intents.add(
                            Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
                        )
                    }
                    intents.add(appDetailsIntent())
                    result.success(startFirst(intents))
                }

                "open_app_details" -> result.success(startFirst(listOf(appDetailsIntent())))

                // 穿云 1.4.1: 诊断 › 时间不准
                "open_date_settings" -> result.success(
                    startFirst(listOf(Intent(android.provider.Settings.ACTION_DATE_SETTINGS), appDetailsIntent()))
                )

                // ColorOS / OPPO: 自启动 manager; other systems fall back to the app's details page
                "open_autostart_settings" -> {
                    val intents = listOf(
                        Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")),
                        Intent().setComponent(ComponentName("com.oplus.safecenter", "com.oplus.safecenter.startupapp.StartupAppListActivity")),
                        Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")),
                        Intent().setComponent(ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")),
                        appDetailsIntent(),
                    )
                    result.success(startFirst(intents))
                }

                "get_connected_since" -> result.success(Settings.connectedSince)

                // 穿云 1.6.0 C9: 按需运行
                "wifi_ssid" -> result.success(readWifi())

                "wifi_permission" -> result.success(wifiPermissionState(afterRequest = false))

                "request_wifi_permission" -> {
                    val a = activity
                    if (hasFineLocation() || a == null) {
                        result.success(wifiPermissionState(afterRequest = false))
                    } else {
                        pendingWifiPermission?.success("denied")
                        pendingWifiPermission = result
                        // Android 12+ wants both in one request; only 「精确」 reveals the Wi‑Fi name
                        androidx.core.app.ActivityCompat.requestPermissions(
                            a,
                            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                            wifiPermissionRequest,
                        )
                    }
                }

                // 穿云 1.6.0 C9: 分应用代理 › 只看联网应用 (apps that asked for INTERNET)
                "internet_packages" -> {
                    val pm = context.packageManager
                    val main = Handler(Looper.getMainLooper())
                    Thread {
                        val list = try {
                            pm.getPackagesHoldingPermissions(arrayOf(Manifest.permission.INTERNET), 0).map { it.packageName }
                        } catch (_: Exception) {
                            null
                        }
                        main.post { result.success(list) }
                    }.start()
                }

                // 穿云 1.4.1: background-kill detection (a start recorded before the last boot is a
                // reboot, not a kill) and the brand-specific keep-alive steps
                "device_info" -> result.success(
                    mapOf(
                        "manufacturer" to (Build.MANUFACTURER ?: ""),
                        "brand" to (Build.BRAND ?: ""),
                        "boot_time" to (System.currentTimeMillis() - android.os.SystemClock.elapsedRealtime()),
                    )
                )

                // 穿云: 关于 › 导出诊断 — disconnect reasons, core crash traces, device facts
                "diagnostics_native" -> {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val batteryIgnored = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        pm?.isIgnoringBatteryOptimizations(context.packageName) == true
                    val device = buildString {
                        append("设备: ${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})\n")
                        append("Android: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT}), 系统版本: ${Build.DISPLAY}\n")
                        append("已关闭电池优化: $batteryIgnored\n")
                        append("用户希望保持连接: ${Settings.startedByUser}\n")
                        append("本次连接开始: ${Settings.connectedSince}\n")
                    }
                    result.success(
                        mapOf(
                            "device" to device,
                            "disconnects" to DisconnectLog.read(),
                            "crash" to DisconnectLog.readCrashTraces(),
                        )
                    )
                }

                "record_disconnect" -> {
                    DisconnectLog.record(call.argument<String>("reason") ?: "")
                    result.success(true)
                }

                "show_alert" -> {
                    ChuanyunAlerts.show(
                        context.applicationContext,
                        call.argument<Int>("id") ?: ChuanyunAlerts.ID_SUBSCRIPTION,
                        call.argument<String>("title") ?: "穿云",
                        call.argument<String>("text") ?: "",
                    )
                    result.success(true)
                }

                // 穿云 1.2.4: whether a downloaded APK is signed with the same key as this app
                // (true / false; null when it can't be read). Android refuses an update signed
                // with another key, so the app says so instead of a failing installer.
                "apk_signature_matches" -> {
                    val path = call.argument<String>("path")
                    result.success(path?.let { apkSignatureMatches(it) })
                }

                // 穿云 1.1: in-app update — install the APK the app downloaded into its cache
                "install_apk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank() || !File(path).exists()) {
                        result.success(false)
                        return
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !context.packageManager.canRequestPackageInstalls()
                    ) {
                        // ask for 「安装未知应用」 first; the user taps 更新 again afterwards
                        startFirst(
                            listOf(
                                Intent(
                                    android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:${context.packageName}")
                                )
                            )
                        )
                        result.success(false)
                        return
                    }
                    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", File(path))
                    val intent = Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    result.success(startFirst(listOf(intent)))
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("chuanyun", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun signerDigests(info: android.content.pm.PackageInfo?): Set<String>? {
        info ?: return null
        val sigs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val si = info.signingInfo ?: return null
            if (si.hasMultipleSigners()) si.apkContentsSigners else si.signingCertificateHistory
        } else {
            info.signatures
        } ?: return null
        val md = java.security.MessageDigest.getInstance("SHA-256")
        return sigs.map { md.digest(it.toByteArray()).joinToString("") { b -> "%02x".format(b) } }.toSet()
    }

    @Suppress("DEPRECATION")
    private fun apkSignatureMatches(path: String): Boolean? = try {
        val pm = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
        else android.content.pm.PackageManager.GET_SIGNATURES
        val mine = signerDigests(pm.getPackageInfo(context.packageName, flags))
        val theirs = signerDigests(pm.getPackageArchiveInfo(path, flags))
        if (mine == null || theirs == null) null else mine.intersect(theirs).isNotEmpty()
    } catch (e: Exception) {
        null
    }
}
