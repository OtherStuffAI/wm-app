package com.wingmanbefree.wingman_app

import android.app.Activity
import androidx.activity.result.contract.ActivityResultContracts
import com.wingmanbefree.wingman_app.filepicker.FilePickerPlatformContract
import com.wingmanbefree.wingman_app.filepicker.WebViewFilePickerCoordinator
import com.wingmanbefree.wingman_app.fips.FipsPlatformContract
import com.wingmanbefree.wingman_app.fips.FipsRuntimeCoordinator
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var fipsCoordinator: FipsRuntimeCoordinator? = null
    private var fipsChannel: MethodChannel? = null
    private var filePickerCoordinator: WebViewFilePickerCoordinator? = null
    private var filePickerChannel: MethodChannel? = null

    private val vpnConsentLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        fipsCoordinator?.onVpnConsentResult(activityResult.resultCode == Activity.RESULT_OK)
    }

    private val diagnosticsExportLauncher = registerForActivityResult(
        ActivityResultContracts.CreateDocument("text/plain"),
    ) { uri -> fipsCoordinator?.onDiagnosticsDestination(uri?.toString()) }

    private val openDocumentLauncher = registerForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri -> filePickerCoordinator?.complete(uri?.toString()) }

    private val openMultipleDocumentsLauncher = registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris -> filePickerCoordinator?.complete(uris.map { it.toString() }) }

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

        val pickerCoordinator = WebViewFilePickerCoordinator(
            launchSingleDocument = openDocumentLauncher::launch,
            launchMultipleDocuments = openMultipleDocumentsLauncher::launch,
        )
        filePickerCoordinator = pickerCoordinator
        filePickerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FilePickerPlatformContract.CHANNEL,
        ).also { it.setMethodCallHandler(pickerCoordinator) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        filePickerChannel?.setMethodCallHandler(null)
        filePickerChannel = null
        filePickerCoordinator?.destroy()
        filePickerCoordinator = null
        fipsChannel?.setMethodCallHandler(null)
        fipsChannel = null
        fipsCoordinator?.destroy()
        fipsCoordinator = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        filePickerCoordinator?.destroy()
        filePickerCoordinator = null
        fipsCoordinator?.destroy()
        fipsCoordinator = null
        super.onDestroy()
    }
}
