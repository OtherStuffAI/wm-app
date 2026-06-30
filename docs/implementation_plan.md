# Wingman App Implementation Plan

Status: design draft
Date: 2026-06-30

## Goal

Build Wingman App as a cross-platform native edge client for Wingman Be Free.

Initial targets:

- macOS.
- Linux.
- Android.
- iPhone/iPad.

Initial capabilities:

- Per-device Nostr key setup.
- NIP-98 signed Tower HTTP requests.
- Tower-backed file browsing/sync.
- Lazy desktop file hydration.
- Docs open as Flight Deck URLs.
- Embedded WApp browser with a native `window.nostr` signer.

## Guiding Constraints

- Tower is the source of truth.
- All auth uses Nostr keys and NIP-98 where HTTP is involved.
- Device keys are Nostr keys with explicit Tower grants.
- WApps never receive raw private keys.
- The shared sync model should work across desktop and mobile.
- Platform file integration is adapter-specific.
- Do not fork Keychat.

## Phase 0: Repo And Design

Deliverables:

- `README.md`.
- `docs/architecture.md`.
- `docs/implementation_plan.md`.
- Initial repo structure decisions.

Validation:

- The docs clearly split Flutter shell, native core, Tower APIs, and platform adapters.
- The docs identify Tower-owned contracts and platform-specific work.

Status:

- Complete for documentation seed.

## Phase 1: Tower Storage And Auth Contract Audit

Purpose:

Confirm what Tower already exposes and identify the missing API work before client implementation starts.

Tasks:

- Inspect `wingman-tower` Flight Deck PG file routes.
- Inspect current storage metadata and object routes.
- Identify existing routes for:
  - channel files.
  - file object download.
  - upload.
  - object metadata.
  - workspace/scope/channel access checks.
  - visible event polling or deltas.
- Confirm current NIP-98 signer resolution for workspace user keys.
- Document gaps as a Tower API contract.

Expected Tower contracts:

```text
GET  /api/v4/flightdeck-pg/workspaces/:workspaceId/scopes
GET  /api/v4/flightdeck-pg/scopes/:scopeId/channels
GET  /api/v4/flightdeck-pg/channels/:channelId/files
GET  /api/v4/flightdeck-pg/files/:fileId/object
```

Likely new or expanded contracts:

```text
GET    /api/v4/flightdeck-pg/files/delta?cursor=...
GET    /api/v4/flightdeck-pg/folders/:folderId/children
POST   /api/v4/flightdeck-pg/folders
PATCH  /api/v4/flightdeck-pg/files/:fileId
DELETE /api/v4/flightdeck-pg/files/:fileId
PUT    /api/v4/flightdeck-pg/files/:fileId/object?baseVersion=...
```

Validation:

- A signed local script can list files visible to a device/user npub.
- A signed local script can download one file object.
- Missing APIs are captured as implementation tickets.

## Phase 2: Native Core Spike

Purpose:

Prove the core can authenticate to Tower, index metadata, and cache file bytes without UI.

Recommended language:

- Rust.

Initial modules:

```text
core/
  auth/
    nostr_keys
    nip98
  tower/
    client
    models
  sync/
    scanner
    delta
    state_machine
  cache/
    object_store
    eviction
  db/
    sqlite
  control/
    local_api
```

Tasks:

- Generate/import a device Nostr key.
- Store development keys in a local encrypted file first, then replace with platform secure storage.
- Sign NIP-98 requests.
- Call Tower service/workspace discovery.
- List scopes/channels/files.
- Create SQLite schema for local metadata.
- Download one object into cache.
- Expose `GET /status` and `GET /items` through a local control API or CLI.

Validation:

- `wmapp-core login/status` shows the device npub and Tower URL.
- `wmapp-core sync --once` populates SQLite with visible Tower file metadata.
- `wmapp-core cat <fileId>` streams bytes from cache or Tower.

## Phase 3: Flutter Shell Spike

