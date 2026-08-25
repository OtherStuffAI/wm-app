# WMAPP Android release to Zapstore

## Outcome

Publish the first shareable Android release of WMAPP to Zapstore under Rick's stable Nostr publisher identity, then return a verified install path Pete can use on his tablet and share with early testers.

Flight Deck tracking: @[Publish signed WMAPP Android release to Zapstore](mention:task:4cccad9c-82a0-4723-a6c5-66190cc51faf), originating from @[Message](mention:message:36efe0e7-9716-45cb-83bf-f0421cc01699) in @[features](mention:channel:d8d00881-ac84-41eb-ab0d-2c2afb77ddf3).

## Current evidence

- Active repo: `/Users/mini/code/wm/wmapp`; the old `/Users/mini/code/wingmanbefree/wm-app` checkout is superseded.
- Repo was clean on `main` and aligned with `origin/main` at manager inspection time.
- Flutter 3.44.4 is installed. Official `zsp` v0.4.17 is installed at `~/go/bin/zsp`; Android SDK build-tools 36.1.0 provide `apksigner` and `aapt`.
- `app/pubspec.yaml` declares release `0.1.2+3`.
- Android application ID is `com.wingmanbefree.wingman_app`.
- `app/android/app/build.gradle.kts` now requires the external release-signing environment and cannot fall back to the debug certificate.
- `build_android_apk.sh` currently creates only `app-debug.apk`.
- Zapstore's current official publisher is `zsp` (`github.com/zapstore/zsp`). Version 0.4.17 was installed from the official Go module for this release. Its current extraction command is `zsp utils extract-apk`; an npub plus offline mode emits unsigned software events and an upload manifest without handling private signing material.
- Zapstore publication signs Nostr software events (currently application kind 32267, release kind 30063, and asset kind 3063). This Nostr publisher signature is distinct from the Android APK signing certificate.

## Release validation completed 2026-08-26

- Durable keystore: `~/.config/wmapp/android-release.jks`, mode `0600`, with its password in the `wmapp-android-release` macOS Keychain item. The keystore was already present and was preserved rather than overwritten.
- Package: `com.wingmanbefree.wingman_app`.
- Version name/code: `0.1.2` / `3`.
- APK: `app-release.apk`, 21,631,286 bytes.
- APK SHA-256: `79d0360a1c429459b5ac753f07441f3cb62f28aef7fed7c8835798ecd2353c2e`.
- Release certificate SHA-256: `6c0da09b9e2375d657645f197419be7b8227a7434e0225512fc760cedf383c8c`.
- Certificate subject: `CN=WMAPP Android Release, O=Wingman Be Free`; Android debug certificate SHA-256 on this machine is `a98dd3e317915e143f66f94d4b2513cb8dbba217a58e785581901e3e69f6f561`, proving the release did not use the debug signer.
- `flutter pub get`, `flutter analyze`, all 46 Flutter tests, and `flutter build apk --release --target-platform android-arm64` passed.
- `zsp utils extract-apk`, `zsp publish --check zapstore.yaml`, `apksigner verify --verbose --print-certs`, `aapt dump badging`, the missing-signing failure-path test, `bash -n`, and `git diff --check` passed.
- `zsp` generated an unsigned kind 32267 application template (`0629d40724d17d12d37cc545a5a174509265b71c5f650cce3f84926a9dfcd046`), kind 30063 release template (`40586e258f3e7df0a53fdf7e435d70caa4966a9bdb9487571d5c225d144b12d4`), and kind 3063 asset template (`a14360e68f977407477969819277de124c3b9e5f3fa92c648a9c1124537c3706`). These are deterministic unsigned template IDs, not published event IDs.
- The generated APK and icon Blossom URLs both returned public HTTP 404 and therefore require authenticated upload before their software events can be published.

## Narrow publication blocker

The running session's direct Nostr MCP signer correctly resolves to Rick's configured npub, but its policy denied every required non-note event kind with `Nostr event kind is not allowed`: Blossom upload authorization kind `24242`, software application kind `32267`, software release kind `30063`, and software asset kind `3063`. No asset or software event was published, and no catalog/install claim can be made. The safe next step is to grant this stable agent identity those four exact event kinds, then regenerate the time-sensitive Blossom authorization, upload the APK/icon, sign and publish the three existing software templates, and verify the public catalog.

## Authority and secret boundaries

Rick's stable publisher npub is:

`npub1llwrq3rtah3rg3r2dyfyht55ek7aa0ey7z47ujju407pzfp38shqa7zcvr`

Use the Nostr signing and publishing tools already available inside the running agent session (for example the broker-backed `nostr_sign_event` / `nostr_publish_event` MCP surface). Do not inspect or use the Autopilot repository to implement signing, do not build a signer adapter, and do not route `zsp` to an nsec or bunker. Never export, search for, display, log, copy, persist, or pass on a command line any nsec, raw private key, bunker URI, capability token, `WINGMAN_CAPABILITY`, or equivalent secret. Do not add a raw-key fallback.

The Android release certificate is a separate identity. Create or locate one durable WMAPP Android release keystore, store it outside git, and keep its password out of source, shell history, task comments, logs, and generated artifacts. Prefer environment/Gradle property indirection and document the safe operator path without recording secrets. Do not overwrite an existing release keystore whose provenance is unclear. Record only the public certificate SHA-256 fingerprint.

Use `zsp` to build/extract the software event payloads and the session's existing Nostr tools to sign/publish them. If the available tools deny a required event kind, capture the exact denied kind and stop at that narrow blocker. Do not inspect Autopilot signing internals, create a signer adapter, switch to raw secrets, or use Pete Tier 2.

## Work scope

1. Re-read the task and latest comments. Re-inspect the repo, branch, status, existing release artifacts, git history, Android config, and any ignored/local signing configuration before changing anything.
2. Confirm the current official `zsp` workflow and exact event/upload requirements from primary Zapstore sources. Install `zsp` from an official release or source in a user-local tool location; do not commit downloaded binaries.
3. Establish durable Android release signing:
   - use a stable release keystore outside the repo;
   - wire Gradle/Flutter release builds to external properties or environment variables;
   - ensure missing signing configuration fails clearly rather than silently using the debug key;
   - update `.gitignore`, scripts, and deployment docs as needed so no keystore/password can enter git;
   - choose an intentional version name/code greater than the currently published/tested build if required by Zapstore.
4. Add a reproducible release command/script and a `zapstore.yaml` (or the current official equivalent) containing suitable app name, summary/description, repository URL, license if verifiable, release source, icon/screenshots where available, channel, and architecture selection. Avoid making up metadata; note any absent screenshots rather than inventing them.
5. Run repository-native validation before publication: Flutter dependency resolution, analyze, tests, release APK build, `zsp apk --extract`, `zsp publish --check` or the closest valid check for a local source, SHA-256 calculation, APK signature/certificate verification, and `git diff --check`.
6. Publish the APK/assets and Nostr software events under Rick's broker-held identity. Use the official Zapstore relay/indexer defaults unless the live docs require explicit relays. Preserve event IDs and per-relay acceptance evidence.
7. Independently verify the result from public/read-only surfaces: resolve Rick's published software events, confirm package/version/hash/certificate tags match the built APK, and verify the Zapstore listing/install URL or exact in-app search flow. If practical, install from Zapstore on an available Android device/emulator; otherwise clearly separate listing/download verification from device install verification.
8. Work on `main`. Preserve concurrent work. Do not reset, discard, rebase, force-push, or overwrite unexplained changes. When ready, commit all nonignored tested state in the shared worktree and push `main` to origin. Never commit build output, keystores, passwords, tokens, or temporary publisher files containing sensitive values.
9. Post meaningful task progress comments after the implementation path is confirmed, after the release APK is built/validated, and after publication verification. Do not post raw logs. The manager session will mirror concise milestones to the originating chat thread.
10. On completion, post a self-contained task handoff and move the task to `review`.

## Acceptance evidence

The final task handoff must include:

- git commit and pushed branch;
- package ID, version name, and version code;
- release APK filename, size, and SHA-256;
- Android signing certificate SHA-256 fingerprint and proof it is not the debug certificate;
- exact validation commands and results;
- Rick publisher npub and published application/release/asset event IDs;
- relay/indexer acceptance evidence;
- public Zapstore listing/install URL when one exists, otherwise exact Zapstore search instructions tested against the public catalog;
- device/emulator install evidence, or a precise statement that only catalog/download verification was possible;
- any narrowly scoped capability/tooling blocker that remains.

Do not claim success merely because `zsp` exited zero. Success means the published catalog state independently matches the built, release-signed APK and Pete has a usable path to install it.
