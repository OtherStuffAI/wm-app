# Flight Deck refresh and iPhone install attempt — 2026-09-09

Origin: @[Refresh and install request](mention:message:78acce71-7591-4493-8680-461d8738aff1).
Task `05cfb9b1-b6d8-42a7-a801-b197a00a78da` stays `in_progress` for manager review.

## Outcome

Refreshed and packaged latest committed active Flight Deck main (build 1915). Signed installation remains
blocked by Xcode account/profile provisioning. No install, launch, process or
rendered-screen pass is claimed. The existing phone app/data remain intact.

WMAPP started at `77d7b9223a1c8270547d930bc40a6c2668be54af` on main.
Fetched configured origin `https://github.com/OtherStuffAI/wm-app.git`:
`origin/main` is `1ff13d6e512989f38c7fc489b8d02d4413a79cdb`, eight commits behind
local main, zero ahead. Preserved local history; no integration or push needed.
The commit containing this report is the refresh source commit; its exact SHA is
posted in the durable task handoff.

## Flight Deck provenance

Configured local Flight Deck origin matches the default bundle URL
`https://github.com/OtherStuffAI/wm-flightdeck.git`. The wrapper’s fresh shallow
clone fetched **c868dcf419064fd8b82010aec2c07d6b49d7c7cc**, published build 1913.
A separate remote-head check matched. Before handoff the manager clarified that
latest means the newer committed active main, retaining the required FIPS
transport changes (task comment `3fc904d0-8ab0-4896-9fd5-f9d6e9c90b97`).

Final source is **0f7dccb2ef3042bd026fb1e5061b22e594faed96**, active Flight Deck main,
including `2809743` paired native Tower FIPS transport. Used a clean isolated
`git clone --no-hardlinks --single-branch --branch main` from
`/Users/mini/code/wm/flightdeck` into ignored
`build/iphone-refresh/flightdeck-source`; initial status was clean and HEAD exact.
Untracked local handoffs were excluded. Installed locked dependencies and built
fresh with explicit FLIGHT_DECK_DIR pointing only to this isolated clone.
No Flight Deck publication or modification of its active checkout occurred.

Final packaged build **1915**, ID **wmapp-0f7dccb2ef30-1915**, source-date timestamp
**2026-09-09T06:53:53.000Z**. This deterministic source time is not the build’s
wall-clock time. The intermediate 1913 package was superseded before commit.
The bundle retains FIPS transport UI; physical native Tower bridge support is
still unverified. The default remains published GitHub main and can lag active
committed main; docs explain explicit isolated-source selection for this case.

The release script already automatically builds the core, clones/builds/verifies
Flight Deck, bundles dist, runs Flutter pub get and builds signed iOS Release.
Added full fetched-commit logging; corrected the printed/documented artifact
path from Release-iphoneos to iphoneos. Fixed the bundle test fixture to stub
the newly added native-core preparation step.

## Commands and validation

```sh
env -u FLIGHT_DECK_DIR -u FLIGHT_DECK_PG_APP_NPUB \
  -u FLIGHTDECK_BUILD_NUMBER -u FLIGHTDECK_BUILD_ID -u SOURCE_DATE_EPOCH \
  ./build_ios_release.sh
# After signing failure and manager source clarification:
git clone --no-hardlinks --single-branch --branch main \
  /Users/mini/code/wm/flightdeck build/iphone-refresh/flightdeck-source
(cd build/iphone-refresh/flightdeck-source && bun install --frozen-lockfile)
FLIGHT_DECK_DIR="$PWD/build/iphone-refresh/flightdeck-source" \
  FLIGHT_DECK_PG_APP_NPUB=npub1hd37reqgfcnz3pvzj4grknd2nkzc94p9ercmunrxx22razr2rfxsw6dns5 \
  FLIGHTDECK_BUILD_NUMBER=1915 FLIGHTDECK_BUILD_ID=wmapp-0f7dccb2ef30-1915 \
  SOURCE_DATE_EPOCH=1788936833 ./tools/update_flightdeck_bundle.sh
cd app
flutter build ios --release --no-codesign
flutter analyze
flutter test test/flight_deck_update_manager_test.dart
cd ..
bash tools/test_update_flightdeck_bundle.sh
```