Purpose:

Prove Flutter can act as the user-facing shell and control the native core.

Tasks:

- Create a Flutter app under `app/`.
- Add account setup screens.
- Add key import/generate screen.
- Add Tower URL configuration.
- Add sync status view.
- Connect Flutter to the native core through the chosen bridge.
- Add an embedded WebView for Flight Deck/WApps.
- Inject a minimal `window.nostr` bridge for an approved origin.

Validation:

- User can configure a Tower URL.
- User can generate a device npub.
- Flutter can call native core `status`.
- WebView page can call `window.nostr.getPublicKey()`.
- WebView page can request a NIP-98 signature for an approved Tower URL.

## Phase 4: Linux FUSE Read-Only Mount

Purpose:

Prove the virtual filesystem model with the simplest desktop target.

Tasks:

- Add Linux FUSE adapter.
- Mount `~/FlightDeck`.
- Project workspace/scope/channel/folder/file metadata into paths.
- Implement directory listing.
- Implement file stat with known size and timestamps.
- Implement lazy read and range fetch.
- Expose Flight Deck docs as `.flightdeck.url` entries.

Validation:

```bash
ls ~/FlightDeck
find ~/FlightDeck -maxdepth 4 -type f
open-or-cat ~/FlightDeck/<workspace>/<scope>/<channel>/<file>
```

Acceptance:

- Files appear without pre-downloading all bytes.
- Opening a file hydrates bytes from Tower.
- Reopening a hydrated file uses local cache.
- Docs open the Flight Deck URL in the default browser.

## Phase 5: macOS Early Mount

Purpose:

Get macOS desktop parity before investing in File Provider.

Tasks:

- Add macFUSE adapter.
- Reuse the Linux filesystem semantics where possible.
- Add macOS app permissions and install guidance.
- Add tray/menu control to mount/unmount.

Validation:

- Finder shows the mounted Wingman folder.
- Opening a normal file hydrates from Tower.
- Opening a doc URL opens the default browser.

Decision Gate:

- If macFUSE UX is good enough for early users, continue with it.
- If Finder integration, placeholder behavior, or install friction is unacceptable, prioritize macOS File Provider.

## Phase 6: Desktop Write Support

Purpose:

Allow local file creation and edits with conflict-safe upload.

Tasks:

- Detect create/write/rename/delete in FUSE/macFUSE.
- Queue uploads through the sync engine.
- Add optimistic `baseVersion` uploads.
- Add conflict detection.
- Add conflict file naming.
- Add retry/backoff.
- Add transfer status UI.

Validation:

- Create a local file and see it appear in Tower/Flight Deck.
- Edit a local file and see a new remote version.
- Simulate a remote edit race and verify conflict handling.
- Delete a local file and verify Tower tombstone semantics.

## Phase 7: Android DocumentsProvider

Purpose:

Expose Wingman Drive through Android's document provider/file picker model.

Tasks:

- Add Android native plugin/adapter.
- Reuse core metadata sync and content cache.
- Implement browse/open/download through DocumentsProvider.
- Add local key storage through Android Keystore.
- Add signer WebView support.

Validation:

- Wingman appears as a storage provider in Android file flows.
- A third-party app can pick/open a Wingman file.
- Opening a file hydrates content from Tower.
- WApp WebView can request a NIP-98 signature from native code.

## Phase 8: iOS File Provider

Purpose:

Expose Wingman Drive in the iOS Files app.

Tasks:

- Add iOS File Provider extension.
- Reuse core metadata model where iOS allows.
- Integrate iOS Keychain for device key storage.
- Implement item enumeration.
- Implement download-on-open.
- Implement doc URL entries.
- Add signer WebView support in the main app.

Validation:

- Wingman appears in the iOS Files app.
- Files can be browsed by workspace/scope/channel/folder.
- Opening a file downloads it from Tower.
- WApp browser can sign NIP-98 requests.

## Phase 9: Native File Provider Upgrade For macOS

