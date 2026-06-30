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

## Work Package Index

Each phase is split into numbered work packages. Flight Deck tasks should use the same IDs in their titles so planning, task board state, and repo-local docs can be reconciled without guessing.

### Phase 0: Repo And Design

#### WP-00-01: Repo Seed And Documentation Baseline

Scope:

- Keep `wm-app` as a standalone repo under `~/code/wingmanbefree/wm-app`.
- Maintain the initial README, architecture, and implementation plan.
- Capture the product boundary: Flutter shell, native core, Tower source of truth, per-platform adapters.

Deliverable:

- Documentation baseline committed in `wm-app`.

Acceptance:

- `docs/architecture.md` and `docs/implementation_plan.md` explain the product shape and first implementation path.
- The repo can be handed to a fresh worker without relying on chat context.

#### WP-00-02: Architecture Decision Backlog

Scope:

- Create a lightweight decision log for major unresolved choices.
- Track decisions for Flutter/Rust split, macFUSE vs File Provider, local daemon API, device key model, and WApp signer policy.

Deliverable:

- A decision-log document or section with open, proposed, and accepted decisions.

Acceptance:

- Each open decision includes owner, context, options, recommendation, and trigger for finalizing.

### Phase 1: Tower Storage And Auth Contract Audit

#### WP-01-01: Tower Route Inventory

Scope:

- Inspect `wingman-tower` Flight Deck PG task, file, folder, document, storage, and event routes.
- Identify which current routes can support Wingman Drive and which are missing.

Deliverable:

- Route inventory with current route, method, auth, request payload, response payload, and suitability.

Acceptance:

- The audit covers file listing, file object download, storage upload, file metadata creation, scopes, channels, workspace discovery, and events.

#### WP-01-02: File, Folder, Version, And Delta Contract

Scope:

- Define the Tower-side metadata contract required by the sync core.
- Specify stable IDs, folder records, tombstones, version IDs, ETags, object refs, and delta cursor behavior.

Deliverable:

- Draft API contract for file/folder/version/delta routes.

Acceptance:

- The contract supports online-only placeholders, lazy hydration, optimistic writes, conflict detection, and deletes.

#### WP-01-03: Device Key And NIP-98 Grant Contract

Scope:

- Define how per-device Nostr keys are registered, granted, audited, and revoked in Tower.
- Confirm how Tower resolves a device npub to user/workspace permissions.

Deliverable:

- Device key registration and authorization contract.

Acceptance:

- A revoked device key fails closed.
- A granted device key can sign NIP-98 requests without exposing the user's master key.

#### WP-01-04: API Gap Harness And Tickets

Scope:

- Build or document a small signed script/CLI flow that exercises the current Tower API.
- Convert missing capabilities into follow-up Tower tasks.

Deliverable:

- API smoke-test notes plus a list of Tower gap tasks.

Acceptance:

- A signed request can list visible files and download one file where current APIs support it.
- Missing API routes are captured as explicit follow-up work.

### Phase 2: Native Core Spike

#### WP-02-01: Rust Workspace And Core Crate Skeleton

Scope:

- Add the native core project structure.
- Define modules for auth, Tower client, sync, cache, SQLite, and control API.

Deliverable:

- Compilable native core skeleton.

Acceptance:

- Native core builds locally.
- Module boundaries match the architecture document.

#### WP-02-02: Nostr Key Manager And NIP-98 Signer

Scope:

- Implement device key generation/import.
- Implement NIP-98 signing for Tower HTTP requests.
- Use a development storage backend first, with secure storage adapters planned separately.

Deliverable:

- CLI/API can generate a device npub and sign a NIP-98 request.

Acceptance:

- Generated signatures verify against the device npub.
- NIP-98 payload hashes are included for request bodies.

#### WP-02-03: Tower HTTP Client And Models

Scope:

- Implement typed client calls for workspace discovery, scopes, channels, files, file objects, and events.
- Model Tower responses in native code.

Deliverable:

- Core can call Tower and deserialize workspace/file metadata.

Acceptance:

- `wmapp-core status` and `wmapp-core list-files` work against a configured Tower.

#### WP-02-04: SQLite Index And Object Cache

Scope:

