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

## First Launch

On first launch WMApp asks for:

- the nsec to use for signing;
- a local PIN.

The nsec is encrypted into the Android app's local secure storage backed vault.

## Current Android Notes

- The debug APK is for personal testing, not Play Store distribution.
- Android application id is currently `com.wingmanbefree.wingman_app`.
- Browser and signer flows are the main mobile test target right now.
- Desktop-only process-backed features should report unavailable on Android until the Rust/core paths are made native.

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
screenshots are currently maintained, so the first listing has no screenshots.
Zapstore publication uses `zsp` with Rick's npub to prepare unsigned events and
assets. Sign and publish those events through the running agent session's Nostr
MCP tools; never use a raw Nostr key, bunker, or browser Tier 2 fallback.
