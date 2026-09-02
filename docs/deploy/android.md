# Android Tablet Build And Install

## Fastest Path: Debug APK

Build the debug APK from the repo root:

```bash
cd ~/code/wm/wmapp
git pull --ff-only
./build_android_apk.sh
```

The APK is written to:

```text
app/build/app/outputs/flutter-apk/app-debug.apk
```

Send that APK to the Android tablet and install it. The simplest options are:

- AirDrop/nearby share equivalent, cloud drive, or USB file transfer, then open the APK on the tablet.
- `adb install` over USB if Android platform tools are installed.

```bash
adb devices
adb install -r app/build/app/outputs/flutter-apk/app-debug.apk
```

On the tablet, Android may ask you to allow installs from the app you used to open the APK.

## Fastest Developer Loop: Run Directly On Tablet

Enable Developer Options and USB debugging on the tablet, connect it by USB, then:

```bash
cd ~/code/wm/wmapp/app
flutter devices
flutter run -d <android-device-id>
```

This is usually the easiest way to see logs while testing.

## Android Tooling Setup

Install Android Studio or the Android command line tools, then ensure:

```bash
flutter doctor
```

shows an Android toolchain. If it reports missing command line tools, install them through Android Studio's SDK Manager or the standalone command line tools package.

The embedded FIPS library also requires a stable Rust toolchain, the ARM64
Android standard library, and `cargo-ndk`:

```bash
rustup target add aarch64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
```

The supported `build_android_apk.sh` and release build invoke the Gradle native
task automatically. It builds official FIPS `v0.5.0` from the Git commit pinned
in `Cargo.lock` and packages only the ARM64 JNI library. Generated `jniLibs`
and Cargo caches are ignored and may be deleted safely; no identity or secret
is generated at build time.

## First Launch

On first launch WMApp asks for:

- the nsec to use for signing;
- a local PIN.

The nsec is encrypted into the Android app's local secure storage backed vault.

## Current Android Notes

- The debug APK is for personal testing, not Play Store distribution.
- Android application id is currently `com.wingmanbefree.wingman_app`.
- Browser and signer flows are the main mobile test target right now.
- FIPS is embedded in WM-App; no separate FIPS app or daemon is installed.
- The first exact `.fips` app open asks for Android VPN consent. Android may
  show this again after consent is revoked or the app is reinstalled.
- A persistent foreground-service notification is posted while the FIPS VPN is
  active (Android 13+ may require notification permission to show it in the
  notification drawer). Stopping or repairing FIPS tears down both the Rust
  node and the app-owned TUN.
- Android permits one active VPN per user/profile. Starting WM-App's FIPS VPN
  replaces, or can be blocked by, another VPN. Public destination traffic remains
  outside WM-App's split tunnel; only `fd00::/8` and `10.1.1.1/32` are routed
  into it. DNS is separate: Android sends system queries to the advertised
  `10.1.1.1`, where WM-App sends all-`.fips` questions only to the embedded FIPS
  resolver and sends all-public questions through Android's resolver on the
  selected non-VPN underlying network. Mixed questions receive local `REFUSED`.
- Safe public-DNS forwarding uses `DnsResolver.rawQuery`, which is available on
  Android 10 (API 29) and newer. On older Android versions, or when no
  internet-capable non-VPN network is available at startup, FIPS fails closed
  before it can become the device DNS path.
- WM-App itself is intentionally not excluded from the VPN. Every UDP socket
  published by FIPS is protected with `VpnService.protect(fd)` before packet
  loops begin, while WebView mesh traffic continues through the TUN.
- The FIPS machine key is app-private, mode `0600`, and separate from the
  WM-App Nostr signer. Clearing app storage replaces it; upgrades preserve it.

## FIPS Device Validation

As of 2026-09-01 the ARM64 APK, host native tests, Kotlin JVM tests, Flutter
analysis, and the complete Flutter suite pass. No Android device or emulator
was connected for this implementation pass, so VPN consent, notification,
bootstrap connectivity, and a real exact `.fips` WebView request remain device
validation items.

There is one specifically isolated browser risk: Android System WebView is
Chromium-based and Chromium is known to suppress AAAA resolution on some
ULA-only VPNs. The native path is complete (split TUN, official DNS proxy,
checksummed reply, and unchanged exact hostname/origin), but this environment
cannot truthfully establish whether the installed device WebView accepts the
AAAA answer. Test on ARM64 hardware by opening the exact Autopilot-provided
`http://<npub>.fips:<port>/` URL and capture `adb logcat` plus the WebView error,
if any. Do not replace the hostname with an IPv6 literal: that changes the
origin and invalidates exact-origin NIP-07/NIP-98 trust. If Chromium suppresses
the answer, the outstanding work is a browser-resolution strategy (potentially
NAT46 after a separate safety design), not the FIPS native interface.