- Add local SQLite schema for accounts, workspaces, scopes, channels, items, versions, cache entries, transfers, permissions, and cursors.
- Add object cache layout and basic eviction metadata.

Deliverable:

- Local metadata index and content cache implementation.

Acceptance:

- A sync pass persists visible metadata.
- A downloaded object can be read from cache after restart.

#### WP-02-05: Sync CLI And Local Control API

Scope:

- Add a CLI and/or local control API for status, sync once, list items, cat file, pin, and evict.

Deliverable:

- Headless core can be tested without Flutter.

Acceptance:

- `sync --once` populates metadata.
- `cat <fileId>` streams from cache or Tower.
- `status` reports account, device npub, Tower URL, and sync health.

### Phase 3: Flutter Shell Spike

#### WP-03-01: Flutter App Shell And Account Setup

Scope:

- Create the Flutter app shell.
- Add Tower URL configuration, account setup, key import/generate, and basic navigation.

Deliverable:

- Flutter app launches on at least one desktop target with account setup screens.

Acceptance:

- User can enter Tower URL and create/import a device key.

#### WP-03-02: Native Bridge To Core Status And Config

Scope:

- Connect Flutter to native core through platform channels, FFI, or local control API.
- Expose status, account config, and basic sync commands.

Deliverable:

- Flutter can display native core status and trigger sync.

Acceptance:

- UI shows device npub, Tower URL, and latest sync result from the native core.

#### WP-03-03: Embedded WebView With `window.nostr` Injection

Scope:

- Add WebView for Flight Deck and WApps.
- Inject a minimal NIP-07-style `window.nostr` bridge for approved origins.

Deliverable:

- Test page can call `window.nostr.getPublicKey()`.

Acceptance:

- Unknown origins do not get the bridge.
- Approved origin receives only the supported methods.

#### WP-03-04: NIP-98 Permission Prompt Prototype

Scope:

- Implement native approval flow for WebView NIP-98 signing requests.
- Add remembered approval for safe Tower auth requests.

Deliverable:

- WebView can request and receive a NIP-98 signature through the native bridge.

Acceptance:

- The prompt shows origin, URL, method, event kind, and device npub before approval.

### Phase 4: Linux FUSE Read-Only Mount

#### WP-04-01: Linux FUSE Adapter Skeleton

Scope:

- Add Linux FUSE adapter.
- Mount and unmount a local `~/FlightDeck` filesystem from the core.

Deliverable:

- Empty or fixture-backed mount works on Linux.

Acceptance:

- `ls ~/FlightDeck` returns without errors.
- Mount and unmount are controlled by CLI or local API.

#### WP-04-02: Metadata Projection To Mount Tree

Scope:

- Project workspace, scope, channel, folder, and file metadata into filesystem paths.

Deliverable:

- Read-only directory tree from local SQLite metadata.

Acceptance:

- `find ~/FlightDeck -maxdepth 4` shows expected Tower-backed hierarchy.

#### WP-04-03: Lazy Read And Range Hydration

Scope:

- Implement file open/read by fetching missing ranges from Tower into cache.

Deliverable:

- Opening a file hydrates content on demand.

Acceptance:

- Files are visible before content is downloaded.
- Reopening hydrated content uses cache.

#### WP-04-04: Doc URL Entries And Read-Only Validation

Scope:

- Expose Flight Deck docs as `.flightdeck.url` entries.
- Validate read-only desktop behavior.

Deliverable:

- Docs open in the default browser, not as editable local document bodies.

Acceptance:

- Opening a doc entry launches the Flight Deck URL.
- Write operations are rejected or ignored clearly in read-only mode.

### Phase 5: macOS Early Mount

#### WP-05-01: macFUSE Adapter

Scope:

- Add macFUSE support reusing the Linux FUSE semantics where practical.

Deliverable:

- macOS read-only mounted Wingman Drive.

Acceptance:

- Finder can browse workspace/scope/channel/file hierarchy.
- File open hydrates from Tower.

#### WP-05-02: macOS Mount UX And Tray Controls

Scope:

- Add tray/menu controls for mount, unmount, reveal in Finder, sync status, and cache actions.

Deliverable:

- Basic macOS user controls for the early mount.

Acceptance:

- User can mount/unmount without terminal commands.

#### WP-05-03: macOS Early-Mount Decision Gate

Scope:

