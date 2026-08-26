# WMAPP privacy audit, public-repository conversion, and Zapstore publication

## Outcome

Audit `OtherStuffAI/wm-app` before public exposure. If the repository and its reachable Git history contain no material privacy leak or secret—or only a small, safely contained current-tree issue—remediate it, verify the result, make the GitHub repository public, and complete the already prepared broker-signed Zapstore release.

This continues @[Publish signed WMAPP Android release to Zapstore](mention:task:4cccad9c-82a0-4723-a6c5-66190cc51faf) from Pete's approval in @[Message](mention:message:6f2d38dc-93fc-43be-932b-e493d3c637ca), in Flight Deck thread `8633e75e-3a33-47d4-9e40-b19bb1aeac43`. Pete's phrase “happy to make this private” is interpreted in context as approval to make the currently private repository **public** after a clean audit; the preceding messages explain that public access is the remaining Zapstore prerequisite.

## Source of truth and current state

- Work only in `/Users/mini/code/wm/wmapp`, on `main`. The older `/Users/mini/code/wingmanbefree/wm-app` checkout is superseded.
- Read the task and all recent comments first.
- Read `docs/handoffs/2026-08-26-zapstore-android-release.md` in full; it contains the validated build, hashes, signing identity, failed upload evidence, and publication constraints.
- Starting source commit is expected to be `7d9e407`, clean and aligned with `origin/main`. Recheck rather than assuming.
- Repository is `OtherStuffAI/wm-app`, currently private. The public raw URL for `zapstore.yaml` currently returns 404 and Zapstore's first-publisher verification rejects the Rick-signed upload.

## Privacy and secret audit

Audit both the current tracked tree and all reachable Git history before changing visibility. Use reputable secret scanners already available locally (for example `gitleaks` or `trufflehog`) plus targeted Git/path searches where useful. Do not install or invoke an unreviewed scanner that uploads repository content. Do not print a discovered secret value into the terminal transcript, task comments, commit messages, or handoff; report only a masked identifier, category, path, and commit.

At minimum, check for:

- Nostr nsecs/raw private keys, bunker or NWC connection strings, capability tokens, API keys, passwords, cookies, auth headers, signing secrets, and private certificates;
- Android/Java keystores, signing property files, `.env` files, credentials, backups, archives, generated publisher payloads, logs, database dumps, and build artifacts;
- private email/address/phone information or other personal data;
- internal-only hostnames, IPs, URLs, infrastructure details, operator notes, test fixtures, screenshots, or architecture/configuration whose publication would materially expose private systems;
- secrets removed from the current tree but retained in reachable commits, tags, or non-default branches available from the origin;
- ignored and untracked local files that are sensitive but safely absent from Git. Confirm the durable Android keystore/password remains outside Git without displaying it.

Also inspect repository-level exposure that changes with visibility where accessible: releases/assets, Actions workflow/configuration, branch contents/tags, GitHub Pages, wiki/issues/discussions defaults, and any obvious submodule/LFS references. Avoid dumping GitHub secret names or values unnecessarily.

Classify findings:

1. **Clean / harmless public information:** proceed.
2. **Easy contained issue in the current tree with no secret history or broad side effects:** fix it, add an appropriate ignore/example/documentation guard, validate, commit, push, then proceed.
3. **Material secret/private data anywhere in history, or remediation requiring credential rotation, history rewrite, branch/tag deletion, force-push, or consequential product/configuration changes:** do not make the repo public. Stop at a precise blocker and report the affected paths/commits/categories without exposing values.

## Git and visibility rules

- Preserve concurrent work. Do not reset, discard, rebase, rewrite history, force-push, or overwrite changes you do not understand.
- Default to `main`. If fixes are required, run proportionate tests and commit/push all nonignored tested worktree state, excluding any sensitive/generated artifacts.
- Pete has explicitly authorized changing `OtherStuffAI/wm-app` from private to public only after the audit passes. Verify the exact repository target and current visibility immediately before mutation. Use the supported GitHub CLI/API visibility operation and its explicit consequence acknowledgement; do not touch another repository.
- After mutation, independently verify GitHub reports `PUBLIC` and unauthenticated retrieval of `https://raw.githubusercontent.com/OtherStuffAI/wm-app/main/zapstore.yaml` returns the committed file with HTTP 200.

## Zapstore publication retry

After public verification, resume the official `zsp`/broker-only workflow documented in the existing handoff:

- Publisher identity: Rick, `npub1llwrq3rtah3rg3r2dyfyht55ek7aa0ey7z47ujju407pzfp38shqa7zcvr`.
- Never search for, export, print, persist, or use an nsec, raw key, bunker URI, NWC secret, or capability token. Do not use Pete Tier 2. Use the session's Autopilot broker-aware signing/publishing tools only.
- Required Nostr kinds are Blossom authorization `24242`, application `32267`, release `30063`, and asset `3063`.
- Validated package/build: `com.wingmanbefree.wingman_app`, `0.1.2` code `3`, APK `app-release.apk`, size `21,631,286`, SHA-256 `79d0360a1c429459b5ac753f07441f3cb62f28aef7fed7c8835798ecd2353c2e`, certificate SHA-256 `6c0da09b9e2375d657645f197419be7b8227a7434e0225512fc760cedf383c8c`.
- Regenerate short-lived upload authorization and event outputs as necessary. Do not blindly reuse expired authorization or treat prior template/attempt IDs as published IDs.
- Upload APK and icon, then independently fetch and hash the public bytes before publishing release/asset events.
- Publish application/release/asset events only after their referenced blobs are publicly retrievable. Preserve exact event IDs and per-relay acknowledgement.
- Independently query/read back events and verify Zapstore catalog/search/install retrieval. Do not claim success from a command exit code alone. If no physical device is available, distinguish catalog/download verification from device-install verification.

## Reporting and task state

Post concise progress comments to the Flight Deck task after: (1) audit conclusion and visibility decision, (2) successful public verification/upload, and (3) final catalog/install verification or concrete blocker. Include the originating thread/message mention in the final handoff. Do not post directly to Pete's chat; the manager session owns that reply.

Move the task to `review` only after the public listing/download path is independently verified. If a material exposure or external Zapstore rejection remains, move it to `blocked` with exact, non-sensitive evidence and the smallest next decision/action.

Final evidence must include the audit scope/tools/results, any remediation and commit, pushed branch, verified repository visibility/raw metadata fetch, package/version/APK hash/certificate fingerprint, blob URLs and verified hashes, Rick's published event IDs/relay readback, Zapstore listing or tested search instructions, and whether device installation itself was tested.
