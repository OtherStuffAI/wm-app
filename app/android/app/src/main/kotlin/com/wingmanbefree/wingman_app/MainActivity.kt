package com.wingmanbefree.wingman_app

import android.app.Activity
import androidx.activity.result.contract.ActivityResultContracts
import com.wingmanbefree.wingman_app.fips.FipsPlatformContract
import com.wingmanbefree.wingman_app.fips.FipsRuntimeCoordinator
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var fipsCoordinator: FipsRuntimeCoordinator? = null
    private var fipsChannel: MethodChannel? = null

    private val vpnConsentLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        fipsCoordinator?.onVpnConsentResult(activityResult.resultCode == Activity.RESULT_OK)
    }

    private val diagnosticsExportLauncher = registerForActivityResult(
        ActivityResultContracts.CreateDocument("text/plain"),
    ) { uri -> fipsCoordinator?.onDiagnosticsDestination(uri?.toString()) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val coordinator = FipsRuntimeCoordinator(
            this,
            launchConsent = { vpnConsentLauncher.launch(it) },
            launchDiagnosticsExport = { diagnosticsExportLauncher.launch(it) },
        )
        fipsCoordinator = coordinator
        fipsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FipsPlatformContract.CHANNEL,
        ).also { it.setMethodCallHandler(coordinator) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        fipsChannel?.setMethodCallHandler(null)
        fipsChannel = null
        fipsCoordinator?.destroy()
        fipsCoordinator = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        fipsCoordinator?.destroy()
        fipsCoordinator = null
        super.onDestroy()
    }
}
