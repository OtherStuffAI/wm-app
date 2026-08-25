# iPhone Build And Install

## Reality Check

iPhone installs require Apple's signing flow. The easiest practical route is:

1. Build from a Mac with Xcode installed.
2. Open the iOS Runner project in Xcode.
3. Pick your Apple development team.
4. Run directly to a plugged-in iPhone.

For wider testing later, use TestFlight.

## Fastest Path: iPhone Simulator

This does not install on a physical phone, but it is the fastest iOS smoke test.

```bash
cd ~/code/wm/wmapp
git pull --ff-only
./build_ios_debug.sh simulator
```

Then open a simulator from Xcode or run directly:

```bash
cd ~/code/wm/wmapp/app
flutter devices
flutter run -d <simulator-id>
```

## Standalone Physical iPhone Install

An app that Pete can reopen from the Home Screen must be a release build. Flutter
debug builds on physical iPhones are development artifacts that expect a Flutter
tool or Xcode debugger connection; do not install a debug build as a standalone
test build.

Build the signed release artifact using the existing Xcode signing configuration:

```bash
cd ~/code/wm/wmapp
git pull --ff-only
./build_ios_release.sh
```

Install and launch it on the connected phone:

```bash
xcrun devicectl device install app \
  --device <physical-iphone-udid> \
  app/build/ios/Release-iphoneos/Runner.app
xcrun devicectl device process launch \
  --device <physical-iphone-udid> \
  com.wingmanbefree.wingmanApp
```

Keep the phone unlocked during installation and launch. Verify that the Runner
process remains present and visually confirm that the first Flutter screen
renders; installation by itself is not launch verification.

## Interactive Debugging On A Physical iPhone

Use Xcode or `flutter run` when an attached debugger is intended:

```bash
cd ~/code/wm/wmapp/app
flutter run -d <physical-iphone-udid>
```

Alternatively, open the Xcode workspace and press Run:

```bash
open app/ios/Runner.xcworkspace
```

In Xcode:

1. Select `Runner` in the project navigator.
2. Select the `Runner` target.
3. Open `Signing & Capabilities`.
4. Select your Apple development team.
5. Confirm the bundle identifier is unique for your account.
6. Connect the iPhone by USB.
7. Select the iPhone as the run destination.
8. Press Run.

The current bundle identifier is:

```text
com.wingmanbefree.wingmanApp
```

If Xcode says that identifier is already taken for your team, change it to something unique, for example:

```text
com.yourname.wingmanApp
```

## First Launch

On first launch WMApp asks for:

- the nsec to use for signing;
- a local PIN.

The nsec is encrypted into the iOS app's secure storage backed signer vault.

## Trusting A Developer Build

If iOS blocks the app after install, trust the developer profile on the iPhone:

```text
Settings -> General -> VPN & Device Management
```

Choose the developer profile and trust it.

## Current iPhone Notes

- Browser and signer flows are the main mobile test target right now.
- Desktop-only process-backed features should report unavailable on iPhone until those paths are made native.
- `build_ios_release.sh` uses the existing Xcode project signing configuration and produces the standalone device artifact.
- `build_ios_debug.sh device` remains available only for debugger-attached development; it builds with `--no-codesign` and Xcode handles signing when you run to the phone.
- If dependencies fail, run:

```bash
cd ~/code/wm/wmapp/app
flutter clean
flutter pub get
cd ios
pod install
```

## Later: TestFlight

For a build other people can install without Xcode:

1. Set the final bundle identifier.
2. Set app icons, display name, version, and build number.
3. Archive from Xcode: `Product -> Archive`.
4. Upload through Xcode Organizer.
5. Add testers in App Store Connect TestFlight.
