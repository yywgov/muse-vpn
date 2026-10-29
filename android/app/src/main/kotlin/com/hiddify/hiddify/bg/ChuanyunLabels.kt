package com.hiddify.hiddify.bg

// 穿云: Chinese group names for the native side (notification), the same table as
// lib/features/muse/home/node_label.dart (museKnownGroupName / balance strategies), and the
// screen on/off hook that tells the core to slow its node tests down while the screen is off.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import android.util.Log
import com.hiddify.core.mobile.Mobile

object ChuanyunLabels {
    private val balanceStrategies = mapOf(
        "round-robin" to "轮询",
        "consistent-hashing" to "一致性哈希",
        "consistent-hash" to "一致性哈希",
        "sticky-sessions" to "粘性会话",
        "sticky-session" to "粘性会话",
        "random" to "随机",
    )

    /** Chinese name for a common English group/outbound name ("lowest" -> 自动最快), or null. */
    fun knownGroupName(name: String): String? = when (name.trim().lowercase()) {
        "lowest", "lowest-delay", "auto", "fastest", "urltest", "url-test", "best" -> "自动最快"
        "balance", "balancer", "loadbalance", "load-balance", "round-robin" -> "负载均衡"
        "select", "selector", "proxy", "proxies", "manual" -> "手动选择"
        "fallback", "failover" -> "故障切换"
        "direct" -> "直连"
        "block", "reject" -> "拦截"
        else -> null
    }

    /**
     * The core reports the current outbound as "group→node" ("lowest→香港 01",
     * "balance→round-robin") or just the node a user picked. Returns
     * 「已连接 · 自动最快 · 香港 01」 / 「已连接 · 负载均衡」 / 「已连接 · 香港 01」.
     */
    fun notificationText(currentOutbound: String): String {
        val parts = currentOutbound.split("→").map { it.trim() }.filter { it.isNotEmpty() }
        val items = mutableListOf("已连接")
        when (parts.size) {
            0 -> {}
            1 -> items.add(knownGroupName(parts[0]) ?: parts[0])
            else -> {
                val group = parts[0]
                val selected = parts.last()
                val strategy = balanceStrategies[selected.lowercase()]
                val groupName = knownGroupName(group)
                when {
                    strategy != null -> items.add("负载均衡")
                    groupName == "负载均衡" && selected.lowercase() != "lowest-delay" -> {
                        // a lowest-delay balancer named "balance" still reports the node it picked
                        items.add("自动最快")
                        items.add(knownGroupName(selected) ?: selected)
                    }
                    else -> {
                        items.add(groupName ?: group)
                        if (selected.lowercase() != "lowest-delay") items.add(knownGroupName(selected) ?: selected)
                    }
                }
            }
        }
        return items.joinToString(" · ")
    }

    /** Screen-off: the core tests nodes every 15 minutes; screen-on: re-tests at once. */
    fun screenChanged(on: Boolean) {
        // 穿云 1.7.0: the standard core's library must never load in the 兼容内核 process
        if (ChuanyunProcess.isCompat) return
        try {
            if (on) Mobile.screenOn() else Mobile.screenOff()
        } catch (e: Throwable) {
            Log.w("ChuanyunLabels", "screen hook failed", e)
        }
    }
}