Purpose:

Move macOS from a FUSE-style prototype to a polished cloud-files integration if needed.

Tasks:

- Add macOS File Provider extension.
- Map Tower item IDs to File Provider item identifiers.
- Implement enumeration, placeholder display, download, upload, delete, and conflict flow.
- Preserve the same local SQLite/cache model where practical.

Validation:

- Finder shows native cloud-file style behavior.
- Placeholder and hydrated states behave as users expect.
- App handles restart, offline, and account revocation cleanly.

## Phase 10: WApp Signer Policy

Purpose:

Move from a prototype signer to a safe app platform capability.

Tasks:

- Define WApp identity metadata trusted by the app.
- Bind WApp launch records to allowed origins.
- Add per-origin and per-WApp permission storage.
- Add prompt UI for signing and decryption.
- Add policy presets:
  - Tower auth only.
  - Auth plus app events.
  - Auth plus encryption.
  - Developer/unrestricted mode.
- Add audit log for signer requests.

Validation:

- Unknown origins cannot access `window.nostr`.
- Approved WApps can request NIP-98 signatures.
- Arbitrary event signing prompts the user.
- Permission revocation takes effect immediately.

## Phase 11: Packaging And Distribution

Purpose:

Make the app installable and updateable.

Tasks:

- macOS signed app build.
- Linux package or AppImage/deb/rpm decision.
- Android APK/AAB build.
- iOS TestFlight build.
- Update channel design.
- Crash/log collection policy.
- Secure local diagnostics export.

Validation:

- Fresh install can connect to Tower.
- Upgrade preserves account and cache metadata.
- Uninstall removes keys/cache according to user choice.

## Cross-Repo Work Items

Tower:

- Device key registration and revocation.
- File/folder metadata routes.
- Delta cursor routes.
- Object range reads.
- Optimistic versioned uploads.
- WApp trusted origin metadata.

Flight Deck:

- File URL/doc URL behavior.
- WApp launcher metadata for native app.
- UI for device key management if not only in Tower admin.

Autopilot:

- WApp assignment metadata may need native-app launch hints.
- Developer tooling to run WApps in the Wingman Browser during testing.

wm-app:

- Flutter shell.
- Native core.
- Platform adapters.
- Signer policy.
- Packaging.

## First Worker-Friendly Milestones

Milestone A: Tower Contract Audit

- Workdir: `~/code/wingmanbefree/wingman-tower`.
- Deliverable: `wm-app` API gap document or Tower issue/task.
- No client code required.

Milestone B: Core CLI Prototype

- Workdir: `~/code/wingmanbefree/wm-app`.
- Deliverable: Rust CLI can sign NIP-98 and list Tower files.
- No Flutter required.

Milestone C: Flutter Signer Browser Prototype

- Workdir: `~/code/wingmanbefree/wm-app`.
- Deliverable: Flutter WebView injects `window.nostr` and signs a test NIP-98 request.
- No filesystem required.

Milestone D: Linux Read-Only Drive

- Workdir: `~/code/wingmanbefree/wm-app`.
- Deliverable: FUSE mount lists and lazily opens Tower files.
- No write support required.

Milestone E: macOS Read-Only Drive

- Workdir: `~/code/wingmanbefree/wm-app`.
- Deliverable: macFUSE or File Provider proof of the same read-only flow.

## Risks

- Tower file API may not yet expose stable folder/file/version/delta semantics.
- macOS File Provider has more platform ceremony than macFUSE.
- Mobile file providers have stricter lifecycle limits than desktop daemons.
- WebView injection differs by platform and may require platform-specific plugin code.
- Key custody and signer permissions must be conservative from the start.
- Offline edits and conflicts can become complex; defer until read-only sync is proven.

## Recommended Next Step

Start with two parallel spikes:

1. Tower storage API audit.
2. Flutter signer browser prototype.

Then build the Linux FUSE read-only drive once the Tower file contract is clear.
