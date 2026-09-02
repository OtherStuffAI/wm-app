# Android FIPS diagnostics export and 0.1.5 release

## User report and goal

Pete retested the signed WM-App `0.1.4+5` build on a Daylight Android tablet. The same failure occurs when the embedded FIPS VPN path loads/starts. He needs an in-app way to export useful crash/startup diagnostics, and has asked to reissue WM-App as `0.1.5`.

Implement a privacy-safe diagnostics journal and export flow that remains usable after a failed FIPS start, then produce and verify signed Android release `0.1.5+6`. Do not claim the tablet-specific root cause is fixed without the exported device evidence. Do not publish to Zapstore, request Nostr signatures, or restart any registered app unless Pete separately authorizes that action.

## Repository and working rules

- Work in `/Users/mini/code/wm/wmapp` on `main` from `6131a68` or later.
- Preserve concurrent changes. Commit all nonignored tested state with Conventional Commits and push `origin/main`.
- Existing Android FIPS lifecycle hardening and privacy-safe logcat tags are in `cf70f7b`; the durable Rust build fix is `6131a68`.
- Existing release catalog tooling and durable signing workflow must be reused.
- Never log/export private keys, nsec, raw Nostr events, NIP-98 tokens, bunker/NWC/capability material, identity/certificate private material, full sensitive file paths, request/response payloads, browsing history, arbitrary WebView URLs, or a broad Android bug report.

## Required design and behavior

1. Do not attempt to read system logcat from the app. Modern Android apps cannot reliably read the system log buffer without privileged permissions. Instead, add an app-owned bounded diagnostic journal shared by the Android activity/coordinator/VPN service and the Flutter FIPS boundary where useful.
2. Record structured, allowlisted events only: UTC timestamp, release version/build, platform/API and device model/manufacturer where safe, event code, lifecycle phase, FIPS status/error code, consent/service state, and exception class (never exception message/stack trace unless it is demonstrably sanitized). Include enough events to distinguish native preparation, consent launch/result, foreground-service promotion, VPN establishment, native start/readiness, cancellation, timeout, activity destruction, and Dart boundary/UI retry.
3. Journal must be bounded and durable across process/app restarts so a crash does not erase the evidence. Use app-private storage; cap by record count and/or byte size; atomic/serialized writes; tolerate corrupt/truncated data; and avoid blocking the Android main thread. Add a clear/reset operation.
4. Add a native export operation through the existing FIPS MethodChannel. Create a human-readable UTF-8 text or JSON diagnostics file with a prominent privacy/version header and the bounded records. Export through Android's user-controlled document/share surface with a safe filename such as `wmapp-fips-diagnostics-<UTC>.txt`; do not require storage permission. Handle no activity, cancelled export, provider/intent failure, lifecycle destruction, and duplicate taps as structured recoverable outcomes.
5. Make export accessible in Flutter whenever Android embedded FIPS is supported, especially directly on the FIPS failed/error UI and setup screen. The user must not need FIPS to be running or Tower/WebView access to export. Show concise progress/success/cancel/failure feedback. Keep retry/install available.
6. If a truly uncaught Android process crash cannot be journaled at the final instruction, ensure the immediately preceding lifecycle events persist synchronously enough to survive it. Do not install a global uncaught-exception handler that captures arbitrary secrets or stack traces.
7. Preserve routing, DNS, VPN service behavior, FIPS identity/certificates, authentication/allowlists, and all other platforms. Unsupported platforms should not show a broken export control.
8. Document what the exported file contains, what it deliberately excludes, retention/cap, clearing behavior, and how Pete should attach it for diagnosis.

## Testing and validation

- Extract testable Kotlin components/interfaces and add JVM tests for bounded retention, serialization/redaction invariants, corrupt-file recovery, concurrent/duplicate events, export success/cancel/failure, missing activity, and persistence across journal re-instantiation.
- Add Flutter tests covering export availability on Android failed state, method-channel success/cancel/error/unexpected error, duplicate taps, user feedback, and retry remaining usable.
- Add a secret-leak regression test using representative `nsec`, Authorization/NIP-98, bunker/NWC/capability strings, sensitive path and URL/payload inputs; assert none appear in exported output.
- Run Flutter analyze/tests, Android JVM tests, Rust/FIPS tests, and `git diff --check`.
- Bump `app/pubspec.yaml` to `0.1.5+6`; add `docs/release-notes/0.1.5.md`; update `zapstore.yaml`.
- Build the signed ARM64 APK using `build_android_release.sh` and the established keystore workflow. Verify package/version, min/target SDK, APK v2 signature, established certificate SHA-256, embedded `libwmapp_fips_android.so`, VPN service declaration, and expected permissions.
- Create `app/build/zapstore-releases/0.1.5+6/release.json` using `tools/prepare_zapstore_release.py`; verify its APK hash equals the built APK.

## Handoff

Report:

- exact UI route Pete should use to export after reproducing on the Daylight tablet;
- file contents/privacy/retention behavior;
- tests and build verification;
- APK path, size, SHA-256 and certificate digest;
- catalog release ID/path;
- commits and push evidence;
- the remaining physical-tablet retest and request that Pete attach the exported diagnostics file.

## Takeover status

The first dispatched turn stalled after creating a coherent partial implementation. Treat the live worktree as the source of truth and continue it; do not discard or overwrite it. At takeover time the journal/export state machine, coordinator/service instrumentation, Flutter service API, Setup controls, and initial Flutter service tests existed, but the required Kotlin journal/export tests, complete Flutter UI tests, release/version updates, validation, signed build, catalog snapshot, commits, and push were not yet complete. Review the partial design before extending it, especially its exactly-once export lifecycle and allowlist-only privacy boundary.
