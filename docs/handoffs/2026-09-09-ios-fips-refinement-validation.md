# iOS FIPS event-driven refinement

Task `05cfb9b1-b6d8-42a7-a801-b197a00a78da` remains `in_progress` for manager
acceptance. This changes the existing WMAPP native implementation on main.
The original FIPS dependency, extension Keychain identity, exact `.fips` URLs,
split routing/DNS, scoped ATS and exact-origin signer approvals remain in place.
No Flight Deck/Tower/Autopilot or bridge contract change is involved.

## Reference comparison

Read source from the [Nostr VPN GitHub mirror at
7926f28843c24ceed55863c7511d798534436720](https://github.com/mmalmi/nostr-vpn/tree/7926f28843c24ceed55863c7511d798534436720).
The fetched mirror HEAD matched that revision; canonical upstream is git.iris.to.
The ignored checkout is `build/ios-fips/nostr-vpn-reference`.

| Reference files at that revision | Adopted pattern / WMAPP implementation |
| --- | --- |
| `ios/PacketTunnel/PacketFlowBridge.swift`, `PacketFlowBridgeLifecycle.swift` | Event-driven bounded batches, terminal failure, generation-aware reads. WMAPP uses a native readiness descriptor instead of retaining a Swift callback context in Rust. |
| `crates/nostr-vpn-app-core/src/c_abi/ios_packet_flow.rs`, `mobile_tunnel/ios_packet_flow.rs` | Explicit ownership on success/failure and terminal release. WMAPP Rust owns a bounded queue and socket-pair endpoints; Swift owns a duplicate closed in the dispatch cancellation handler. No foreign callback, object or packet pointer is retained. |
| `ios/PacketTunnel/PacketTunnelProvider.swift` | Independent physical Wi-Fi monitor alongside generic path monitoring; coalesced generation-scoped updates. WMAPP recreates the pinned core with the same identity; it has no verified equivalent of the reference's live-carrier refresh API. |
| `ios/Sources/PacketTunnelController.swift`, `PacketTunnelReplacementTransaction.swift` | Confirm disconnect before replacement; reject stale async completions. WMAPP operation tokens now protect preference loads and stop polling, and stop occupies the operation until disconnect/timeout. Existing repair already confirms disconnect. |
| `ios/README.md`, `scripts/mobile-ios-smoke.sh` | Separate host/simulator performance and lifecycle evidence from signed-device VPN acceptance. WMAPP adds an isolated production-pump host harness without disrupting the desktop fixed browser port. |

This is an independent implementation of the patterns, not copied Nostr VPN
source. Nostr VPN's MIT code was inspected but not incorporated. It uses
`nvpn-fips-core` / `nvpn-fips-endpoint` 0.4.72; WMAPP keeps isolated patched
jmcorgan/fips 0.5.0 at `80f8f965aa872296edbce84ade9949ece2596602`. No mesh enrollment,
private network, exit-node, full-tunnel, shared identity, or interoperability
claim is imported. Existing upstream FIPS licensing remains unchanged.

Architecture reviewed before changes: latest local `Wingman_Suite/wingman-suite-arch/v4`,
including the `excalidraw-scene.json` `.scene` wrapper, text and arrow bindings.
TowerSyncService remains the network/materialization owner, Dexie remains the
browser cache, and the UI consumes liveQuery. This change stays below those
boundaries in WMAPP's native runtime.

## Packet ownership and lifecycle

- Rust `Delivery` is one mutex-protected queue: 64 packets, 128 KiB, 4096-byte
  output-packet maximum. Mesh delivery and DNS replies use the same queue.
  Input TUN remains 64 × 1280 bytes; DNS requests remain 16 × 1280 bytes.
  The Swift OS-read callback retains at most 64 × 1280 bytes before dispatch.
- A single notification byte is present while output is nonempty. Queue
  insertion and clearing the byte on final dequeue share the same lock, so no
  producer/empty acknowledgement race can lose readiness. Full queues drop
  immediately. No polling thread or new per-packet Swift task is introduced.
- `wm_fips_output_descriptor()` transfers an owned duplicate; Swift never reads
  the byte. `wm_fips_output()` consumes packets and acknowledges empty atomically.
  `FipsOutputPump` drains at most 32 packets / 128 KiB per dispatch event. Remaining
  data keeps readiness asserted. A separate health timer runs every five seconds.
- Swift cancels its source before Rust stop, and closes the duplicate only in
  the dispatch cancel handler after any executing event. Repeated cancellation
  is harmless. Rust has no callback into Swift, so teardown cannot join a Rust
  callback that is waiting for the teardown queue. Rust queue closure rejects
  later producers; a future-owned drop guard signals EOF on node abort/panic.
- Generation checks prevent old sources/settings/path/read callbacks from
  delivering into a replacement. The one outstanding `packetFlow` read belongs
  to the provider and is never reset by a runtime restart. Its old batch is
  discarded before registering a current read.
- Rejected OS writes, invalid output, negative runtime input/output results and
  runtime death are terminal failures, not a connected-state success. Full
  bounded input queues drop packets; malformed/off-mesh packets are rejected.
- Startup timeout and underlay debounce use cancellable sources. Stop during
  pending settings invalidates the generation and completes start once. Rust
  startup itself is synchronous on the worker (up to its existing 15-second
  timeout); a stop queued during that call runs after it returns, before any
  later queued settings completion. It does not interrupt node initialization.
- Generic and physical Wi-Fi path updates each ignore their initial snapshot,
  then reschedule one one-second debounce, including same-interface updates.
  Restart stays on the lifecycle worker to avoid enqueueing an old restart
  behind a newer stop. Actual Wi-Fi/cellular recovery still needs a device.

## Reproduction and measured evidence

```sh
python3 tools/ios/prepare_core.py
./tools/ios/test_native.sh > ios-fips-refinement-native.log 2>&1
RUSTC="$(rustup which --toolchain 1.98.0 rustc)" \
  rustup run 1.98.0 cargo test --manifest-path crates/wmapp-fips-ios/Cargo.toml \
  live_authenticated_bootstrap -- --ignored --nocapture
./tools/ios/build_core.sh
cd app
flutter analyze
flutter test
flutter build ios --simulator --debug
flutter build ios --release --no-codesign
flutter build ipa --release --no-codesign
```

Run preparation and builds sequentially; preparation replaces the ignored
vendor source. Rust is pinned to 1.98.0 for host and all three iOS architectures.
The host link uses macOS frameworks and may warn about the host compiler's
macOS deployment-version mismatch; it runs on this supported macOS host, not on
an iPhone. The iOS libraries use the build script's iOS 13 deployment setting.

Measured production-pump host run (`ios-fips-refinement-packet-smoke.log`):

- Idle: **5.150 seconds, zero output reads, zero delivery batches** while the
  real Rust runtime is running. The removed 10 ms timer would schedule about
  500 drain attempts in five seconds. This measures output-delivery activity,
  not total process wakeups/CPU, VPN power, or iPhone battery use.
- Active: **272 packet DNS replies**, **257 batches**, largest batch **16**,
  **529 output reads**, including empty checks at batch completion. These are
  public DNS questions intentionally sent to the intercept address; every
  reply is checked as local REFUSED, with no public fallback.
- Stop: **one terminal EOF failure notification**, descriptor confirmed closed.
- Swift deterministic lifecycle checks: **1000** stop-during-start / replacement /
  stale-read cycles against the production lifecycle; **100** real dispatch
  cycles with 32-packet rejected-write batches, cancellation from within the
  callback and descriptor-close verification. No callback-to-stop deadlock.
- Rust unit suite: **10 passed**, including packet/byte backpressure, concurrent
  producers/close, DNS checksums/malformed input, repeated real node starts,
  failed/duplicate start, identity continuity, old descriptor EOF across restart,
  runtime abort and DNS-worker join. Separate explicit live test: **1 passed**,
  authenticated bootstrap plus `.fips` AAAA via packet DNS.

Host lifecycle state tests model the ordering of OS settings/read/path events;
they do not run Apple's VPN consent UI or claim physical underlay behavior.
The standalone harness links the production Rust library and Swift output pump.
Android was not rerun: no Android/shared Dart implementation or dependency
changed; the full Flutter regression suite still covers existing origins/trust.

## Final builds and device state

Final logs are retained locally; the exact source commit is reported in the task handoff.

| Check | Result / log |
| --- | --- |
| Rust host unit suite | 10 pass; `ios-fips-refinement-native.log` |
| Live authenticated bootstrap + packet AAAA | 1 pass; `ios-fips-refinement-live.log` |
| Swift settings / production lifecycle / output pump | Pass; `ios-fips-refinement-native.log` |
| Final repeated host idle/burst/EOF smoke | 5.064 seconds, 0 idle reads/batches, 272 replies, max batch 16; same native log |
| Flutter analyze / complete suite | Clean / 173 pass; `ios-fips-refinement-analyze.log`, `ios-fips-refinement-flutter-tests.log` |
| Rust release XCFramework | All 3 architectures pass; `ios-fips-refinement-core-build.log` |
| Simulator build | Pass; `ios-fips-refinement-simulator.log`; new descriptor ABI symbol confirmed embedded |
| Unsigned device release | Pass, 43.1 MB; `ios-fips-refinement-device.log` |
| Unsigned archive | Pass, 212.6 MB; `ios-fips-refinement-archive.log` |
| Signed build recheck | Blocked; `ios-fips-refinement-signing.log` |

Archive: `app/build/ios/archive/Runner.xcarchive`. Runner and embedded extension
are arm64, version **0.1.6 (7)**, both explicitly verified **unsigned**.
`ios-fips-refinement-linked-symbols.log` confirms all eight exported C entry
points in the actual archived extension, including `wm_fips_output_descriptor`.
No IPA/export/publication or physical installation was performed.

SHA-256 (also in `build/ios-fips/refinement-{core,archive}-hashes.json`):

| Artifact | SHA-256 |
| --- | --- |
| Device Rust static library | `47c686ae9495d219934f29bac1d8dbb78fd97905b30cab3378d55739c8ca6ff3` |
| Universal simulator Rust static library | `4ec06dcde2b1513fb97d6912b286698de21fba809cea4db08664ea16a7410363` |
| Archived FipsPacketTunnel executable | `4830d5e51d785aa79a9b19ef7ff0fce1907a041981045aa87f44cdd0beba5f65` |
| Archived Runner executable | `d5369e749a565cae282e3ba90e34cd3e18daaa41d8bd6ccbbe1a3751c5d6a5b8` |

Final September 9 signed build still reports:

- `No Accounts: Add a new account in Accounts settings.`
- Runner profile `iOS Team Provisioning Profile: com.wingmanbefree.wingmanApp`
  and extension wildcard profile `iOS Team Provisioning Profile: *` do not
  include Network Extensions capability or
  `com.apple.developer.networking.networkextension`.

Team **N5DRUM6S94** and bundle IDs were preserved. Required user step: restore
the authorized account in Xcode Settings → Accounts and provision both explicit
App IDs for Packet Tunnel, then reconnect/unlock the known iPhone and rebuild
signed. The final `devicectl` check reports Peter's iPhone 15 Pro
`8A1C111C-F340-5C1A-B609-B022E9B7D832` **unavailable** (changed from the earlier
implementation run). An available iPad was not substituted. See
`ios-fips-refinement-devices-final.log`.

Simulator rendered UI was not re-claimed: current desktop WMAPP still owns
`127.0.0.1:47831` (PID 67076 at check). It was left running. The reference's
clean-install/device-network-creation scripts were not run against Pete's apps
or devices. This task's simulator result is a build/linked-runtime result.

Still unperformed: physical VPN consent/refusal/retry, exact `.fips` WApp and
Nostr login, ordinary HTTPS/DNS during VPN, lock/background and reboot identity
behavior, Wi-Fi/cellular/offline recovery, existing VPN interactions, extension
memory and battery. Host/simulator evidence does not satisfy those checks.
Follow the physical checklist in `docs/deploy/ios-fips.md` after signed install.

Pre-existing reviewer-owned `docs/fips-tower-bridge-handoff-2026-09-09.md` and
`tools/fips_bridge/` were preserved untouched and untracked. The manager's
refinement brief is retained in the accompanying source commit. No destructive
Git/history operation, Autopilot restart, phone data clearing or account/team
substitution occurred. Task state remains `in_progress`; the manager owns
acceptance and the originating chat reply.
