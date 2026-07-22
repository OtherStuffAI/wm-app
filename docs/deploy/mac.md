# Mac Build And Install

## Fastest Path

Use the root helper script. It pulls the latest `main`, fetches Flutter dependencies, builds the macOS debug app, and launches it.

```bash
cd ~/code/wm-app
git pull --ff-only
./build_runapp.sh
```

After the first successful build, relaunch the existing app without rebuilding:

```bash
cd ~/code/wm-app
./runapp.sh
```

Logs go to:

```text
$TMPDIR/wingman_app.log
```

## Fresh Mac Setup

Install Flutter and Xcode command line tooling first:

```bash
flutter --disable-analytics
xcode-select --install
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept
flutter doctor
```

If `flutter doctor` says CocoaPods is missing, install it before iOS work. macOS debug builds usually do not need CocoaPods unless a plugin path requires it.

## Manual Build

```bash
cd ~/code/wm-app/app
flutter pub get
flutter build macos --debug
open build/macos/Build/Products/Debug/wingman_app.app
```

## First Launch

On first launch WMApp asks for:

- the nsec to use for signing;
- a local PIN.

The nsec is encrypted into the app's local signer vault. Do not put signer keys in `.env.local`.

## Updating

```bash
cd ~/code/wm-app
git pull --ff-only
./build_runapp.sh
```

Set `WMAPP_SKIP_CLEAN=1` if you want a faster rebuild:

```bash
WMAPP_SKIP_CLEAN=1 ./build_runapp.sh
```

## Current Notes

- The macOS debug app is unsigned development output.
- `runapp.sh` launches the built app executable directly and sources `.env.local` for development-only overrides.
- Finder launch can work, but `runapp.sh` is the reliable path because it sets `WMAPP_REPO_DIR`.
- macFUSE is only needed for the future live Drive mount path. Browser/signer testing does not require it.

