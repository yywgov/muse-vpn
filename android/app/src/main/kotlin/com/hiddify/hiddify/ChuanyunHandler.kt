package com.hiddify.hiddify

// 穿云: platform bits for the privacy, keep-alive and 按网络自动开关 settings.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.location.LocationManagerCompat
import com.hiddify.hiddify.bg.NetworkAuto
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
        private const val LOCATION_REQUEST = 4711

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
    private var permissionResult: MethodChannel.Result? = null

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
    ): Boolean {
        if (requestCode != LOCATION_REQUEST) return false
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(granted)
        permissionResult = null
        return true
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

                "get_wifi_ssid" -> result.success(NetworkAuto.currentSsid(context))

                "location_status" -> {
                    val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    result.success(
                        mapOf(
                            "granted" to NetworkAuto.hasLocationPermission(context),
                            "background" to NetworkAuto.hasBackgroundLocationPermission(context),
                            "enabled" to (lm != null && LocationManagerCompat.isLocationEnabled(lm)),
                        )
                    )
                }

                "request_location_permission" -> {
                    val act = activity
                    if (act == null) {
                        result.success(false)
                        return
                    }
                    if (NetworkAuto.hasLocationPermission(act)) {
                        result.success(true)
                        return
                    }
                    permissionResult?.success(false)
                    permissionResult = result
                    ActivityCompat.requestPermissions(
                        act,
                        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                        LOCATION_REQUEST,
                    )
                }

                "open_location_settings" ->
                    result.success(startFirst(listOf(Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS))))

                "apply_network_auto" -> {
                    NetworkAuto.apply(context.applicationContext)
                    NetworkAuto.evaluate(context.applicationContext)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("chuanyun", e.message, null)
        }
    }
}
