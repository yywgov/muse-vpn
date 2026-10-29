package com.hiddify.hiddify.utils

import java.security.SecureRandom

/**
 * Muse VPN: per-process token for the core's local gRPC servers (127.0.0.1:17078/17079).
 *
 * Loopback ports on Android are reachable by every installed app, so the core
 * rejects any call without metadata "x-muse-token". The token lives only in
 * memory; Flutter fetches it over the MethodChannel ("get_grpc_token"), and the
 * Kotlin notification poller adds it as a header. The core runs in this same
 * process, so a process restart resets both sides together.
 */
object GrpcAuth {
    const val HEADER = "x-muse-token"

    private val own: String by lazy {
        // 穿云 1.7.0: a 兼容内核 connection outlived the previous app process: keep its token
        com.hiddify.hiddify.bg.CompatState.runningToken()?.let { return@lazy it }
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        bytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * 穿云 1.7.0: the 兼容内核 process (:compat) uses the app process's token, handed over in its
     * start intent, so the app reaches either core with the one token it already has.
     */
    @Volatile
    var override: String? = null

    val token: String get() = override ?: own
}