- Supported Release wrapper: core release builds pass for all three architectures;
  Flight Deck build/verify:dist pass (19 files, two asset references). Signed Flutter
  build exits 1 after 6.4 seconds of Xcode build, with No Accounts and both existing
  profiles lacking Network Extensions capability and networking.networkextension.
- Final isolated Flight Deck build and verify:dist pass; final unsigned Release
  exit 0 (40.1 MB, Xcode 6.3 seconds) and hashes below supersede the intermediate 1913 build.
- Bundle script suite passes all seven entry points, refresh failure propagation,
  source selection, transient-clone cleanup and release-number selection.
- Flutter analyze clean; nine update/fallback/archive/loopback tests pass.
  An initial command additionally named a nonexistent local_flight_deck_server
  test file and failed on loading that path; corrected invocation above passes.
- Shell syntax and git diff whitespace checks pass. Existing native behavioral
  suites were not repeated; core was rebuilt through the supported wrapper.

Logs and machine-readable evidence are retained in ignored `build/iphone-refresh/`:
`signed-release.log`, `unsigned-release-final.log`, `local-bundle.log`,
`local-dependencies.log`, `bundle-tests.log`,
`flutter-update-tests.log`, `flutter-analyze.log`, `package-evidence.json`,
`extension-symbols.log`, and `devices-{start,final}.{json,log}`.

## Actual packaged artifact

`app/build/ios/iphoneos/Runner.app`; Runner and embedded
`PlugIns/FipsPacketTunnel.appex` are arm64, version **0.1.6 (7)**.
`codesign -dvv` exits 1 for each: **code object is not signed at all**.
All eight native entry points including `wm_fips_output_descriptor` are present.
All 19 source bundle files match their packaged copies byte for byte under
`Frameworks/App.framework/flutter_assets/assets/flightdeck/`.

SHA-256 evidence:

| Item | SHA-256 |
| --- | --- |
| Packaged version.json | `bb2f0ae978a05561f7aaa778ef241d81cde830b7fdd55ab00f169ceb775004db` |
| Canonical complete Flight Deck hash manifest | `0aa66d6c8c3b45f57358e3abc2507e6c55b6d1885d1608116f9044625ff3b481` |
| com.wingmanbefree.wingmanApp executable | `40414e809b7935bcaa1e49164f7fe35119a461c5e0a6d0c9a9340607ac30263e` |
| com.wingmanbefree.wingmanApp.FipsPacketTunnel executable | `0ad6d75ed995c374d4d5bf3c9ffe76f6ac11f4d25f3040df37ff04a67586e34d` |

Manifest digest hashes UTF-8 JSON of the relative-path → file-SHA256 map, sorted
keys with comma/colon separators and no trailing newline. Full map is in
package-evidence.json.

## Device and exact remaining action

Start and final devicectl checks: **Peter’s iPhone**, iPhone 15 Pro (iPhone16,1),
**8A1C111C-F340-5C1A-B609-B022E9B7D832**, **available (paired)**.
Flutter identifies the same phone as `00008130-001824141442001C`, iOS 26.6.1
(23G83). No iPad or simulator substituted.

Restore the authorized existing account in **Xcode → Settings → Accounts**.
For existing team **N5DRUM6S94**, enable Network Extensions and provision explicit
App IDs `com.wingmanbefree.wingmanApp` and
`com.wingmanbefree.wingmanApp.FipsPacketTunnel`, both permitting
`com.apple.developer.networking.networkextension = [packet-tunnel-provider]`.
Then rebuild signed, verify both signatures/profile entitlements, install in
place to the exact devicectl ID above, and launch `com.wingmanbefree.wingmanApp`
without a debugger. Verify Runner remains present and visually confirm a rendered
first screen. Never install the unsigned artifact.

Remaining physical checks: consent/refusal/retry, authenticated bootstrap, exact
.fips WApp/Nostr login with origin approval, ordinary HTTPS/DNS, stop/restart/repair,
lock/background/reboot identity, Wi-Fi/cellular/offline recovery, another VPN,
diagnostics, memory and battery. Follow docs/deploy/ios-fips.md. Build success
is not evidence of working VPN/WApp traffic or a rendered phone screen.

Preserved reviewer-owned docs/fips-tower-bridge-handoff-2026-09-09.md and
 tools/fips_bridge/ untouched/untracked. No entitlement removal, team/account
substitution, uninstall/data clearing, remote publication, service restart,
desktop port 47831 change or history rewriting. Manager owns final acceptance
and originating thread response.
