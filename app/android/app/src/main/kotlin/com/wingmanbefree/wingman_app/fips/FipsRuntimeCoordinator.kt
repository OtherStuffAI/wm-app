package com.wingmanbefree.wingman_app.fips

import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.wingmanbefree.wingman_app.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

internal class FipsRuntimeCoordinator(
    private val activity: MainActivity,
    private val launchConsent: (Intent) -> Unit,
) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val timer: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
    @Volatile private var alive = true
    private var preparedConsentIntent: Intent? = null

    private val startOperation = FipsStartOperation(object : FipsStartEnvironment {
        override fun runBackground(task: () -> Unit): Boolean = execute(worker, task)
        override fun runMain(task: () -> Unit): Boolean = postMain(task)

        override fun scheduleTimeout(delayMillis: Long, task: () -> Unit): FipsTimeout {
            val future = timer.schedule({ if (alive) task() }, delayMillis, TimeUnit.MILLISECONDS)
            return FipsTimeout { future.cancel(false) }
        }

        override fun resetForStart() {
            FipsVpnServiceFailure.clear()
            FipsVpnService.resetForStart(activity.applicationContext)
        }

        override fun prepareNative(): String {
            val fipsDir = File(activity.filesDir, "fips")
            if (!fipsDir.exists() && !fipsDir.mkdirs()) throw IllegalStateException("directory unavailable")
            return FipsNative.nativePrepare(
                File(fipsDir, "fips.machine.key").absolutePath,
                File(fipsDir, "control.sock").absolutePath,
            )
        }

        override fun prepareVpnConsent(): Boolean {
            check(Looper.myLooper() == Looper.getMainLooper())
            preparedConsentIntent = VpnService.prepare(activity)
            return preparedConsentIntent != null
        }

        override fun launchVpnConsent() {
            check(Looper.myLooper() == Looper.getMainLooper())
            val intent = preparedConsentIntent
                ?: throw IllegalStateException("consent intent unavailable")
            preparedConsentIntent = null
            launchConsent(intent)
        }

        override fun startVpnService() {
            check(Looper.myLooper() == Looper.getMainLooper())
            FipsVpnService.start(activity.applicationContext)
        }

        override fun inspectNative(): String = FipsNative.nativeInspect()

        override fun stopNative() {
            runCatching { FipsNative.nativeStop() }
            FipsVpnService.stop(activity.applicationContext)
        }

        override fun pauseBeforePoll(delayMillis: Long) = Thread.sleep(delayMillis)

        override fun log(event: String, failure: Throwable?) {
            if (failure == null) Log.i(TAG, event)
            else Log.e(TAG, "$event (${failure.javaClass.simpleName})")
        }
    })

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "inspect" -> inspect(result)
                "start", "repair" -> startOperation.start(result.asCompletion())
                "stop" -> backgroundStatus(result) {
                    FipsVpnService.stop(activity.applicationContext)
                    FipsStatus.fromNative(FipsNative.nativeInspect(), "Embedded FIPS could not stop safely.")
                }
                "peerStatus" -> backgroundMap(result) {
                    FipsPlatformContract.peerStatus(FipsNative.nativePeerStatus())
                }
                "probe" -> {
                    val npub = call.argument<String>("npub")
                    if (npub == null) {
                        result.success(FipsStartOperation.failed("invalid_argument", "A FIPS node is required."))
                    } else {
                        backgroundMap(result) { FipsPlatformContract.probe(FipsNative.nativeProbe(npub)) }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (failure: Throwable) {
            logFailure("method_dispatch_failed", failure)
            safeSuccess(
                result,
                FipsStartOperation.failed(
                    "android_bridge_failed",
                    "Android embedded FIPS is unavailable. Please retry.",
                ),
            )
        }
    }

    fun onVpnConsentResult(granted: Boolean): Boolean = startOperation.onVpnConsentResult(granted)

    fun destroy() {
        if (!alive) return
        startOperation.destroy()
        alive = false
        preparedConsentIntent = null
        worker.shutdownNow()
        timer.shutdownNow()
        main.removeCallbacksAndMessages(null)
    }

    private fun inspect(result: MethodChannel.Result) {
        if (!execute(worker) {
                val native = try {
                    FipsStatus.fromNative(FipsNative.nativeInspect(), "Embedded FIPS inspection failed.")
                } catch (failure: Throwable) {
                    logFailure("inspect_native_failed", failure)
                    FipsStartOperation.failed("inspect_failed", "Embedded FIPS inspection failed. Please retry.")
                }
                postMain {
                    val serviceFailure = FipsVpnServiceFailure.peek()
                    val status = if (serviceFailure != null) {
                        FipsStartOperation.failed(serviceFailure.code, serviceFailure.detail)
                    } else if (native["state"] == "notInstalled") {
                        try {
                            if (VpnService.prepare(activity) != null) {
                                native + mapOf(
                                    "state" to "consentRequired",
                                    "detail" to "Android VPN consent is required to start embedded FIPS.",
                                )
                            } else native
                        } catch (failure: Throwable) {
                            logFailure("inspect_consent_failed", failure)
                            FipsStartOperation.failed(
                                "consent_prepare_failed",
                                "Android VPN consent could not be checked. Please retry.",
                            )
                        }
                    } else native
                    safeSuccess(result, status)
                }
            }
        ) {
            safeSuccess(
                result,
                FipsStartOperation.failed(
                    "executor_unavailable",
                    "Embedded FIPS inspection was interrupted. Please retry.",
                ),
            )
        }
    }

    private fun backgroundStatus(result: MethodChannel.Result, action: () -> Map<String, Any?>) {
        if (!execute(worker) {
                val status = try {
                    action()
                } catch (failure: Throwable) {
                    logFailure("background_status_failed", failure)
                    FipsStartOperation.failed("native_failed", "Android embedded FIPS failed. Please retry.")
                }
                postMain { safeSuccess(result, status) }
            }
        ) {
            safeSuccess(
                result,
                FipsStartOperation.failed(
                    "executor_unavailable",
                    "Android embedded FIPS was interrupted. Please retry.",
                ),
            )
        }
    }

    private fun backgroundMap(result: MethodChannel.Result, action: () -> Map<String, Any?>) {
        if (!execute(worker) {
                val value = try {
                    action()
                } catch (failure: Throwable) {
                    logFailure("background_map_failed", failure)
                    mapOf(
                        "ok" to false,
                        "connected" to false,
                        "detail" to "Android embedded FIPS request failed. Please retry.",
                    )
                }
                postMain { safeSuccess(result, value) }
            }
        ) {
            safeSuccess(
                result,
                mapOf(
                    "ok" to false,
                    "connected" to false,
                    "detail" to "Android embedded FIPS was interrupted. Please retry.",
                ),
            )
        }
    }

    private fun MethodChannel.Result.asCompletion() = FipsCompletion { safeSuccess(this, it) }

    private fun safeSuccess(result: MethodChannel.Result, value: Map<String, Any?>) {
        try {
            result.success(value)
        } catch (failure: Throwable) {
            logFailure("result_delivery_failed", failure)
        }
    }

    private fun postMain(task: () -> Unit): Boolean {
        if (!alive || activity.isFinishing || activity.isDestroyed) return false
        return if (Looper.myLooper() == Looper.getMainLooper()) {
            task()
            true
        } else {
            main.post { if (alive && !activity.isDestroyed) task() }
        }
    }

    private fun execute(executor: ExecutorService, task: () -> Unit): Boolean {
        if (!alive || executor.isShutdown) return false
        return try {
            executor.execute { if (alive) task() }
            true
        } catch (_: RejectedExecutionException) {
            false
        }
    }

    private fun logFailure(event: String, failure: Throwable) {
        // Event codes plus exception classes are actionable in logcat without
        // exposing native payloads, identities, secrets, or filesystem paths.
        Log.e(TAG, "$event (${failure.javaClass.simpleName})")
    }

    companion object { private const val TAG = "WMAppFips" }
}
