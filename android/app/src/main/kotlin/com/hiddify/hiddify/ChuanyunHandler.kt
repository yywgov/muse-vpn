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
    // 1.15.0 R23: Wi‑Fi 变化事件（只在 Dart 订阅时注册系统回调）
    private var wifiEvents: io.flutter.plugin.common.EventChannel? = null
    private val wifiWatch = com.hiddify.hiddify.bg.ChuanyunWifiWatch { context }
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, channelName)
        channel!!.setMethodCallHandler(this)
        wifiEvents = io.flutter.plugin.common.EventChannel(flutterPluginBinding.binaryMessenger, com.hiddify.hiddify.bg.ChuanyunWifiWatch.channelName)
        wifiEvents!!.setStreamHandler(wifiWatch)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        wifiEvents?.setStreamHandler(null)
        wifiEvents = null
        wifiWatch.unregister()
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

                // 穿云 1.11.0: the node in use / its delay for the home-screen widget (sent on a change only)
                "widget_update" -> {
                    com.hiddify.hiddify.bg.ChuanyunWidget.onNodeFavs(
                        call.argument<String>("node") ?: "",
                        call.argument<Int>("delay") ?: 0,
                        // 1.16.0 R25: 常用节点 (first 3 favourites)
                        com.hiddify.hiddify.bg.ChuanyunWidget.zipFavs(
                            call.argument<List<String>>("favTags") ?: emptyList(),
                            call.argument<List<String>>("favNames") ?: emptyList(),
                        ),
                    )
                    // 穿云 1.12.0: the quick-settings tile shows the same 「节点 · 延迟」
                    if (android.os.Build.VERSION.SDK_INT >= 24) com.hiddify.hiddify.bg.TileService.refresh(Application.application)
                    result.success(true)
                }

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

                // 1.16.0 B8: 敏感页禁截屏（FLAG_SECURE 同时让最近任务里的缩略图变空白）。只作用于当前窗口，
                // 在主线程调用（MethodChannel 回调本来就在主线程），离开敏感页即清除。
                "set_secure_screen" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    val window = activity?.window
                    if (window == null) {
                        result.success(false)
                    } else {
                        if (on) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(true)
                    }
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

                // ---- 穿云 1.13.0: 上次异常 / 安全模式 / 被其他 VPN 顶掉 (ChuanyunHealth) ----
                "health_state" -> result.success(com.hiddify.hiddify.bg.ChuanyunHealth.state())
                "health_log" -> result.success(com.hiddify.hiddify.bg.ChuanyunHealth.read())
                "health_start_failed" -> {
                    com.hiddify.hiddify.bg.ChuanyunHealth.startFailed(call.argument<String>("reason") ?: "")
                    result.success(true)
                }
                "health_start_ok" -> {
                    com.hiddify.hiddify.bg.ChuanyunHealth.startSucceeded()
                    result.success(true)
                }
                "health_exit_safe_mode" -> {
                    com.hiddify.hiddify.bg.ChuanyunHealth.exitSafeMode()
                    result.success(true)
                }
                "health_dismiss_crash" -> {
                    com.hiddify.hiddify.bg.ChuanyunHealth.dismissCrash()
                    result.success(true)
                }
                "health_dismiss_revoked" -> {
                    com.hiddify.hiddify.bg.ChuanyunHealth.dismissRevoked()
                    result.success(true)
                }
                // 连不上诊断: another app's VPN is up (asked only while 穿云 is disconnected)
                "other_vpn_active" -> {
                    val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                    @Suppress("DEPRECATION")
                    val vpn = cm?.let { m ->
                        m.allNetworks.any { n -> m.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }
                    } ?: false
                    result.success(vpn)
                }
                "open_vpn_settings" -> result.success(startFirst(listOf(Intent(android.provider.Settings.ACTION_VPN_SETTINGS))))
                // 连不上诊断「释放内核」: the background core of this process (17079), when no service runs
                "release_core" -> {
                    // 1.13.0: never on the main thread (Flutter's UI thread); at most 10 s
                    val main = Handler(Looper.getMainLooper())
                    Thread({
                        com.hiddify.hiddify.bg.BoxService.releaseCore()
                        main.post { result.success(true) }
                    }, "chuanyun-release-core").start()
                }
                // debug builds only (the emulator e2e run): the 开机自启 and 小组件更新 paths
                "e2e_boot" -> {
                    if ((context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
                        result.success(false)
                    } else {
                        com.hiddify.hiddify.bg.BootReceiver.autoStart()
                        result.success(true)
                    }
                }
                "e2e_widget_update" -> {
                    if ((context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
                        result.success(false)
                    } else {
                        val app = context.applicationContext
                        val cn = ComponentName(app, com.hiddify.hiddify.bg.ChuanyunWidget::class.java)
                        val ids = android.appwidget.AppWidgetManager.getInstance(app).getAppWidgetIds(cn)
                        app.sendBroadcast(
                            Intent(android.appwidget.AppWidgetManager.ACTION_APPWIDGET_UPDATE).setComponent(cn)
                                .putExtra(android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                        )
                        com.hiddify.hiddify.bg.ChuanyunWidget.onNode("e2e", 1)
                        result.success(true)
                    }
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
