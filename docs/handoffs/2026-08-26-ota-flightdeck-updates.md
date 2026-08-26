# Verified over-the-wire Flight Deck updates

Status: implementation handoff
Date: 2026-08-26

## Work record

- Flight Deck task: @[Add verified over-the-wire Flight Deck updates to WMAPP](mention:task:26068baa-a4e8-4549-a7eb-9ea8884da7b5)
- Originating request: @[Message](mention:message:81c7bfad-0077-4418-9fc3-5c4d6f082247) in @[Channel](mention:channel:d8d00881-ac84-41eb-ab0d-2c2afb77ddf3)
- Originating thread: Pete asked whether a chosen GitHub branch could update Flight Deck without rebuilding WMAPP, accepted the download-and-serve-locally model, then asked Rick to set it up.

Read the task and its latest comments before doing work. They are the authoritative execution contract and reporting surface.

## Goal

Make Flight Deck independently updateable as web content while WMAPP retains control of trust, installation, local serving, fallback, and native bridge compatibility.

The target flow is:

1. A dedicated branch in `/Users/mini/code/wm/flightdeck` triggers a reproducible GitHub Actions build.
2. CI publishes an immutable/versioned Flight Deck archive and a stable manifest containing version, URL, SHA-256 digest, size, schema/compatibility data, and release metadata.
3. WMAPP checks the stable manifest asynchronously at startup and through a user-visible control.
4. WMAPP downloads only a newer compatible archive, enforces host/HTTPS and resource limits, verifies its digest, extracts it safely to staging, validates its expected structure, then atomically promotes it.
5. WMAPP's existing local Flight Deck server serves the selected on-device directory at the same loopback origin used today.
6. The previous verified version remains rollback-capable. The packaged asset copy remains the bootstrap and final fallback.

Do not make the WebView run branch source, GitHub Pages, or another remote origin directly.

## Architecture decision

The latest living architecture reference is v4:

`https://pale-log-tank.rick.runwingman.com/artifacts/Wingman_Suite/wingman-suite-arch/v4/`

Its saved Excalidraw scene explicitly separates application-version checks from Flight Deck's TowerSyncService/workspace-data sync. Therefore:

- WMAPP owns update checks, download, verification, local activation, state, and rollback.
- Flight Deck owns producing the distributable web build and its compatibility declaration.
- Tower remains the workspace/data authority and is not made an update CDN.
- The loopback origin and native signer trust boundary remain stable.

## Starting state

### WMAPP

Path: `/Users/mini/code/wm/wmapp`

- Branch: `main`
- Dispatch-preparation state: clean and one commit ahead of `origin/main`
- Existing commit to preserve: `204c7f0 build: package Flight Deck 1841`
- Current packaging: `app/assets/flightdeck/` is declared in `app/pubspec.yaml` and served by `app/lib/src/core/local_flight_deck_server_io.dart`.
- Existing source updater: `tools/update_flightdeck_bundle.sh` with focused source-resolution coverage in `tools/test_update_flightdeck_bundle.sh`.

The repo-local handoff file itself will appear as a new nonignored change when the worker starts. It is part of the task context and should be committed with the tested implementation.

### Flight Deck publisher source

Path: `/Users/mini/code/wm/flightdeck`

- Branch: `main`
- Dispatch-preparation state: ahead of `origin/main` with unrelated concurrent modifications in `src/autopilot-overview-manager.js`, `src/unread-store.js`, and two other task handoffs.
- Do not reset, discard, stash, rebase, overwrite, or blindly commit those changes.
- Inspect current state again before changing it. If the CI publisher genuinely belongs here, make the smallest compatible workflow/tooling change and keep repo commits conventional and understandable.

## Required implementation

### Update contract

Define and document a versioned manifest contract. At minimum it should carry:

- manifest schema version;
- Flight Deck build/version and source commit;
- immutable archive URL;
- archive SHA-256 and byte size;
- build timestamp;
- minimum supported WMAPP/native bridge compatibility version;
- optional channel/branch identity and release notes URL.

Use deterministic canonical JSON if a future signature field is planned. SHA-256 is mandatory for corruption/integrity checking. If there is already an appropriate repo signing mechanism, add manifest signature verification; otherwise document that authenticity currently rests on the pinned HTTPS host/repository and list an independent signing key as the next security hardening step. Never generate or commit a private signing key.

### Publisher

