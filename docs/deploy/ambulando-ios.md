# Ambulando for iPhone

Ambulando embeds the validated Sol web application in the existing Flutter /
WKWebView native shell. It uses the actual product UI and Confluence assets;
it is not a SwiftUI rewrite. Native signer custody, explicit approval and the
single generic `window.fipsTransport` provider remain shared with WMapp.

The `ambulando` Xcode scheme uses Debug/Profile/Release-ambulando configurations
of the existing Runner and FipsPacketTunnel targets. It has separate app identity
`com.wingmanbefree.ambulando`, extension identity
`com.wingmanbefree.ambulando.FipsPacketTunnel`, display name, launch screen and
icon. Runner's default configurations and bundle identifiers remain compatible.
Flutter selects the product from `FLUTTER_APP_FLAVOR`; use `--flavor ambulando`.
The bundled app opens at the fixed `http://127.0.0.1:47832/` origin. Native WebKit
permits that local transport origin only in the Ambulando bundle; default WMapp
keeps port 47831. Never reuse another process's listener or select a random port.

The UI opens with native browser controls hidden. Edge gestures expose native
controls and the drawer for identity, signer, transport setup and reload. Local
web storage remains tied to this app/origin. An existing browser's account,
workspace configuration, device grant or keys do not automatically transfer.
Create/import/unlock the native identity through the existing user interface;
never extract a key from another application.

## Build and provenance

Confirm Sol's final source checkpoint and successful frontend validation before
packaging. Generated frontend bytes stay ignored. The packaging tool hashes every
relative file path and SHA-256 in canonical sorted compact JSON, then hashes that
JSON. It rejects symlinks, unknown asset directories, changed source/copy bytes
and a digest mismatch. It does not rebuild or edit Sol. Review new Sol asset
directories in `app/pubspec.yaml` before packaging. Assets are flavor-scoped so
ordinary WMapp builds do not require or package Sol.

```sh
python3 tools/ios/package_ambulando.py <validated-sol-dist> --inspect
./build_ios_ambulando.sh <validated-sol-dist> <approved-tree-sha256> \
  --release --build-name <version> --build-number <build>
# Compile-only alternatives:
./build_ios_ambulando.sh <validated-sol-dist> <approved-tree-sha256> \
  --simulator --debug --build-name <version> --build-number <build>
./build_ios_ambulando.sh <validated-sol-dist> <approved-tree-sha256> \
  --release --no-codesign --build-name <version> --build-number <build>
```

`tools/ios/configure_ambulando.py` idempotently adds the flavor configuration clones;
checked-in project changes are buildable without running it. When changing a
shared native build setting, review both the default and branded configurations.
The icon and launch raster resize the existing ivory-backed Sol favicon while
preserving its geometry and aspect ratio. The underlying extracted raster mark
is provisional; a future approved vector master should replace both together.

Signing requires the existing authorized Apple team account in Xcode and explicit
Network Extensions provisioning for both Ambulando identifiers. A wildcard
profile or installed signing certificate alone is insufficient. Follow
[iOS FIPS](ios-fips.md) for capability and transport details. When signing is
blocked, sign into the authorized account under Xcode Settings → Accounts, enable
Network Extensions for both App IDs, and download/create matching profiles.
Reconnect/unlock the already-paired iPhone, keep Developer Mode enabled, then:

```sh
xcrun devicectl device install app --device <paired-device> \
  app/build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <paired-device> \
  com.wingmanbefree.ambulando
```

Only run these commands with a successfully signed device build. Simulator
installation and unsigned compilation are not physical device delivery.

## Background and recovery

There are no added audio, location, fetch, processing or notification background
modes. WebKit JavaScript, sync and uploads may be suspended by iOS. No indefinite
background sync, push delivery or voice recording is promised. A user-enabled
FIPS packet tunnel is independently managed by iOS and can remain connected;
backgrounding Runner neither stops it nor gives the web application execution
rights. Stop it explicitly in native Setup when no longer needed.

On every non-resumed Flutter lifecycle transition, the shell synchronously
invalidates signing epochs and transport grants, closes native requests/sockets,
and revokes diagnostics. JavaScript revocation rejects pending signer/transport
requests, ends streams and closes worker ports. Signer requests also expire after
30 seconds. The generic `wingman-fips-transport-revoked` event follows transport
cleanup so consumers can invalidate their handles. Revocation remains effective
natively even if WebKit suspends before the JavaScript callback executes.

On resume, the shell checks the live main-frame URL and native channel policy,
injects fresh document-scoped providers and emits the standard foreground
`focus` event after both providers finish. Existing local state and drafts are
preserved; old handles and pending approvals cannot revive. Sol owns reconnection,
worker reattachment, service-health verification, cursor recovery and sync above
the transport. Remembered exact policy decisions can approve a new matching
handle; signatures are always fresh. WebKit process termination revokes access;
use the visible native reload control if the page cannot recover.

## Repeatable verification

```sh
cd app
flutter analyze
flutter test
flutter test --flavor ambulando test/ambulando_product_test.dart
# On a booted iPhone simulator (or authorized connected physical device):
flutter test --flavor ambulando -d <device> integration_test/ambulando_native_smoke_test.dart
cd ..
xcrun swiftc \
  packages/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview/WingmanScriptMessagePolicy.swift \
  tools/tests/fips_bundled_origin.swift -o <ignored-evidence-directory>/origin-check
<ignored-evidence-directory>/origin-check
./tools/ios/test_native.sh
```

Verify the branded login and authenticated workspace, navigation, keyboard and
safe areas, HTTPS loads, endpoint consent, fresh signing, foreground/offline
recovery, lock/unlock, Wi-Fi/cellular transitions, tunnel stop/restart, and exact
identity continuity on the physical iPhone. Test rejected and late approvals too.
Keep device records, screenshots, exact hashes and operational outcomes private
under ignored `tmp/docs/handoffs/`. Record which checks were actually performed;
source tests cannot establish iPhone network routing or battery behavior.
