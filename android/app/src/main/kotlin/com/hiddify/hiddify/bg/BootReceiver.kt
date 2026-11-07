package com.hiddify.hiddify.bg
import android.content.BroadcastReceiver
import android.content.Context

import android.content.Intent
import com.hiddify.hiddify.MainActivity
import com.hiddify.hiddify.Settings
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext


class BootReceiver : BroadcastReceiver() {
    @OptIn(DelicateCoroutinesApi::class)
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
            }

            else -> return
        }
        autoStart()
    }

    companion object {
        /**
         * 开机 / 更新后自动连接: the user had the tunnel on → start it with the core (no app UI).
         * 穿云 1.13.0: also the entry the debug e2e run uses (MethodHandler "e2e_boot"), since a shell
         * may not send the protected BOOT_COMPLETED broadcast.
         */
        @OptIn(DelicateCoroutinesApi::class)
        fun autoStart() {
            GlobalScope.launch(Dispatchers.IO) {
                if (Settings.startedByUser) {
                    withContext(Dispatchers.Main) {
                        Settings.startCoreAfterStartingService=true //H
                        BoxService.start()
                    }
                }
            }
        }
    }
}