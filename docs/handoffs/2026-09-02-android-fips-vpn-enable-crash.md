# Fix Android crash/error when enabling embedded FIPS VPN

## User report

On Pete's physical Android device, the moment he selected the option to install/enable the FIPS VPN, the whole WM-App errored out. This is a release-blocking first-run failure in the Android embedded FIPS path. No device is currently connected to this Mac, so there is no recoverable logcat yet.

## Goal

Diagnose the consent/start lifecycle from code and make it impossible for VPN preparation, the system consent activity, foreground-service launch, JNI/native preparation, or result delivery to crash/strand the Flutter app. Produce a signed replacement APK for Pete to retest. Do not publish to Zapstore or restart any registered WApp.

## Repo/current state

- Work in `/Users/mini/code/wm/wmapp` on `main`; preserve all concurrent commits and changes.
- Current head is `944df05` or later; inspect before editing.
- Android bridge:
  - `app/android/app/src/main/kotlin/com/wingmanbefree/wingman_app/MainActivity.kt`
  - `app/android/app/src/main/kotlin/com/wingmanbefree/wingman_app/fips/FipsRuntimeCoordinator.kt`
  - `app/android/app/src/main/kotlin/com/wingmanbefree/wingman_app/fips/FipsVpnService.kt`
- Dart bridge/service: `app/lib/src/core/fips_runtime_service.dart`.
- Current coordinator uses deprecated `startActivityForResult`/`onActivityResult`, stores one `MethodChannel.Result`, performs native preparation on an executor, and has unguarded throw paths around reset/native prepare/JSON parsing/consent launch/service launch.
- `inspectWithConsentState()` currently calls `VpnService.prepare(activity)` from the worker executor.
- `launchServiceAndAwait()` calls `FipsVpnService.start(activity)` without converting foreground-service/security failures into a result.
- Dart catches `PlatformException`, but native unhandled exceptions or a method result that is never completed can strand or terminate the UI.
- Manifest declares INTERNET, network state, foreground service, special-use foreground service, notifications, and a protected `VpnService`.

## Required investigation/fix

1. Trace the exact first-run sequence from setup/Open FIPS action through Dart `ensureReadyForAppAccess`, method channel, `VpnService.prepare`, activity result, service start, native startup, and UI completion. Record the strongest code-supported failure modes; do not invent a single confirmed root cause without logcat.
2. Move all Android framework calls that require/expect the activity thread onto the main thread, including consent preparation/launch.
3. Prefer the current Activity Result API over deprecated `startActivityForResult` if it integrates safely with `FlutterActivity`; register it at the correct lifecycle point and keep the coordinator testable. If retaining the old API is safer, justify it and still harden every lifecycle edge.
4. Every start/repair invocation must complete its `MethodChannel.Result` exactly once with a structured failed status on cancellation, exception, service-launch denial, activity destruction/detach, or timeout. No thrown native/framework exception may escape to crash Flutter or leave `_operationInProgress` stuck.
5. Catch and sanitize failures around reset, file setup, JNI/native prepare, JSON decoding, `VpnService.prepare`, consent activity launch/result, foreground-service launch, and readiness polling. Do not expose secrets or raw key paths in user-visible errors.
6. Make cancellation and repeated taps deterministic. Only one start may be active; a second receives `operation_in_progress`. Late/duplicate activity results must not complete another call. Destroyed coordinator/executor paths must not post into a dead activity/engine.
7. Harden `FipsVpnService` start/onCreate/onStartCommand so Android 10–16 foreground-service and notification constraints fail back to a structured FIPS failed state rather than a process crash where possible. Confirm whether POST_NOTIFICATIONS runtime permission is needed for correctness; do not request unrelated permissions.
8. Preserve existing split routing, public DNS handling, FIPS DNS, socket protection, certificate/identity behavior, and ARM64 packaging.
9. Make the setup/shell UI show a recoverable concise failure message and allow retry instead of reaching a Flutter error surface. Catch any non-`PlatformException` boundary errors that can reasonably cross the channel.
10. Add diagnostic logging that is useful in future logcat but contains no private keys, nsec, bunker/NWC material, full sensitive paths, or payloads.

## Tests/validation

- Add focused Kotlin/JVM tests by extracting lifecycle decisions behind testable interfaces/fakes as needed. Cover consent required, consent granted, cancelled, launch throws, native prepare throws/returns invalid JSON/failure, service start throws, timeout, duplicate start, duplicate/late result, and exactly-once method completion.
- Add Flutter tests proving Android channel errors (including unexpected non-PlatformException failures) become `FipsRuntimeState.failed`, operation flags clear, and retry is possible.
- Run Flutter analyze/tests, Android JVM tests, Rust/FIPS tests, and `git diff --check`.
- Build the signed ARM64 release using the existing durable signing workflow. Verify package/version, v2 signature, established certificate SHA-256, embedded `libwmapp_fips_android.so`, VPN declaration, SDK levels, and permissions.
- This is a behavioral patch after `0.1.3+4`; bump to `0.1.4+5`, add release notes, update `zapstore.yaml`, and create a versioned local Zapstore catalog snapshot with `tools/prepare_zapstore_release.py` after the signed build.
- Report APK path/hash/size, catalog release ID/path, exact validations, and remaining need for physical-device logcat/retest.

## Git/handoff

- Commit all nonignored tested state on `main` with Conventional Commits and push `origin/main`.
- Do not publish, upload, request Nostr signatures, or restart the publisher.
- Return diagnosis with confidence levels, commit/push evidence, tests, signed artifact details, and concise physical-device retest steps including how to capture logcat if it still fails.