After granting VPN consent once, run the device-only regression with the exact
Autopilot WApp URL and a known public hostname:

```bash
cd app/android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.fipsUrl='http://<npub>.fips:<port>/' \
  -Pandroid.testInstrumentationRunnerArguments.publicDnsName='example.com'
```

`ChromiumExactFipsTest` separately resolves `publicDnsName` while the FIPS VPN is
running, then starts the embedded node, awaits the authenticated bootstrap,
loads the unchanged `.fips` hostname in Android System WebView, fails on a
main-frame DNS/network error or bounded timeout, and verifies that the final
WebView scheme, host, and port still match the exact `.fips` origin. Both tests
always tear down the VPN, and the browser test also tears down its WebView,
including after an assertion failure. The browser test intentionally does not
substitute an IPv6 literal. A passing result still depends on the installed
System WebView accepting the FIPS ULA/AAAA answer; that Chromium behavior cannot
be established by compilation or host tests.

The design follows Android's documented contracts: `Builder.addDnsServer()`
adds a DNS server to the VPN (and does not say that public names bypass it),
whereas `Builder.addRoute()` controls destination routes. `DnsResolver.rawQuery`
accepts a specific `Network`, and `LinkProperties.isPrivateDnsActive()` warns
that applications must not send unencrypted DNS while Private DNS is active.
Consequently WM-App delegates public packets to Android's network-scoped resolver
instead of choosing or directly contacting a public DNS server:

- https://developer.android.com/reference/android/net/VpnService.Builder#addDnsServer(java.net.InetAddress)
- https://developer.android.com/reference/android/net/VpnService.Builder#addRoute(java.net.InetAddress,int)
- https://developer.android.com/reference/android/net/DnsResolver#rawQuery(android.net.Network,byte[],int,java.util.concurrent.Executor,android.os.CancellationSignal,android.net.DnsResolver.Callback)
- https://developer.android.com/reference/android/net/LinkProperties#isPrivateDnsActive()

## Shareable Release APK

Release builds use a durable keystore outside git. On the release Mac, create it
once and store its randomly generated password in macOS Keychain:

```bash
cd ~/code/wm/wmapp
./tools/setup_android_release_signing.sh
```

The default keystore is `~/.config/wmapp/android-release.jks`, with mode `0600`.
The password is held by the `wmapp-android-release` Keychain item and is never
written into this repository. Back up both the keystore and its password using
the operator's secret-backup process; losing either prevents compatible updates.

Build and run the repository-native checks:

```bash
./build_android_release.sh
```

The script retrieves the password from Keychain, exports it only to the build
process, runs dependency resolution, analysis, tests, and an arm64 release
build, then prints the APK SHA-256. CI or non-macOS operators may instead set:

```text
WMAPP_ANDROID_KEYSTORE
WMAPP_ANDROID_STORE_PASSWORD
WMAPP_ANDROID_KEY_ALIAS
WMAPP_ANDROID_KEY_PASSWORD
```

Missing release-signing values fail the Gradle release build explicitly. Debug
builds remain separate and continue to use Android's debug certificate.

The release APK is written to:

```text
app/build/app/outputs/flutter-apk/app-release.apk
```

Verify its metadata and certificate before publishing:

```bash
zsp utils extract-apk app/build/app/outputs/flutter-apk/app-release.apk
zsp publish --check zapstore.yaml
JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}" \
  "${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}/build-tools/36.1.0/apksigner" \
  verify --verbose --print-certs app/build/app/outputs/flutter-apk/app-release.apk
```

`zapstore.yaml` intentionally uses the APK-extracted launcher icon. No release
screenshots are currently maintained, so the listing has no screenshots. The
canonical handoff inputs are `zapstore.yaml`, `app-release.apk`, the extracted
`app-release_icon.png`, and the versioned release-notes file.

Publication is an owner-only action in the WMAPP Zapstore Publisher WApp. Pete
reviews the pinned artifact hashes there and approves the publication with his
NIP-07 browser signature. Do not ask Rick, a backend, an agent, or an MCP route
to sign or publish the release. Never enter, export, copy, or expose a raw Nostr
private key; there is no raw-key fallback. Preparing and validating these local
inputs does not authorize publication or a restart of the publisher WApp.
