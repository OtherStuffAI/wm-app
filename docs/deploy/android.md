# Android Tablet Build And Install

## Fastest Path: Debug APK

Build the debug APK from the repo root:

```bash
cd ~/code/wm-app
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
cd ~/code/wm-app/app
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

## Later: Shareable Release APK

For a non-debug APK, add proper Android signing config and build:

```bash
cd ~/code/wm-app/app
flutter build apk --release
```

Do not use a release APK for shared testing until the signing key and package identity are intentionally set.

