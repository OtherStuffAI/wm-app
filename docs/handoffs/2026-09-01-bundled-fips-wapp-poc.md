# Bundled FIPS WApp access PoC

Status: implementation brief
Date: 2026-09-01

## Goal

Make the macOS WMapp bundle and manage its own FIPS v0.5.0 client runtime so a
user who unlocks the existing signer can open an Autopilot-managed WApp at:

```text
http://<autopilot-fips-npub>.fips:<app-port>/
```

The WApp must load at `/` through FIPS and retain the existing `window.nostr`
login flow. Tower is excluded from this PoC.

## Scope and constraints

- First supported client: macOS WMapp.
- Use the upstream FIPS v0.5.0 macOS daemon/package design. FIPS requires a
  system launch daemon, TUN setup, and `/etc/resolver/fips`; simply spawning an
  unprivileged child from the Flutter process is not a correct implementation.
- Bundle the pinned FIPS installer or pinned built binaries/package in the
  WMapp build output. The user must not separately download or preinstall FIPS.
- A deliberate WMapp action may invoke the macOS authorization/install UI to
  install or repair the bundled privileged service. Do not hide or bypass the
  privilege boundary.
- Never copy a FIPS private key into Flutter config, logs, argv, or the WMapp
  Nostr signer vault. FIPS machine identity and WMapp user/device identity are
  separate.
- Do not claim iOS or Android support in this PoC. FIPS v0.5.0 has no iOS port;
  Android embedding can be a later phase.

## Required implementation

1. Add a reproducible build/package step pinned to FIPS `v0.5.0` that places
   the macOS FIPS installer payload in the `.app` bundle. Avoid committing
   architecture-specific generated binaries unless the repository's release
   practice requires it; verify source/artifact checksums.
2. Add a small `FipsRuntimeService` abstraction that can report at least:
   `notBundled`, `notInstalled`, `installRequired`, `starting`, `running`,
   `degraded`, and `failed`.
3. Add a setup/status UI action to install or repair the bundled system FIPS
   service through macOS authorization, then inspect it through `fipsctl`.
   Do not silently restart an unrelated running service.
4. Add `probe(npub)` and expose useful diagnostics without secrets.
5. Allow navigation to `http://<npub>.fips:<port>/` in the embedded WebView.
   Add the minimal macOS WebView transport policy needed for FIPS HTTP.
6. Preserve signer safety. NIP-07 injection can continue to use the existing
   per-request prompts. NIP-98 must require explicit trust of the exact FIPS
   origin; never globally trust `*.fips`.
7. Add an `Open FIPS app` flow that accepts/validates either an exact `.fips`
   HTTP URL or a small descriptor containing node npub, port, and URL. It must:
   verify FIPS is running, optionally probe the node, request exact-origin
   trust, then open a normal browser tab.
8. Show a small FIPS transport indicator for `.fips` tabs so the end-to-end test
   is observable.

## Validation

- Unit-test `.fips` URL validation, exact-origin trust, runtime state parsing,
  command construction, and secret redaction.
- Run Flutter tests and a macOS debug build.
- With two real FIPS nodes, unlock WMapp, open the Autopilot-provided FIPS URL,
  load the WApp at `/`, and complete its existing Nostr login.
- Stop the WMapp-owned FIPS service and confirm the same URL becomes
  unreachable; start it and confirm recovery.

## Git and reporting

Work on `main`. Preserve concurrent changes. When ready, commit all nonignored,
tested state in this worktree with a Conventional Commit. Do not restart any
registered Wingman/Autopilot process. Report platform-signing or privilege
blockers precisely.
