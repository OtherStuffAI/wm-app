# Native iPhone FIPS implementation handoff

Task: `05cfb9b1-b6d8-42a7-a801-b197a00a78da`. Keep `in_progress` for manager
review. Source is on main; concurrent Tower bridge work is preserved. No
Autopilot restart, TestFlight/App Store publication, phone uninstall, identity
substitution or secret export occurred.

## Implemented

- Isolated `crates/wmapp-fips-ios` static Rust library, pinned upstream revision
  and Rust 1.98.0, independent lockfile, reproducible checked portability and
  bounded-queue patches. Android upstream/source remain unchanged.
- `FipsPacketTunnel.appex`, embedded in Runner, linked to the real library;
  public packetFlow APIs, IPv6 mesh and `.fips` DNS split routing, extension-only
  persistent Keychain identity, bounded queues/workers, stop/join and reconnect.
- Async Runner VPN consent/preferences/controller, Dart native iPhone runtime,
  setup stop/error/retry/diagnostics, exact HTTP `.fips` WApp URL preservation.
  ATS exception is scoped to `.fips` transport; exact-origin signing approval
  remains unchanged. No Tower bridge iPhone capability claim.
- Deployment/build instructions and physical acceptance checklist:
  [ios-fips.md](../deploy/ios-fips.md).

## Validation evidence

Logs are ignored local artifacts at the repository root unless otherwise noted.
They are retained for manager inspection.

| Check | Result | Evidence |
| --- | --- | --- |
| Device + both simulator Rust release libraries | PASS, XCFramework produced | `ios-fips-core-build.log` |
| iOS Rust unit suite | 8 passed; explicit network test excluded by default | `ios-fips-rust-tests.log` |
| Host live adapted core | PASS, authenticated PoC bootstrap and AAAA response through packet DNS ingress/egress and IPv6-loopback resolver | `ios-fips-live-core-test.log` |
| Swift route/DNS/MTU checks | PASS | `ios-fips-swift-tests.log` |
| Flutter analyze | No issues | `ios-fips-flutter-analyze.log` |
| Full Flutter suite | 173 passed, includes existing signing/origin and bridge regressions | `ios-fips-flutter-tests.log` |
| Focused runtime/setup suite | 42 passed | `ios-fips-targeted-tests.log` |
| iOS simulator build | PASS | `ios-fips-simulator-build.log` |
| Simulator install and process launch | PASS; PID 56063 remained present | `ios-fips-simulator-install.log`, `ios-fips-simulator-launch.log` |
| Simulator rendered UI | NOT PASSED: fixed port 47831 is owned by running macOS WMAPP | `ios-fips-simulator-runtime.log`, `build/ios-fips/simulator-launch.png` |
| Unsigned device release | PASS, 40.0 MB | `ios-fips-device-build.log` |
| Unsigned release archive | PASS, 212.5 MB; no IPA/export | `ios-fips-archive-build.log` |
| Android debug APK | PASS | `ios-fips-android-build.log` |
| Android Gradle unit tests | 493 passed across projects, including 30 WMAPP tests | `ios-fips-android-tests.log` |
| Existing Android Rust unit suite | 13 passed serially; see parallel caveat below | `ios-fips-android-rust-tests-serial.log` |
| Signed physical device build | BLOCKED on final recheck | `ios-fips-signed-device-recheck.log` |

Archive: `app/build/ios/archive/Runner.xcarchive`. Its Runner and embedded
FipsPacketTunnel are arm64 Mach-O executables, both version **0.1.6 (7)**,
minimum iOS 13.0. `codesign --verify` confirms both **unsigned**. Metadata is
in `build/ios-fips/archive-metadata.json`. `ios-fips-linked-symbols.log` confirms
all seven C ABI entry points are linked into the actual extension executable.
No physical-device binary was installed by this task.

The initial 512 KiB Tokio worker stack overflowed in the sustained live host
smoke. It was raised to 2 MiB per worker; the final library was rebuilt for all
architectures and the live authentication/DNS test then passed. Short start/stop
unit tests alone did not detect this, so the explicit live test is retained.

Manager's DNS shutdown review is addressed: stop sets a flag, disconnects the
producer, skips queued DNS requests, and joins the thread after the bounded
in-flight resolver request. Repeated start/stop asserts the live DNS worker
count returns to zero. The test verifies stable node npub/IPv6 across restarts.

The existing Android descriptor-close test failed once in the default parallel
suite because another test can reuse a closed numeric descriptor before its
`fcntl` assertion. Its unchanged code and all 13 Android Rust tests pass with
`--test-threads=1`. The original result is retained in
`ios-fips-android-rust-tests.log`; this is not reported as a parallel-suite pass.

## Device/signing reality and next steps

Peter's iPhone 15 Pro remains paired/available, identifier
`8A1C111C-F340-5C1A-B609-B022E9B7D832`. Pete's latest instruction authorizes
building/deploying to it; signing was rechecked after independent builds.

September 6's account-restoration handoff records successful distribution
export and later signed development installs. Those historical successes were
read and do not override today's Xcode result: **No Accounts**, and current
Runner and extension profiles do not contain the Network Extensions capability
or `com.apple.developer.networking.networkextension` entitlement. Existing team
`N5DRUM6S94` and bundle IDs are preserved. Restore authorized Xcode account access
and provision both explicit App IDs with Packet Tunnel capability, then rebuild
signed and install in place using the deployment commands. No credential
fallback or speculative account/team change was attempted.

Manager should distinguish these unperformed physical checks: normal VPN
consent/refusal; authenticated mesh and exact `.fips` WApp/Nostr login; ordinary
HTTPS/DNS during VPN; screen lock/background; Wi-Fi/cellular/offline recovery;
repeated stop/restart and persisted Keychain identity; existing-VPN interaction;
real extension peak memory/battery. Host core tests, mocked Flutter tests and
simulator build/install do not substitute for these checks.

The optional end-to-end probe is explicitly unavailable on iPhone; users may
continue to the exact WApp URL. The public bootstrap is PoC only. Desktop WMAPP
was left running to preserve concurrent bridge work, so simulator visual startup
requires coordination over port 47831. No browser-origin workaround was added.

## Commit and concurrent-work record

The iOS implementation is committed in **`9c4caa9`**
(`build(flightdeck): bundle paired FIPS transport build 1915`). During this
worker's reviewed staging/commit window, the concurrent bundle worker committed
the shared index, including all 30 staged iOS implementation/documentation
files. My following feature commit had nothing left to commit. History was
preserved; no amend/reset or duplicate feature commit was attempted.

Bridge commits `c878c37` and `423e9c5` are preserved. The final Flutter tests and
unsigned archive were repeated after `9c4caa9` so the recorded final archive
includes its Flight Deck 1915 bundle. An evidence-only follow-up commit records
this handoff. The earlier simulator install/process evidence predates that
bundle refresh and covers the same finalized native iOS runtime. Pre-existing
`docs/fips-tower-bridge-handoff-2026-09-09.md` and `tools/fips_bridge/` remain
untouched and untracked for their reviewer owner.

Final archived extension SHA-256: `f098b8f9b959ce76d9bbfae5cbc68091a90413d37495b2887ff00e4ee6e916bd`.
Final archived Runner SHA-256: `7b781977a0d0a8e02d75e7c3259e1435263ff17b137374383b284f74300b97de`.
Archived Flight Deck `version.json` matches the committed 1915 bundle byte for byte.
