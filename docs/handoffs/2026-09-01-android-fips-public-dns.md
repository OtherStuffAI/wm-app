# Android FIPS VPN public-DNS closeout

Audit current `main` after `2913ae186cc2a0b619750c4a61b5e01e49ee2f66` in
`/Users/mini/code/wm/wmapp`. This is a narrow correctness task.

## Confirmed concern to prove or fix

`FipsVpnService.Builder.addDnsServer(10.1.1.1)` advertises the synthetic server
to Android while `10.1.1.1/32` is routed through the TUN. Android may therefore
send ordinary public-name queries to that address even though public destination
IP routes bypass the VPN. The native adapter currently answers `.fips` queries
but drops DNS packets containing non-`.fips` questions. That can break ordinary
hostname resolution device-wide whenever the FIPS VPN is active.

Do not treat the `fd00::/8` IP split route as proof that DNS bypasses the VPN;
Android VPN DNS selection is a separate contract. Establish the behavior from
authoritative Android source/docs and the actual packet design.

## Required outcome

- If ordinary queries truly bypass `10.1.1.1`, provide precise authoritative
  evidence and add a host-testable regression that models the relevant contract.
- Otherwise implement safe public DNS preservation. `.fips` payloads must still
  go only to FIPS `Node::dns_local_addr()`. Non-FIPS queries must go to an
  appropriate underlying-network resolver without entering FIPS or looping back
  into the VPN, and replies must preserve correct headers/checksums. Avoid a
  casually hard-coded public resolver if Android can supply underlying DNS.
- Mixed-question queries must not leak `.fips` names to a public resolver. Return
  a deterministic local error or otherwise handle them safely.
- Add regression tests covering `.fips`, public, and mixed questions plus clean
  teardown/failure behavior.
- Re-run Rust fmt/clippy/workspace tests, Kotlin unit/androidTest compilation,
  Flutter analyze/tests, and the supported ARM64 APK build if production code
  changes. Inspect ABI/native library and report the final checksum.
- No Android target is attached: do not claim live DNS, VPN, bootstrap, or
  WebView validation. Keep a device test/instructions for ordinary public DNS as
  well as exact `.fips` WebView loading.

Work on `main`, preserve and commit all tested nonignored state (including the
current handoff-document modification), use a Conventional Commit, and push
`main`. Do not restart Autopilot or registered apps.

## Closeout

The concern was confirmed and fixed. Android documents `addDnsServer()` as
adding the VPN connection's DNS server, while `addRoute()` separately determines
which destination routes enter the interface. There is no documented split-DNS
exception based on the queried name. Because `10.1.1.1/32` is routed into the
TUN, ordinary queries selected for the VPN DNS server reach the native adapter;
the old non-`.fips` drop therefore could break system name resolution.

Authoritative Android contracts used for the fix:

- `VpnService.Builder.addDnsServer` adds a DNS server to the VPN connection:
  https://developer.android.com/reference/android/net/VpnService.Builder#addDnsServer(java.net.InetAddress)
- `VpnService.Builder.addRoute` controls destination routing independently:
  https://developer.android.com/reference/android/net/VpnService.Builder#addRoute(java.net.InetAddress,int)
- `DnsResolver.rawQuery` sends a raw DNS message on a specified `Network`:
  https://developer.android.com/reference/android/net/DnsResolver#rawQuery(android.net.Network,byte[],int,java.util.concurrent.Executor,android.os.CancellationSignal,android.net.DnsResolver.Callback)
- `LinkProperties.isPrivateDnsActive` says applications must not send
  unencrypted DNS while Private DNS is active:
  https://developer.android.com/reference/android/net/LinkProperties#isPrivateDnsActive()

WM-App now selects an internet-capable non-VPN underlying `Network`, also sets
it as the VPN's underlying network, and forwards public raw DNS messages through
Android's network-scoped `DnsResolver`. It does not choose a public resolver or
open a raw upstream DNS socket. All-`.fips` questions still go exclusively to
`Node::dns_local_addr()`. Mixed public/`.fips` questions are answered locally
with `REFUSED`; upstream failures are answered locally with `SERVFAIL`. All
responses are rebuilt with swapped IP/UDP endpoints and recalculated IPv4 and
UDP checksums. Android versions before API 29 and startup without a suitable
underlying network fail closed before the VPN becomes the device DNS path.

Host regressions cover all-`.fips`, all-public, and mixed classification and
resolver isolation; valid reply checksums; public resolver failure; TUN shutdown
with a full channel; and descriptor closure on startup failure. A device-only
instrumentation test now resolves a configurable ordinary public hostname while
the FIPS VPN is active. The existing test still loads the exact
`http://<npub>.fips:<port>/` WebView origin. Commands are in
`docs/deploy/android.md`.

Validation completed on 2026-09-01:

- `cargo fmt --all -- --check`
- `cargo clippy --workspace --all-targets --locked -- -D warnings`
- `cargo test --workspace --locked` (37 tests)
- Kotlin debug unit tests and debug androidTest Kotlin compilation
- Flutter analyze and all 85 Flutter tests
- signed ARM64 release APK build and APK Signature Scheme v2 verification
- packaged native library: ELF64/AArch64, with the expected JNI lifecycle
  exports; only `lib/arm64-v8a` is present

Artifact checksums:

- release APK SHA-256:
  `9c178aae324df3c3ae09d88c80cfadf2744c9766b23cbcae3c1c1955e0b4a5a4`
- packaged stripped `libwmapp_fips_android.so` SHA-256:
  `3c705e3ba00a97869ffdd1eac1caab2b3c8867700de659ec877e3dbfcdd98c10`

No Android device or emulator was attached. Public DNS, VPN consent/lifecycle,
bootstrap connectivity, and exact `.fips` WebView loading were not run live and
remain device validation items.
