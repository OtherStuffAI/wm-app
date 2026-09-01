package com.wingmanbefree.wingman_app.fips

internal object FipsNative {
    init {
        System.loadLibrary("wmapp_fips_android")
    }

    external fun nativePrepare(identityPath: String, controlPath: String): String
    external fun nativeStartNode(): String
    external fun nativeRunNode(tunFd: Int): String
    external fun nativeInspect(): String
    external fun nativeStop(): String
    external fun nativePeerStatus(): String
    external fun nativeProbe(npub: String): String
}
