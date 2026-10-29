package com.hiddify.hiddify.bg

// 穿云 1.7.0: VPN service of 兼容内核, in the :compat process. It builds the TUN itself (address,
// routes, DNS, which apps) and hands the descriptor to the core; the app itself stays outside the
// TUN, so the core's own connections go straight out without per-socket protection.
// Part of 穿云 (GPLv3).

import android.content.Intent
import android.content.pm.PackageManager.NameNotFoundException
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import com.hiddify.hiddify.R

class CompatVpnService : VpnService() {
    private val runner = CompatService(this) { launch -> openTun(launch) }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = runner.onStartCommand(intent)

    override fun onBind(intent: Intent): IBinder {
        return super.onBind(intent) ?: runner.onBind(intent)
    }

    override fun onDestroy() {
        runner.onDestroy()
        super.onDestroy()
    }

    override fun onRevoke() {
        runner.onRevoke()
    }

    private fun openTun(launch: CompatLaunch): ParcelFileDescriptor {
        if (prepare(this) != null) error("android: missing vpn permission")
        val builder = Builder()
            .setSession(getString(R.string.app_name))
            .setMtu(CompatService.TUN_MTU)
            .addAddress(CompatService.TUN_ADDRESS_V4, 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer(CompatService.TUN_DNS_V4)
        if (launch.ipv6) {
            builder.addAddress(CompatService.TUN_ADDRESS_V6, 126)
            builder.addRoute("::", 0)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }
        val (allowed, disallowed) =
            CompatService.appLists(launch.perAppEnabled, launch.perAppMode, launch.perAppList, packageName)
        for (app in allowed) {
            try {
                builder.addAllowedApplication(app)
            } catch (_: NameNotFoundException) {
                Log.d(TAG, "not installed: $app")
            }
        }
        for (app in disallowed) {
            try {
                builder.addDisallowedApplication(app)
            } catch (_: NameNotFoundException) {
                Log.d(TAG, "not installed: $app")
            }
        }
        // like the standard service: no HTTP proxy published on the VPN
        return builder.establish() ?: error("android: the application is not prepared or is revoked")
    }

    companion object {
        private const val TAG = "A/CompatVpnService"
    }
}
