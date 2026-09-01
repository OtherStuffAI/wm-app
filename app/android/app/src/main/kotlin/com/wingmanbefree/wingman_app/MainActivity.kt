package com.wingmanbefree.wingman_app

import android.content.Intent
import com.wingmanbefree.wingman_app.fips.FipsPlatformContract
import com.wingmanbefree.wingman_app.fips.FipsRuntimeCoordinator
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var fipsCoordinator: FipsRuntimeCoordinator

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fipsCoordinator = FipsRuntimeCoordinator(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FipsPlatformContract.CHANNEL)
            .setMethodCallHandler(fipsCoordinator)
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (::fipsCoordinator.isInitialized && fipsCoordinator.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