- Compare macFUSE UX against File Provider needs.
- Decide whether to continue macFUSE for beta or prioritize File Provider.

Deliverable:

- Written decision with recommendation.

Acceptance:

- Decision covers install friction, Finder behavior, placeholder UX, permissions, and distribution impact.

### Phase 6: Desktop Write Support

#### WP-06-01: Local Write Detection And Upload Queue

Scope:

- Detect creates, writes, renames, moves, and deletes in desktop adapters.
- Queue uploads and metadata mutations.

Deliverable:

- Dirty local state transitions into upload queue entries.

Acceptance:

- A new local file appears as a pending upload.

#### WP-06-02: Versioned Uploads And Conflict Handling

Scope:

- Implement optimistic `baseVersion` uploads.
- Detect remote/local divergence and create conflict copies.

Deliverable:

- Conflict-safe upload flow.

Acceptance:

- Remote edit races produce a conflict file rather than overwriting remote data.

#### WP-06-03: Desktop Transfer UI And Retries

Scope:

- Add transfer status, retries, backoff, and user-visible errors.

Deliverable:

- Desktop UI for upload/download queue health.

Acceptance:

- Failed transfers are visible and retryable.

### Phase 7: Android DocumentsProvider

#### WP-07-01: Android Shell And Key Storage

Scope:

- Add Android build target and secure key storage through Android Keystore.

Deliverable:

- Android app can store a device key and sign NIP-98.

Acceptance:

- Device key survives app restart without exposing raw private key to WebView content.

#### WP-07-02: DocumentsProvider Browse And Open

Scope:

- Implement Android DocumentsProvider browsing and lazy open behavior.

Deliverable:

- Wingman appears in Android file picker flows.

Acceptance:

- A third-party app can browse and open a Wingman file.

#### WP-07-03: Android WApp Signer WebView

Scope:

- Add Android WebView signer bridge and permission prompts.

Deliverable:

- Approved WApps can request NIP-98 signatures in the Android app.

Acceptance:

- Unknown origins are denied by default.

### Phase 8: iOS File Provider

#### WP-08-01: iOS Shell And Key Storage

Scope:

- Add iOS target and Keychain-backed device key storage.

Deliverable:

- iOS app can store a device key and sign NIP-98.

Acceptance:

- Key custody works across app restarts and denies direct WebView access.

#### WP-08-02: iOS File Provider Enumeration

Scope:

- Implement iOS File Provider item enumeration from Tower metadata.

Deliverable:

- Wingman appears in the iOS Files app with workspace/scope/channel hierarchy.

Acceptance:

- Files are visible as provider-backed items without downloading all bytes.

#### WP-08-03: iOS Lazy Download And Signer Browser

Scope:

- Implement File Provider download-on-open.
- Add WApp browser signer support in the main iOS app.

Deliverable:

- iOS can open files lazily and sign WApp/Tower auth requests.

Acceptance:

- Opening a file downloads from Tower.
- Approved WApp can obtain a NIP-98 signature.

### Phase 9: Native File Provider Upgrade For macOS

#### WP-09-01: macOS File Provider Architecture Spike

Scope:

- Build a minimal macOS File Provider proof of concept.
- Map Tower item IDs to File Provider identifiers.

Deliverable:

- Spike showing enumeration and placeholder behavior.

Acceptance:

- The spike proves whether the shared core model fits macOS File Provider.

#### WP-09-02: Finder Placeholder And Hydration Flow

Scope:

- Implement native Finder placeholder, download, eviction, and pin states.

Deliverable:

- File Provider-backed Finder integration.

Acceptance:

- Placeholder, hydrated, and pinned states behave as expected.

#### WP-09-03: Migration From macFUSE To File Provider

Scope:

- Define migration path for users and cache/index reuse.

Deliverable:

- Migration plan and implementation if File Provider is adopted.

Acceptance:

- Existing cache and account config survive migration where practical.

### Phase 10: WApp Signer Policy

#### WP-10-01: WApp Trusted Identity And Origin Contract

Scope:

- Define how Wingman App knows a WApp origin is trusted.
- Bind WApp records, app IDs, workspace IDs, and origins.

Deliverable:

- Trusted WApp identity contract.

Acceptance:

- Origin alone is not enough to receive signing access.

