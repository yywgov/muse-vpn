package com.hiddify.hiddify.bg

// 穿云 1.7.0: JNI entry points of 兼容内核 (libmusecompat.so, built from the core repository; its
// jni.c names this class). The library is loaded on first use, which only ever happens in the
// :compat process. The standard core's library is never loaded there.
// Part of 穿云 (GPLv3).

import androidx.annotation.Keep
import com.hiddify.hiddify.Application
import java.io.File

@Keep
object CompatCore {
    const val LIBRARY = "musecompat"

    init {
        System.loadLibrary(LIBRARY)
    }

    /** Starts the core's local control service (loopback + token). Returns "" or the error. */
    @JvmStatic
    external fun nativeSetup(base: String, work: String, temp: String, listen: String, secret: String, debug: Boolean): String

    /** The VPN service's TUN descriptor; the core keeps its own copy per start. 0 = none. */
    @JvmStatic
    external fun nativeSetTunFd(fd: Int)

    /** Stops the engine and the control service, and gives the memory back. */
    @JvmStatic
    external fun nativeStop()

    @JvmStatic
    external fun nativeVersion(): String
}

/**
 * Whether this build carries 兼容内核 (release APKs do; a build without it keeps using the standard
 * core). Kept apart from [CompatCore] so asking never loads the library. Native libraries are
 * stored compressed and extracted at install, so the file is there when bundled.
 */
object CompatLibrary {
    val bundled: Boolean by lazy {
        try {
            File(Application.application.applicationInfo.nativeLibraryDir, "lib${CompatCore.LIBRARY}.so").exists()
        } catch (_: Exception) {
            false
        }
    }
}
