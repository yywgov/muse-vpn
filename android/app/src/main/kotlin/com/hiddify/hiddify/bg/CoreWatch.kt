package com.hiddify.hiddify.bg

// 穿云: follows the core's own state from inside the VPN service (independent of the Flutter UI),
// so the service notices when the core stops by itself (a failed restart, a recovered panic)
// and can reconnect. A stop the user asked for ends with an EMPTY message type and is ignored.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import com.hiddify.core.api.v2.hcommon.Empty
import com.hiddify.core.api.v2.hcore.CoreClient
import com.hiddify.core.api.v2.hcore.CoreInfoResponse
import com.hiddify.core.api.v2.hcore.CoreStates
import com.hiddify.core.api.v2.hcore.MessageType
import com.hiddify.hiddify.Settings
import com.hiddify.hiddify.utils.GrpcAuth
import com.squareup.wire.GrpcClient
import okhttp3.OkHttpClient
import okhttp3.Protocol
import java.util.concurrent.TimeUnit

object CoreWatch {
    // no read timeout: the status stream is quiet for hours while all is well
    private val client: GrpcClient by lazy {
        val http = OkHttpClient.Builder()
            .protocols(listOf(Protocol.H2_PRIOR_KNOWLEDGE))
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .pingInterval(30, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                chain.proceed(chain.request().newBuilder().header(GrpcAuth.HEADER, GrpcAuth.token).build())
            }
            .build()
        GrpcClient.Builder()
            .client(http)
            .baseUrl("http://127.0.0.1:${Settings.grpcServiceModePort}")
            .build()
    }

    /** Whether a STOPPED state is the core giving up by itself rather than a normal stop. */
    fun isUnexpectedStop(info: CoreInfoResponse): Boolean =
        info.core_state == CoreStates.STOPPED &&
            info.message_type != MessageType.EMPTY &&
            info.message_type != MessageType.ALREADY_STOPPED

    /**
     * Blocks while the core runs and returns the first unexpected stop seen after the core was
     * started. Throws when the stream breaks (the caller retries), returns null when it ends.
     */
    fun awaitUnexpectedStop(onStarted: () -> Unit): CoreInfoResponse? {
        val (sink, source) = client.create(CoreClient::class).CoreInfoListener().executeBlocking()
        sink.write(Empty())
        sink.close()
        source.use {
            var seenStarted = false
            while (true) {
                val info = it.read() ?: return null
                when {
                    info.core_state == CoreStates.STARTED -> {
                        seenStarted = true
                        onStarted()
                    }
                    seenStarted && isUnexpectedStop(info) -> return info
                }
            }
        }
    }
}
