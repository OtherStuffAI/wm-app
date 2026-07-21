# Wingman App

Wingman App is the planned native edge client for Wingman Be Free.

The initial product combines:

- Wingman Drive: a desktop/mobile file surface backed by Tower HTTP storage.
- Wingman Browser: an embedded browser for Flight Deck and WApps with native Nostr signing.
- Wingman Signer: local per-device Nostr key custody for NIP-98 and approved app signing.

Tower remains the source of truth for workspace identity, scopes, channels, groups, file metadata, and object storage.

## Current Status

Phase 1 contracts and the Phase 2 headless native core are complete.

Latest package: `WP-02-05: Sync CLI And Local Control API`.

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

The Flutter shell lives at `app/`. It defines setup, Drive, browser, and status screens plus a `NativeCoreBridge` local-process bridge to the existing Rust core.

The current desktop spike can generate/import a device key, register a device through Tower, validate a configured channel, trigger one-shot sync, list local Drive metadata, and inject a `window.nostr` bridge into WebView pages.

The browser prototype has an address bar for loading arbitrary `http` and
`https` websites. The injected NIP-07 surface supports `getPublicKey`,
prompt-backed `signEvent`, empty `getRelays`, and explicit not-yet-supported
errors for NIP-04/NIP-44 encryption. NIP-98 remains more restrictive: both the
loaded WebView origin and the requested NIP-98 target origin must be trusted
before the native approval prompt appears. Remembered NIP-98 approvals and
signer audit entries are persisted locally, and the Signer tab can revoke
approvals or clear the audit log. A static signer test page is served from the
Flutter web build at `/signer-test.html` for native WebView/manual bridge
checks.

Fresh dev builds default to Pete's Wingman App channel and the hosted signer test:

- Tower URL: `http://127.0.0.1:3100`
- Browser URL: `https://kind-net-duck.rick.runwingman.com/signer-test.html`
- Trusted origins: local Tower/dev Flight Deck, `kind-net-duck.rick.runwingman.com`, and `near-tea-crab.rick.runwingman.com`

For a laptop development signer, keep the private key in an ignored root
`.env.local` file:

```bash
cd ~/code/wm-app
cp .env.local.example .env.local
$EDITOR .env.local
```

Set:

```bash
export WINGMAN_NSEC="<your-nsec-or-hex-secret-key>"
```

Then launch through the root helper scripts:

```bash
./build_runapp.sh  # pull, fetch deps, build, launch
./runapp.sh        # launch the existing macOS build
```

`runapp.sh` sources `.env.local` and passes `WMAPP_REPO_DIR` to the app. On
startup the Flutter shell imports `WINGMAN_NSEC`, derives the matching device
`npub`, and uses that identity for the browser signer and NIP-98 calls.

The current macOS development build disables the app sandbox because the Flutter shell still invokes the Rust core through `cargo run`. Production packaging should bundle and execute a signed `wmapp-core` binary from inside the app instead.

macOS signer/browser development builds do not require macFUSE or `fuse.pc`.
The Rust core uses fuser's `macos-no-mount` build mode on macOS so NIP-07 and
NIP-98 signing can compile on a normal laptop. The kernel Drive mount remains a
separate packaging target.

When launching the macOS app from Finder, the Flutter bridge looks for the Rust workspace in `WMAPP_REPO_DIR`, the current directory parents, `~/code/wingmanbefree/wm-app`, or `~/wm-app`. If the repo is cloned elsewhere, launch with `WMAPP_REPO_DIR=/path/to/wm-app open build/macos/Build/Products/Debug/wingman_app.app`.

Flutter platform folders have been generated for macOS, Linux, and web. To validate the shell locally:

```bash
cd app
flutter pub get
flutter test
flutter build web
flutter build macos --debug
flutter run -d macos
```

See:

- [Architecture](docs/architecture.md)
- [Decision Backlog](docs/decisions.md)
- [Implementation Plan](docs/implementation_plan.md)
- [Tower Route Inventory](docs/tower_route_inventory.md)
- [Tower Drive Contract](docs/tower_drive_contract.md)
- [Device Key Contract](docs/device_key_contract.md)
- [API Gap Harness](docs/api_gap_harness.md)
- [WApp Signer Trust Contract](docs/wapp_signer_contract.md)