- Add a deterministic packaging tool that builds Flight Deck, validates `dist/index.html`, archives the build without platform-specific junk, emits SHA-256/size, and writes the manifest.
- Add local fixture/test coverage for manifest and archive generation.
- Add a GitHub Actions workflow triggered by an explicitly named release branch. Choose a clear branch name and document it.
- Publish immutable versioned assets plus a stable channel manifest using an atomic or release-oriented promotion model.
- Keep permissions least-privilege and pin actions to suitable maintained versions or commit SHAs according to existing repository practice.
- Do not push the workflow, create the branch, enable Pages, publish a release, or add repository secrets in this worker. Report exact remaining operator steps.

### WMAPP updater

- Make the update feed configurable at build time or through a safe app setting while providing a documented production default/disabled behavior.
- Keep startup usable offline and when the feed is slow or broken.
- Store downloads under the application's support/cache area, never inside the signed application bundle.
- Use a unique staging directory/file, streaming digest verification, bounded download/archive/extracted sizes, bounded entry count, and path traversal/symlink rejection.
- Require the expected Flight Deck structure, including `index.html`, before promotion.
- Atomically switch a small active-version pointer or directory only after validation is complete.
- Preserve the prior verified version and prune older versions safely without deleting the packaged fallback.
- If an activated build cannot be served/loaded, expose rollback and ensure the next launch can recover to prior or packaged content.
- Record active, previous, available, last-check, last-success, last-failure, and sanitized error state.
- Preserve the same loopback origin/port semantics and signer trust checks. The local server should select a verified downloaded root when available, otherwise packaged Flutter assets.
- Make compatibility rejection explicit before activation. Do not let a Flight Deck build requiring a newer native bridge silently run against an older WMAPP.

### User surface

Add a concise update status/control surface in the most natural existing settings/status location:

- packaged/current/available Flight Deck version;
- checking, downloading, verifying, ready/active, failed, and rollback state;
- manual check/retry and rollback where meaningful;
- clear offline and compatibility messages;
- no secrets or verbose internal paths in user-facing errors.

### Tests

Focused tests must cover at least:

- manifest parsing and version comparison;
- no update / same version;
- successful download, verification, extraction, and activation;
- checksum and declared-size mismatch;
- malformed JSON and incompatible schema/native bridge;
- ZIP/path traversal, absolute path, symlink, entry-count, per-file, and total-size rejection;
- interrupted/partial download and staging cleanup;
- atomic activation failure retaining the existing active version;
- previous-version rollback;
- packaged fallback when no verified downloaded build exists;
- local server selection of downloaded vs packaged root;
- update status/control state transitions.

Run the repo's narrow tests during development, then the appropriate full Flutter test/analyze/build and bundle checks. Run `git diff --check` in every repo touched.

## Platform and policy note

Explicitly document whether locally downloaded Flight Deck HTML/JS is acceptable for each intended distribution path, especially iOS/App Store review. This is a release-policy risk to surface, not a reason to weaken verification or switch the WebView to GitHub. Keep the technical design capable of disabling OTA updates per build/channel if distribution policy requires the packaged-only mode.

## Git and operational constraints

- Default to `main`.
- Preserve concurrent work and re-read both worktrees before each commit.
- Commit all compatible nonignored tested state in a touched worktree so the repository represents the tested state.
- Use Conventional Commits.
- Do not reset, discard, stash, rebase, force-push, or overwrite unexplained changes.
- Do not push, deploy, publish external assets, create/rotate secrets, install to a physical device, or restart managed Autopilot/Flight Deck/WApp processes.
- Stay within WMAPP unless the Flight Deck publisher workflow is proven necessary; it is expected to be necessary, but keep the cross-repo contract narrow.

## Reporting

Post concise task comments at these milestones:

1. Investigation identifies the implementation path and exact repo/file boundary.
2. Core publisher/updater/activation behavior is implemented.
3. Tests/build and commits are complete, or a precise blocker is reached.

Before final handoff, re-read the task and recent comments. The final task comment must include:

- WMAPP and Flight Deck commit hashes (only for repos actually changed);
- manifest/feed example and chosen release branch;
- implementation summary and important security/rollback decisions;
- exact validation commands and results;
- external GitHub configuration still required;
- exact local/manual test steps, including failure/rollback testing;
- any iOS distribution-policy caveat;
- originating @[Message](mention:message:81c7bfad-0077-4418-9fc3-5c4d6f082247).

Move the task to `review` only after all tested changes are committed and the handoff is complete.
