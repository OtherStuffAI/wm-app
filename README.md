# Nostr Browser

![Nostr Browser Wayfinder logo: a purple wing within a compass ring with an orange northeast arrow](public/logo.png)

Nostr Browser (NBrowser for short) opens multiple Nostr apps and mini apps with a
local signer and FIPS connectivity. Browse ordinary HTTP/HTTPS pages in tabs,
save web apps in the new-tab launcher, and open `.fips` WApps through the mesh.
Here, mini apps are web apps opened inside the browser; Nostr Browser does not provide a
separate native mini-app runtime.

The browser injects `window.nostr` so compatible apps can request a public key
and approved NIP-07 event signatures without receiving the private key. NIP-98
request signing is also available with origin and operation policy checks.
Your identity is held in a PIN-encrypted local vault, and signer approvals can
be reviewed and revoked. Different apps share the selected identity while
permissions remain scoped to the requesting app and operation.

FIPS service access from an HTTPS or approved local app uses the generic
`window.fipsTransport` capability with explicit transport consent, pinned
endpoints and lifecycle revocation. Signing approval is separate from transport
consent. Direct `.fips` navigation is its own browser route. Built-in Flight Deck
and optional Tower-backed Drive integrate with these foundations; Tower remains
the authority for its workspace and file records.

## Current functionality and platform limits

The native browser, local signer, saved-app launcher and FIPS integration are
implemented, rather than a product plan. The WebView integration targets macOS,
Android and iOS. macOS/Linux FIPS use a bundled system daemon; Android/iOS use
embedded runtimes with platform VPN consent. Linux packaging and the native core
exist, but the declared WebView plugins do not establish Linux browser support.
The Flutter web target currently cannot compile because the native FIPS runtime
imports `dart:ffi` unconditionally. The browser favicon and manifest assets are
available under `app/web/` and `public/`; a hosted web page cannot provide this
application's native signer, embedded browser or FIPS runtime.

NIP-07 event signing and NIP-98 signing use Dart on native desktop/mobile.
NIP-44 encryption/decryption, Drive sync, device registration, channel validation
and local mounting still require the desktop Rust core process. Mobile reports
these process-backed operations as unavailable. NIP-04 is not implemented;
Windows is not a generated Flutter application target in this repository.
Platform folders and build commands below describe available source/build
paths, not a claim of validation on every device or operating system.

The implementation can be inspected in the [browser and signer](app/lib/src/features/browser/browser_screen.dart),
[saved-app launcher](app/lib/src/features/browser/browser_app_selector.dart),
[FIPS provider](app/lib/src/features/browser/grasp_fips_bridge_script.dart),
[platform runtime](app/lib/src/core/fips_runtime_service.dart), and
[native core bridge](app/lib/src/core/native_core_bridge.dart).

## Repository Checkout

Active development uses the private repository
`https://github.com/OtherStuffAI/wm-app` checked out at
`~/code/wm/wmapp`.

Every root `build_*.sh` script downloads the latest `main` from
`https://github.com/OtherStuffAI/wm-flightdeck.git`, installs its locked
dependencies, builds and verifies Flight Deck, then bundles it before building
Flutter. The bundled output in `app/assets/flightdeck` is generated locally and
ignored by Git; it should not be committed to this repository. Git, Bun,
Node.js, rsync and network access are required; private repository access uses
your normal Git credentials.

The clone, dependencies and temporary dependency caches are removed on success,
failure or interruption. Only the bundled output in `app/assets/flightdeck`
is retained. Refreshes preserve the committed Flight Deck version number and log
the source commit. The public Flight Deck app identifier is supplied by default;
`FLIGHT_DECK_PG_APP_NPUB` can override it. A download, install, build or verification
failure stops the app build instead of silently using an old bundle.

For local development, `FLIGHT_DECK_DIR=/path/to/flightdeck ./build_runapp.sh`
builds that checkout instead, using its existing dependencies and configuration.
This explicit override is never deleted or pulled. To manually reuse its built
assets, run `FLIGHT_DECK_DIR=/path/to/flightdeck ./tools/update_flightdeck_bundle.sh --use-existing-dist`.

`runapp.sh` only launches an existing app. Direct `flutter build` commands still
use whichever assets are already bundled.

The former `~/code/wingmanbefree/wm-app` checkout is a legacy checkpoint and
should not be used for new changes.

## Native Core

The first Rust core crate lives at `crates/wmapp-core`.

Useful commands:

```bash
cargo test
cargo run --bin wmapp-core -- status
cargo run --bin wmapp-core -- device generate --show-secret
cargo run --bin wmapp-core -- sign-nip98 --secret <hex-or-nsec> --method POST --url https://tower.example/api --body '{"hello":"wingman"}'
```

Tower read commands use NIP-98 signing. They accept flags or environment:

```bash
export TOWER_URL="http://127.0.0.1:3100"
export FLIGHTDECK_APP_NPUB="npub1hd37reqgfcnz3pvzj4grknd2nkzc94p9ercmunrxx22razr2rfxsw6dns5"
export WINGMAN_NSEC="<hex-or-nsec-device-or-agent-key>"

cargo run --bin wmapp-core -- status --workspace-id <workspace-id>
cargo run --bin wmapp-core -- list-files --workspace-id <workspace-id> --channel-id <channel-id>
cargo run --bin wmapp-core -- sync --once --workspace-id <workspace-id> --channel-id <channel-id>
cargo run --bin wmapp-core -- list-items --workspace-id <workspace-id>
cargo run --bin wmapp-core -- cat --workspace-id <workspace-id> <file-id> --output /tmp/file.out
cargo run --bin wmapp-core -- pin <file-id>
cargo run --bin wmapp-core -- evict <file-id> --force
cargo run --bin wmapp-core -- mount --dry-run --workspace-id <workspace-id> --mountpoint ~/FlightDeck
cargo run --bin wmapp-core -- mount --workspace-id <workspace-id> --mountpoint ~/FlightDeck
```

The `mount --dry-run` command prints the read-only Drive tree that the FUSE/macFUSE adapter exposes. The non-dry-run mount is a foreground read-only kernel mount: keep the process running and unmount the mountpoint from another shell. Mounted file reads use the local cache first and hydrate from Tower on cache miss when Tower auth is configured. On macOS the CLI preflights macFUSE and fails clearly if the kernel device cannot be loaded or approved.

## Flutter Shell

Right-click a browser tab to choose its colour or set a prefix. Enter `WORK`
to display `WORK: Page title`; the page title continues to update as you browse.
Choose **Default colour** or save an empty prefix to remove the customization.
These settings are saved with your tabs for the current identity.

The Flutter shell lives at `app/`. It defines setup, Drive, browser, and status screens plus a `NativeCoreBridge` local-process bridge to the existing Rust core.

The current desktop build can register a device through Tower, validate a configured channel, trigger one-shot sync, list local Drive metadata, and inject a `window.nostr` bridge into WebView pages. Device key generation/import, NIP-07 `signEvent`, and NIP-98 signing are implemented in Dart so they work in the Flutter app on desktop and mobile without shelling out to Rust.

## Where your Nostr private key is stored

Nostr Browser does **not** put your raw `nsec` directly in Keychain, Android
Keystore, or a Linux keyring. Instead, it uses a two-part local vault:

- Your raw `nsec` is encrypted with AES-256-GCM. The ciphertext and public
  information such as your `npub`, together with the salt, nonce, and other
  data needed to unlock the vault, are stored in the app's normal preferences.
- A 256-bit vault key is derived with PBKDF2-HMAC-SHA256 from your PIN and a
  random 32-byte per-install secret, using a separate random salt. The current
  code uses 210,000 PBKDF2 iterations.
- Only the random per-install secret is placed in the operating system's secure
  storage. The PIN is never stored. Your clear `nsec` exists only in app memory
  while the signer is unlocked.

The secure-storage location for that random per-install secret depends on your
device:

- **iPhone and iPad:** Apple Keychain. Nostr Browser uses the package defaults: the
  item is accessible while the device is unlocked and iCloud Keychain
  synchronisation is off.
- **Android:** AES-GCM encrypted storage. Under the package defaults, its data
  encryption key is wrapped with RSA-OAEP using a wrapping key protected by
  Android Keystore. This is the extra protection for the random per-install
  secret, not storage of the raw `nsec` itself.
- **macOS:** Apple Keychain. Nostr Browser uses an app-specific secure-storage
  service name in the macOS data-protection keychain. Builds from before
  0.1.6 used the plugin's generic traditional-keychain service name; the app
  copies that legacy device secret forward on the next successful unlock.
- **Linux:** `libsecret`, which talks to the desktop Secret Service—normally
  GNOME Keyring or KDE KWallet.

These are the settings in the current app. Nostr Browser does not currently request
Secure Enclave protection or native biometric/user-presence enforcement. It
also does not promise that vault data will survive uninstalling and
reinstalling the app, or that secure-storage keys are hardware-backed on every
device.

After upgrading from an older macOS build, unlock the signer once before
removing any legacy `flutter_secure_storage_service` Keychain item. Cleanup is
optional after a successful unlock because Nostr Browser reads the migrated
app-specific item first.

The browser has an address bar for loading arbitrary `http` and
`https` websites. The injected NIP-07 surface supports `getPublicKey`,
prompt-backed `signEvent`, empty `getRelays`, and prompt-backed
`nip44.encrypt`/`nip44.decrypt` on desktop through `wmapp-core`. NIP-44 is not
mobile-native yet. NIP-04 still returns explicit not-yet-supported errors.
NIP-98 remains more restrictive: both the loaded
WebView origin and the requested NIP-98 target origin must be trusted before
the native approval prompt appears. Remembered NIP-98 approvals and signer
audit entries are persisted locally, and the Signer tab can revoke approvals or
clear the audit log. A static signer test page is served from the Flutter web
build at `/signer-test.html` for native WebView/manual bridge checks.

Fresh dev builds default to Pete's Wingman App channel and a browser home page
with Flight Deck and Rick Autopilot bookmarks:

- Tower URL: `http://127.0.0.1:3100`
- Flight Deck URL: `https://near-tea-crab.rick.runwingman.com`
- Rick Autopilot URL: `https://rick.runwingman.com`
- Trusted origins: local Tower/dev Flight Deck, `kind-net-duck.rick.runwingman.com`, `near-tea-crab.rick.runwingman.com`, and `rick.runwingman.com`

On first launch, browsing is available without Tower configuration. Use the
avatar menu’s **Create identity / Import key** action to generate or import a
Nostr identity and choose a PIN for the local signer vault. An existing vault
requires its PIN before saved browser tabs open and authenticate.

Do not put signer nsecs in `.env.local` anymore. That file is only for local
development overrides such as `WMAPP_CORE_BIN`:

```bash
cd ~/code/wm/wmapp
cp .env.local.example .env.local
$EDITOR .env.local
```

Then launch through the root helper scripts:

```bash
./build_runapp.sh  # pull Nostr Browser, build Flight Deck, build app, launch
./runapp.sh        # launch the existing macOS build
```

`runapp.sh` sources `.env.local` and passes `WMAPP_REPO_DIR` to the app. The
signer identity still comes from the encrypted onboarding vault, not from shell
environment variables.

The current macOS development build disables the app sandbox because the Flutter shell still invokes the Rust core through `cargo run`. Production packaging should bundle and execute a signed `wmapp-core` binary from inside the app instead.

macOS signer/browser development builds do not require macFUSE or `fuse.pc`.
The Rust core uses fuser's `macos-no-mount` build mode on macOS so NIP-07 and
NIP-98 signing can compile on a normal laptop. The kernel Drive mount remains a
separate packaging target.

When launching the macOS app from Finder, the Flutter bridge looks for the Rust workspace in `WMAPP_REPO_DIR`, the current directory parents, `~/code/wm/wmapp`, the legacy `~/code/wingmanbefree/wm-app` checkpoint, or `~/wm-app`. If the repo is cloned elsewhere, launch with `WMAPP_REPO_DIR=/path/to/wm-app open build/macos/Build/Products/Debug/wingman_app.app`.

Flutter platform folders have been generated for macOS, Linux, web, Android,
and iOS. To validate the shell locally:

```bash
cd app
flutter pub get
flutter test
flutter build web
flutter build macos --debug
flutter run -d macos
```

Root helper scripts are available for the most common local builds:

```bash
./build_runapp.sh          # macOS debug build, then launch
./build_linux.sh           # Linux release bundle with bundled FIPS
./build_android_apk.sh     # Android debug APK
./build_ios_debug.sh       # iOS device debug build without codesigning
./build_ios_debug.sh simulator
```

The Android APK is written to:

```text
app/build/app/outputs/flutter-apk/app-debug.apk
```

The iOS debug builds are written to:

```text
app/build/ios/iphoneos/Runner.app
app/build/ios/iphonesimulator/Runner.app
```

Mobile status:

- Browser shell, home bookmarks, WebView browsing, policy prompts, encrypted local signer onboarding, NIP-07 `signEvent`, and NIP-98 signing are mobile-ready.
- Drive sync, device registration, channel validation, local file mounting, and NIP-44 encryption/decryption still use the desktop `wmapp-core` process path and need a mobile-native bridge in a later package.

FIPS runtime status:

- Setup → FIPS transport includes a persisted Nostr Browser FIPS on/off switch. Off
  cancels app mesh retries and transport resources; the separately installed
  desktop system daemon remains independently managed. See
  [Desktop FIPS control and diagnosis](docs/desktop-fips-control.md).
- Android and iOS include embedded FIPS runtimes. Enabling FIPS requests
  platform VPN consent and routes mesh and `.fips` DNS traffic through the
  runtime while ordinary internet traffic keeps its existing route.
- macOS bundles the pinned upstream package and activates it through the normal
  administrator authorization dialog.
- Linux bundles the pinned upstream systemd release for x86_64 or aarch64. On
  first `.fips` navigation Nostr Browser uses `pkexec` to install/repair it, enable the
  daemon and split-DNS service, preserve any existing identity, and connect the
  authenticated no-DNS bootstrap. This path supports Ubuntu and
  Arch/systemd-based Omarchy without a separate FIPS download.

Operational handoffs, worker briefs, device installation results, screenshots,
and run-specific validation evidence stay locally under `tmp/docs/handoffs/`.
They are ignored by Git. Keep reusable product documentation and test procedures
under `docs/`; use generic device labels and placeholders in examples. Do not
force-add handoffs or link public documentation to private evidence files.

See:

- [Architecture](docs/architecture.md)
- [Decision Backlog](docs/decisions.md)
- [Implementation Plan](docs/implementation_plan.md)
- [Tower Route Inventory](docs/tower_route_inventory.md)
- [Tower Drive Contract](docs/tower_drive_contract.md)
- [Device Key Contract](docs/device_key_contract.md)
- [API Gap Harness](docs/api_gap_harness.md)
- [WApp Signer Trust Contract](docs/wapp_signer_contract.md)
