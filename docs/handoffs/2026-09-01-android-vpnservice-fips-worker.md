# Android embedded FIPS via VpnService

Status: implemented; ARM64 device/WebView validation outstanding
Date: 2026-09-01
Repository: `/Users/mini/code/wm/wmapp`
Branch: `main`

## Goal

Implement Android support for WM-App's bundled FIPS runtime by embedding the
official FIPS v0.5.0 Rust crate and attaching its app-owned TUN interface to an
Android `VpnService`. A user must not install a separate FIPS application or
daemon. This phase exists to validate FIPS's official embedded interface in the
real WM-App client while preserving the desktop implementations.

## Authoritative inputs

- Official FIPS tag `v0.5.0`, annotated tag object
  `62999c7dbdca53cfd199b062a025af4c00c23a2e`, peeled source commit
  `80f8f965aa872296edbce84ade9949ece2596602`.
- Official embedding contracts in that source:
  `Node::enable_app_owned_tun()`, `Node::dns_local_addr()`, and
  `Node::enable_app_owned_udp_fd()`.
- Official release notes state that Android is an embedded crate target: the
  host owns the TUN, filters it to `fd00::/8`, clamps outbound TCP SYN MSS, and
  proxies tunnel DNS payloads to the built-in resolver returned by
  `dns_local_addr()`.
- `https://github.com/k0sti/fips-android` at
  `759f9da7ba82ff446ec826b33670cc09bc0daf39` is useful MIT-licensed prototype
  evidence, not the authoritative dependency. It demonstrates UniFFI,
  `VpnService`, persistent app-private identity, TUN packet pumps, and DNS
  interception. Audit and adapt code rather than copying assumptions.
- The existing desktop PoC and exact `.fips` URL behavior are documented in
  `docs/handoffs/2026-09-01-bundled-fips-wapp-poc.md`.

## Critical WM-App-specific distinction

Do **not** call `VpnService.Builder.addDisallowedApplication(packageName)`.
That is acceptable in the standalone reference node but would exclude
WM-App's own Android WebView from the mesh. Instead, arm
`Node::enable_app_owned_udp_fd()` before node start and call
`VpnService.protect(fd)` for every FIPS UDP transport descriptor it publishes.
WM-App/WebView traffic to the mesh must enter the VPN while FIPS's own transport
sockets bypass it, avoiding a routing loop.

## Required implementation

1. Add a reproducible Android native build pinned to official FIPS v0.5.0.
   Build an arm64 Android shared library and generated Kotlin/JNI or UniFFI
   bindings as part of the repository build. Do not depend on a separately
   installed node or an unpinned Git branch. Keep generated artifacts and cache
   policy explicit; never vendor an identity or secret.
2. Add a native Android service extending `android.net.VpnService`, correctly
   declared with `BIND_VPN_SERVICE` and foreground-service requirements. Route
   only FIPS mesh traffic (`fd00::/8`) plus the deliberately chosen DNS
   interception address. Preserve normal internet routing.
3. Persist a dedicated FIPS machine identity in Android app-private storage.
   It is separate from the WM-App Nostr signer identity and must never enter
   Flutter state, argv, logs, test snapshots, or user-facing diagnostics.
4. Start the Rust node using the official lifecycle order: create the node,
   arm app-owned TUN and UDP descriptor publication, establish/own the Android
   TUN after `VpnService.prepare()` consent, start the node, read
   `dns_local_addr()` in its valid window, protect every FIPS transport socket,
   and run the packet loops. Teardown and repeated start/stop must be safe.
5. The TUN adapter must enforce the upstream contract: only IPv6 packets whose
   destination is in `fd00::/8` enter FIPS, and outbound TCP SYN MSS is clamped
   to the safe FIPS transport value. Mesh-to-app packets return through the TUN.
6. Intercept `.fips` DNS packets arriving on the TUN, proxy only the DNS payload
   to the official built-in resolver at `Node::dns_local_addr()`, and splice the
   reply back with correct IP/UDP headers and checksums. Non-FIPS DNS and public
   internet traffic must not be captured by FIPS.
7. Configure the existing Wingman rendezvous app/scope and authenticated pinned
   bootstrap without overwriting an existing Android FIPS identity:
   `npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98` at
   `217.77.8.91:2121` over UDP with `auto_connect`.
8. Add a narrow platform channel between Flutter and Android for inspect,
   consent/start, stop/repair, peer status, and probe. Update
   `FipsRuntimeService` so Android uses this native channel instead of the
   desktop process/installer path. Opening an exact FIPS app link should invoke
   VPN consent once when required, await usable runtime/bootstrap state, then
   continue the existing exact-origin trust and normal-tab flow.
9. Keep Android cleartext enabled only as already required for exact
   `http://<npub>.fips:<port>/` WApps. Do not weaken NIP-07/NIP-98 trust:
   exact-origin approval remains required and wildcard `*.fips` trust is not
   acceptable.
10. Investigate Android System WebView/Chromium's known AAAA suppression on a
    ULA-only VPN. The implementation is complete only if the embedded WM-App
    WebView can load an exact `.fips` WApp URL, or if the native FIPS interface
    is fully implemented and the remaining Chromium behavior is isolated with
    a deterministic failing test and precise handoff. Do not silently replace
    the browser-visible hostname with an IPv6 literal because that changes the
    origin and breaks exact-origin trust. NAT46 is out of scope unless it is
    proven necessary and can be implemented safely in this pass.
11. Update Android deployment/runtime documentation, including VPN consent,
    persistent notification, coexistence with other Android VPN apps (Android
    permits one active VPN per user/profile), build prerequisites, and honest
    device-validation status.

## Acceptance and validation

- Rust/native tests cover app-owned TUN packet direction, `fd00::/8` filtering,
  MSS clamping, DNS proxying, identity persistence without disclosure, and
  repeatable teardown.
- Kotlin tests cover VPN builder/service lifecycle and method-channel state
  mapping where feasible without a device.
- Flutter tests cover Android runtime states, single consent/start operation,
  failure/cancellation, bootstrap wait, and unchanged desktop behavior.
- Run `flutter analyze` and the complete Flutter test suite.
- Build a debug ARM64 APK through the repository's supported build command.
- If an Android device/emulator is connected, install it and capture evidence
  for VPN consent, node npub/status, bootstrap connection, and an exact FIPS
  WApp request. If none is connected, report that hardware smoke test as
  outstanding rather than claiming success.
- No FIPS private key or WM-App signer secret appears in Git, logs, process
  arguments, generated test artifacts, or user-facing status.

## Work and Git rules

- Work directly on `main` and preserve concurrent work.
- Inspect the full worktree before committing. Include all nonignored tested
  state unless there is a clear safety conflict; do not reset, discard, or
  overwrite unknown changes.
- Use Conventional Commits, push `main`, and report the commit, tests, APK path
  and checksum, device evidence, and any exact remaining blocker.
- Do not restart Autopilot or another registered process.

## Implementation result

WM-App now builds an ARM64 JNI bridge against the official pinned FIPS source,
owns a split-tunnel `VpnService`, protects each published UDP descriptor, keeps
the dedicated identity in app-private storage, proxies only `.fips` DNS payloads
to `dns_local_addr()`, and preserves exact browser origins. Host native, Kotlin,
and Flutter coverage is present for the narrow contracts.

No Android target was connected during implementation. The device checks in
the deployment document remain outstanding, including the known Chromium AAAA
suppression question. This is not represented as successful WebView evidence.
