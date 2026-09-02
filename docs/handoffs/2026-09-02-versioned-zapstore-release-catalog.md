# Add a versioned local Zapstore release catalog for WMAPP

## Goal

Replace the single mutable Zapstore release handoff with a safe, versioned local catalog that the publisher WApp can discover. Prepare the current signed `0.1.3+4` release as the first catalog entry. Do not publish, upload, request Nostr signatures, or restart any registered app.

## Context

- Work in `/Users/mini/code/wm/wmapp` on `main`.
- Current source is clean and pushed at `55c70a8063a95de5d84c739f2534eda775b7dece`.
- The signed canonical APK and extracted icon are in `app/build/app/outputs/flutter-apk/`.
- Current release is package `com.wingmanbefree.wingman_app`, version `0.1.3`, code `4`, ARM64 only, min SDK `24`, target SDK `36`.
- Established certificate SHA-256: `6c0da09b9e2375d657645f197419be7b8227a7434e0225512fc760cedf383c8c`.
- Current APK SHA-256/size: `6cc03c139b2e102f5f9402b71aa7e8e1dab901ba3052e665ab2134de36fc4aa8` / `34700798`.
- Current icon SHA-256/size: `07f70806879d675490e4650eaad8b4f92669ec9628b9b1d36f771256087f4468` / `20459`.

## Required design

1. Add a repo-owned preparation command/script that snapshots a validated signed release into an ignored local catalog rooted at `app/build/zapstore-releases/`.
2. Use stable release directories such as `0.1.3+4/` containing `release.json`, `app-release.apk`, `app-release_icon.png`, and a versioned release-notes copy.
3. `release.json` must be non-secret and include at least: schema version, stable release ID, creation timestamp, source Git commit, package ID, version name/code, platform/ABI list, min/target SDK, certificate SHA-256, and each file's relative filename, MIME type, byte size, and SHA-256. Include release-notes hash.
4. Derive and validate metadata from the actual APK using available Android/Zapstore tooling. Do not trust command arguments for package/version/code/SDK/ABI/certificate.
5. Preserve certificate continuity against the established expected certificate. Fail closed on a different certificate, invalid signature, unexpected package ID, absent ARM64 FIPS library, missing VPN service declaration, or inconsistent metadata.
6. Make snapshot creation idempotent. Re-running an identical release may preserve the original `createdAt`; attempting to replace an existing release ID with different bytes/metadata must fail rather than overwrite history.
7. Use atomic staging/rename so incomplete catalog entries are never discoverable. Do not print or inspect signing secrets.
8. Document how future releases are prepared after `build_android_release.sh`, including where creation dates and release IDs appear.
9. Generate and validate the current `0.1.3+4` catalog entry locally. The generated build/catalog output should remain ignored; commit the reusable script, docs, and tests only.

## Validation

- Script/unit tests cover successful manifest generation, idempotence, and refusal to overwrite a release ID with changed input.
- Generated current manifest and files match the exact hashes/sizes above and the established certificate.
- Manifest creation date is a valid ISO timestamp and source commit is `55c70a8063a95de5d84c739f2534eda775b7dece` or the final release-preparation commit if the script intentionally records the current source after these tooling changes; explain the choice.
- Existing Flutter, Android, and FIPS validation is not weakened. Run proportionate relevant tests and `git diff --check`.

## Git and handoff

- Preserve concurrent work and commit all nonignored tested state on `main` with a Conventional Commit, then push `origin/main`.
- Do not commit APKs, secrets, keystores, passwords, or generated catalog output.
- Return commit/push evidence, command usage, generated catalog path, manifest summary, and validation results.
