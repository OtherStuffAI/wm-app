# Mac Build And Install

## Fastest Path

Use the root helper script. It pulls the latest `main`, fetches Flutter dependencies, builds the macOS debug app, and launches it.

```bash
cd ~/code/wm/wmapp
git pull --ff-only
./build_runapp.sh
```

After the first successful build, relaunch the existing app without rebuilding:

```bash
cd ~/code/wm/wmapp
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
cd ~/code/wm/wmapp/app
flutter pub get
flutter build macos --debug
open build/macos/Build/Products/Debug/wingman_app.app
```

The Xcode build bundles the pinned FIPS v0.5.0 macOS packages for both arm64
and x86_64. `tools/prepare_fips_macos.sh` downloads them from the upstream
release into an ignored cache and refuses a checksum mismatch. Generated
binaries are not committed.

## FIPS WApp PoC

After unlocking WMapp, open **Setup → FIPS transport**:

1. Choose **Open FIPS app** and paste the exact
   `http://<autopilot-npub>.fips:<port>/` URL or matching JSON descriptor.
   If the bundled runtime has not been activated, or its Wingman mesh setup is
   outdated, WMapp performs the repair automatically and macOS requests one
   administrator authorization. The separate **Install or repair** control
   remains available for diagnostics and explicit repair.
2. Activation preserves any existing FIPS key and unrelated configuration. The
   bundled helper transactionally enables persistent machine identity, Nostr
   rendezvous and UDP advertising under the `wingman-fips-poc-v1` application
   namespace. Scoped LAN rendezvous is also enabled so two Wingman machines on
   the same physical network do not depend on router NAT hairpin support. For
   this explicit same-LAN PoC, RFC1918/ULA candidates are included only inside
   encrypted Nostr traversal offers. An initial config backup is kept alongside
   `fips.yaml`.
3. The optional diagnostic probe is off by default and does not establish a
   route. Approve trust for the exact origin; WMapp never trusts `*.fips`.

FIPS machine identity is separate from the WMapp user signer. No FIPS private
key is copied into Flutter settings, command arguments, or logs.

The upstream v0.5.0 `.pkg` files are not signed and macOS `spctl` reports `no
usable signature`. This is acceptable only for this local PoC. Production
distribution is blocked until the FIPS packages are rebuilt, Developer ID
Installer signed, and notarized as part of the Wingman release process. Do not
disable Gatekeeper to work around this.

## First Launch

On first launch WMApp asks for:

- the nsec to use for signing;
- a local PIN.

The nsec is encrypted into the app's local signer vault. Do not put signer keys in `.env.local`.

## Updating

```bash
cd ~/code/wm/wmapp
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
