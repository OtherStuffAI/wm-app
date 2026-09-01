package com.wingmanbefree.wingman_app.fips

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import com.wingmanbefree.wingman_app.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

internal class FipsRuntimeCoordinator(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private var consentResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "inspect" -> background(result) { inspectWithConsentState() }
            "start", "repair" -> start(result)
            "stop" -> background(result) {
                FipsVpnService.stop(activity)
                FipsNative.nativeStop()
            }
            "peerStatus" -> backgroundMap(result) {
                FipsPlatformContract.peerStatus(FipsNative.nativePeerStatus())
            }
            "probe" -> {
                val npub = call.argument<String>("npub")
                if (npub == null) result.error("invalid_argument", "npub is required", null)
                else backgroundMap(result) { FipsPlatformContract.probe(FipsNative.nativeProbe(npub)) }
            }
            else -> result.notImplemented()
        }
    }

    private fun inspectWithConsentState(): String {
        val raw = FipsNative.nativeInspect()
        val status = JSONObject(raw)
        if (status.optString("state") == "notInstalled" && VpnService.prepare(activity) != null) {
            status.put("state", "consentRequired")
            status.put("detail", "Android VPN consent is required to start embedded FIPS.")
        }
        return status.toString()
    }

    private fun start(result: MethodChannel.Result) {
        synchronized(this) {
            if (consentResult != null) {
                result.error("operation_in_progress", "VPN consent is already in progress", null)
                return
            }
            consentResult = result
        }
        worker.execute {
            // A direct repeated start must replace the Java TUN owner as well
            // as nativePrepare's Rust engine; repair follows the same path.
            FipsVpnService.resetForStart(activity)
            val fipsDir = File(activity.filesDir, "fips").apply { mkdirs() }
            val prepared = JSONObject(
                FipsNative.nativePrepare(
                    File(fipsDir, "fips.machine.key").absolutePath,
                    File(fipsDir, "control.sock").absolutePath,
                ),
            )
            if (prepared.optString("state") == "failed") {
                finishConsent(prepared.toString())
                return@execute
            }
            activity.runOnUiThread {
                val consent = VpnService.prepare(activity)
                if (consent == null) launchServiceAndAwait()
                else activity.startActivityForResult(consent, VPN_CONSENT_REQUEST)
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_CONSENT_REQUEST) return false
        if (resultCode != Activity.RESULT_OK) {
            worker.execute { FipsNative.nativeStop() }
            finishConsent(
                JSONObject()
                    .put("state", "failed")
                    .put("detail", "Android VPN consent was cancelled.")
                    .toString(),
            )
        } else {
            launchServiceAndAwait()
        }
        return true
    }

    private fun launchServiceAndAwait() {
        FipsVpnService.start(activity)
        worker.execute {
            repeat(100) {
                val status = FipsNative.nativeInspect()
                val state = JSONObject(status).optString("state")
                if (state == "running" || state == "failed") {
                    finishConsent(status)
                    return@execute
                }
                Thread.sleep(100)
            }
            finishConsent(
                JSONObject().put("state", "failed")
                    .put("detail", "Embedded FIPS did not become ready in time.").toString(),
            )
        }
    }

    private fun finishConsent(raw: String) {
        val pending = synchronized(this) {
            val value = consentResult
            consentResult = null
            value
        } ?: return
        activity.runOnUiThread { pending.success(jsonToMap(raw)) }
    }

    private fun background(result: MethodChannel.Result, action: () -> String) {
        worker.execute {
            val raw = runCatching(action).getOrElse {
                JSONObject().put("state", "failed").put("detail", it.message ?: "Native FIPS failed.").toString()
            }
            activity.runOnUiThread { result.success(jsonToMap(raw)) }
        }
    }

    private fun backgroundMap(result: MethodChannel.Result, action: () -> Map<String, Any?>) {
        worker.execute {
            val value = runCatching(action).getOrElse {
                mapOf("ok" to false, "connected" to false, "detail" to (it.message ?: "Native FIPS failed."))
            }
            activity.runOnUiThread { result.success(value) }
        }
    }

    private fun jsonToMap(raw: String): Map<String, Any?> {
        val json = JSONObject(raw)
        return json.keys().asSequence().associateWith { key -> if (json.isNull(key)) null else json.get(key) }
    }

    companion object {
        private const val VPN_CONSENT_REQUEST = 7211
    }
}
