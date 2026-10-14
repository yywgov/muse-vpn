package com.hiddify.hiddify

// 穿云: platform bits for the privacy and keep-alive settings (1.2.1: 按网络自动开关 removed).
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean = false

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
}
