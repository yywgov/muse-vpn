package com.hiddify.hiddify.bg

import android.net.Network
import android.os.Build
import com.hiddify.hiddify.Application
import com.hiddify.core.libbox.InterfaceUpdateListener
import com.hiddify.hiddify.constant.Bugs


import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import java.net.NetworkInterface

object DefaultNetworkMonitor {

    var defaultNetwork: Network? = null
    private var listener: InterfaceUpdateListener? = null

    suspend fun start() {
        DefaultNetworkListener.start(this) {
            defaultNetwork = it
            checkDefaultInterfaceUpdate(it)
        }
        defaultNetwork = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Application.connectivity.activeNetwork
        } else {
            DefaultNetworkListener.get()
        }
    }

    suspend fun stop() {
        lastInterface = null
        DefaultNetworkListener.stop(this)
    }

    suspend fun require(): Network {
        val network = defaultNetwork
        if (network != null) {
            return network
        }
        return DefaultNetworkListener.get()
    }

    fun setListener(listener: InterfaceUpdateListener?) {
        this.listener = listener
        checkDefaultInterfaceUpdate(defaultNetwork)
    }

    // 穿云: the last default interface, so the disconnect log notes real changes only
    @Volatile
    private var lastInterface: String? = null

    private fun noteNetwork(interfaceName: String) {
        val previous = lastInterface
        if (previous == interfaceName) return
        lastInterface = interfaceName
        when {
            interfaceName.isEmpty() -> DisconnectLog.record("网络断开（没有可用网络）")
            previous == null -> {}
            previous.isEmpty() -> DisconnectLog.record("网络恢复：$interfaceName")
            else -> DisconnectLog.record("网络切换：$previous → $interfaceName")
        }
    }

    private fun checkDefaultInterfaceUpdate(newNetwork: Network?) {
        val listener = listener ?: return
        if (newNetwork != null) {
            val interfaceName =
                (Application.connectivity.getLinkProperties(newNetwork) ?: return).interfaceName
            for (times in 0 until 10) {
                var interfaceIndex: Int
                try {
                    interfaceIndex = NetworkInterface.getByName(interfaceName).index
                } catch (e: Exception) {
                    Thread.sleep(100)
                    continue
                }
                noteNetwork(interfaceName ?: "")
                listener.updateDefaultInterface(interfaceName, interfaceIndex, false, false)
                // 穿云: report once. Without this break the same change was sent to the core ten
                // times in a row (upstream sing-box-for-android breaks here too).
                break
            }
        } else {
            noteNetwork("")
            listener.updateDefaultInterface("", -1, false, false)
        }
    }
}