#### WP-10-02: Signer Policy Engine And Audit Log

Scope:

- Implement local signer policy for origins, event kinds, NIP-98 targets, and NIP-44 operations.
- Record local audit events.

Deliverable:

- Policy engine with conservative defaults.

Acceptance:

- Unknown origins are denied.
- Arbitrary signing and decrypt requests require explicit approval.

#### WP-10-03: Permission Management UI

Scope:

- Build UI to view, grant, revoke, and reset WApp signer permissions.

Deliverable:

- User-facing permission management.

Acceptance:

- Revoking a WApp permission immediately blocks future signing requests.

### Phase 11: Packaging And Distribution

#### WP-11-01: macOS And Linux Packaging

Scope:

- Package desktop app and native core for macOS and Linux.
- Include install checks for macFUSE/FUSE where needed.

Deliverable:

- Installable desktop builds.

Acceptance:

- Fresh install can configure Tower, store device key, and run the app shell.

#### WP-11-02: Android And iOS Distribution

Scope:

- Prepare Android APK/AAB and iOS TestFlight distribution.

Deliverable:

- Mobile install artifacts.

Acceptance:

- Fresh mobile install can configure Tower, store device key, and open signer browser.

#### WP-11-03: Updates, Diagnostics, And Uninstall Policy

Scope:

- Define update channels, diagnostics export, crash/log policy, and uninstall cleanup.

Deliverable:

- Operational lifecycle policy and initial implementation hooks.

Acceptance:

- User can export diagnostics without leaking private keys.
- Uninstall can remove keys/cache according to user choice.

## Phase 0: Repo And Design

Work packages:

- WP-00-01: Repo Seed And Documentation Baseline.
- WP-00-02: Architecture Decision Backlog.

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

Work packages:

- WP-01-01: Tower Route Inventory.
- WP-01-02: File, Folder, Version, And Delta Contract.
- WP-01-03: Device Key And NIP-98 Grant Contract.
- WP-01-04: API Gap Harness And Tickets.

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

Work packages:

- WP-02-01: Rust Workspace And Core Crate Skeleton.
- WP-02-02: Nostr Key Manager And NIP-98 Signer.
- WP-02-03: Tower HTTP Client And Models.
- WP-02-04: SQLite Index And Object Cache.
- WP-02-05: Sync CLI And Local Control API.

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

Work packages:

- WP-03-01: Flutter App Shell And Account Setup.
- WP-03-02: Native Bridge To Core Status And Config.
- WP-03-03: Embedded WebView With `window.nostr` Injection.
- WP-03-04: NIP-98 Permission Prompt Prototype.

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

Work packages:

- WP-04-01: Linux FUSE Adapter Skeleton.
- WP-04-02: Metadata Projection To Mount Tree.
- WP-04-03: Lazy Read And Range Hydration.
- WP-04-04: Doc URL Entries And Read-Only Validation.

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

Work packages:

- WP-05-01: macFUSE Adapter.
- WP-05-02: macOS Mount UX And Tray Controls.
- WP-05-03: macOS Early-Mount Decision Gate.

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

Work packages:

- WP-06-01: Local Write Detection And Upload Queue.
- WP-06-02: Versioned Uploads And Conflict Handling.
- WP-06-03: Desktop Transfer UI And Retries.

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

Work packages:

- WP-07-01: Android Shell And Key Storage.
- WP-07-02: DocumentsProvider Browse And Open.
- WP-07-03: Android WApp Signer WebView.

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

Work packages:

- WP-08-01: iOS Shell And Key Storage.
- WP-08-02: iOS File Provider Enumeration.
- WP-08-03: iOS Lazy Download And Signer Browser.

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

Work packages:

- WP-09-01: macOS File Provider Architecture Spike.
- WP-09-02: Finder Placeholder And Hydration Flow.
- WP-09-03: Migration From macFUSE To File Provider.

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

Work packages:

- WP-10-01: WApp Trusted Identity And Origin Contract.
- WP-10-02: Signer Policy Engine And Audit Log.
- WP-10-03: Permission Management UI.

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

Work packages:

- WP-11-01: macOS And Linux Packaging.
- WP-11-02: Android And iOS Distribution.
- WP-11-03: Updates, Diagnostics, And Uninstall Policy.

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
