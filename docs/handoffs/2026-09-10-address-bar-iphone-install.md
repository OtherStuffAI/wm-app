# Push main and install address-bar update on attached iPhone

Pete explicitly asks: “can you nsure this is pushed to main and install this on the attached iphone”. This authorizes normal Git main push and signed app build/install/launch on the attached iPhone. No TestFlight/App Store upload, uninstall/data wipe, Autopilot restart or signing identity changes.

Repo /Users/mini/code/wm/wmapp. Task 74221975-27da-4b25-ba45-dd56aaf5fcf1 in workspace 2e5caefd-dd65-45d2-b747-ee874e8e5fc9, scope 76d518f7-c477-4374-bf74-5d36fda570ed, channel d8d00881-ac84-41eb-ab0d-2c2afb77ddf3, thread 8687ace2-9047-4b98-933e-940ad22c1bbd. Source @[Install request](mention:message:1f4b63b0-2fed-44a9-b7fb-3e6073fbe32b). Read task/comments; manager handles thread replies and final review-state.

Previous implementation 7d673f8c062a010c23c2d69687a6f2cff480057e is on main. Tab changes keep address hidden; active-tab click reveals it. 38 browser/focus tests and changed-file analyzer passed. See docs/handoffs/2026-09-10-address-bar-explicit-reveal.md.

Inspect current main and repo instructions, preserve concurrent work. Default main, commit all nonignored tested state including this brief, no resets/reverts/force pushes. Verify configured canonical remote/upstream and push main (keep GitHub and Forgejo remotes intact); report exact remote hashes and inclusion of 7d673f8. If both are normal maintained mirrors, update both. Do not change deployed branch.

Use existing iOS device build/signing/install workflow, inspect current device list and signing rather than assuming historical failures. Repo has build_ios_release.sh, tools/ios, docs/handoffs iOS validation records. Peter iPhone15 Pro historical ID 8A1C111C-F340-5C1A-B609-B022E9B7D832 is a clue only; verify attached device now. Build signed release/profile suitable for standalone phone launch (avoid debug-only launch dependency), install in place preserving data, launch and check process/app presence. Record commands and exact logs, bundle/version/build, built commit, device name, signing/install/launch evidence and any interaction verification limits. Do not claim UI behavior physically tested unless observed. If phone is locked/trust/signing needs user input, finish independent push/build work then report precise blocker; no key extraction or bypass.

Set session goal to successful push plus attached iPhone installation verification, next-action reflect while working and stop on terminal handoff. Report meaningful milestones in session commentary for manager supervision. Post evidence to task via broker MCP if accessible; no chat reply. Return final evidence through supervised callback.

## Installation evidence — 2026-09-10

Outcome: signed release installed in place and launched on Peter’s iPhone.
GitHub main push succeeded. Forgejo fetch/push attempts returned HTTP 503;
its current hash and maintained-mirror status could not be verified. Both remote
URLs and main's origin/main upstream were preserved; no deployed branch changed.

Built WMAPP commit: `f3867fc54f37a35c7938baca4864bac4afcabcc7` (clean source
worktree), including `7d673f8c062a010c23c2d69687a6f2cff480057e`. The former
adds this installation brief to the reviewed implementation. The subsequent
handoff commit changes only this document, so it does not require an app rebuild.
No source or lockfile changes resulted from the build.

Remotes:

- `origin`: `https://github.com/OtherStuffAI/wm-app.git`; main initially
  `ea06d8823a578d490bb93b7ccfc2f3730bd26efb`, pushed and read back as
  `f3867fc54f37a35c7938baca4864bac4afcabcc7` before the build. Final handoff
  commit hash is recorded in the task comment and supervised callback.
- `forgejo`: `https://forgejo.otherstuff.studio/wm-pete/wmapp.git`; no local
  Forgejo tracking refs, live hash unavailable. `git ls-remote` and normal
  `git push forgejo main` failed with `The requested URL returned error: 503`.
  No force push, reset, revert, remote edits, or service restart attempted.

Build command from repository root (exit 0):

```sh
set -o pipefail
./build_ios_release.sh 2>&1 | tee /tmp/wmapp-address-bar-install-20260910/signed-release.log
```

The wrapper built all three native Rust release targets and the XCFramework,
then built and verified Flight Deck dist from upstream main
`f7bc51c1d52dd5a6ff49bb75cf308f466a3df38b`, build **1924**, ID
`wmapp-f7bc51c1d52d-1924`. Generated assets are ignored by Git. Flutter pub get
and `flutter build ios --release` passed. Output: `Xcode build done. 29.5s`;
`Built build/ios/iphoneos/Runner.app (40.3MB)`. Toolchain: Xcode 26.3 (17C529),
Flutter 3.44.4, Dart 3.12.2, Rust 1.98.0. Nonfatal Vite chunk/import warnings
and newer dependency notices are in the build log.

Binary: `app/build/ios/iphoneos/Runner.app`, bundle
`com.wingmanbefree.wingmanApp`, version **0.1.6**, build **7**, arm64 release.
Extension: `com.wingmanbefree.wingmanApp.FipsPacketTunnel`, same version/build.
Both pass `codesign --verify --deep --strict --verbose=2`, reporting `valid on
disk` and `satisfies its Designated Requirement`. `codesign -dvv` shows the
existing Apple Development identity (76V7H4Y22U), team **N5DRUM6S94**. No signing
identity or account changes were made.

Embedded profiles, inspected using `security cms -D -i <bundle>/embedded.mobileprovision`:

- Runner `65603417-1e61-48b6-ac35-91cd8f6d96b9`, expires 2027-09-09 07:53:34 UTC.
- Extension `27d85918-f57d-48eb-b66c-de22309717b7`, expires 2027-09-09 07:53:36 UTC.
- Both explicitly match their App IDs, contain this device, and include
  `packet-tunnel-provider` in the Network Extension entitlement.

SHA-256:

- Runner executable: `29513f8d2fc460f318aa0d132f4014311d0dde0cc0cb81b74737a5fb1206f4b7`.
- Compiled Flutter App.framework/App: `853e5fca2183caa2b0deb7f13fa43f3f9e9d7829119303ae5574ecb7f78d1f63`.
- Extension executable: `6758783c4b5a771c8efa080d22f3b5170676d55b26ec7a36a4d481dc333c3037`.
- Packaged Flight Deck version.json: `f24c6bb083591b303905af3982d13e5ea9d7c42de7450cdb9f5cddeff55fb061`.

Device freshly verified with `xcrun devicectl list devices` and
`xcrun devicectl device info details --device <id>`: **Peter’s iPhone**, iPhone
15 Pro (iPhone16,1), iOS **26.6.1 (23G83)**, ID
`8A1C111C-F340-5C1A-B609-B022E9B7D832`. Paired over wired USB, connected,
Developer Mode enabled. Existing Wingman App 0.1.6 (7) was present before
installation. The same bundle was installed in place; no uninstall/data wipe.
User data contents were not inspected.

Exact install and launch commands (both exit 0):

```sh
xcrun devicectl device install app --device 8A1C111C-F340-5C1A-B609-B022E9B7D832 app/build/ios/iphoneos/Runner.app --json-output /tmp/wmapp-address-bar-install-20260910/install.json
xcrun devicectl device process launch --device 8A1C111C-F340-5C1A-B609-B022E9B7D832 com.wingmanbefree.wingmanApp --json-output /tmp/wmapp-address-bar-install-20260910/launch.json
xcrun devicectl device info apps --device 8A1C111C-F340-5C1A-B609-B022E9B7D832 --filter "bundleIdentifier == 'com.wingmanbefree.wingmanApp'" --json-output /tmp/wmapp-address-bar-install-20260910/apps-after.json
xcrun devicectl device info processes --device 8A1C111C-F340-5C1A-B609-B022E9B7D832 --json-output /tmp/wmapp-address-bar-install-20260910/processes.json
xcrun devicectl device info processes --device 8A1C111C-F340-5C1A-B609-B022E9B7D832 --json-output /tmp/wmapp-address-bar-install-20260910/processes-recheck.json
```

Install output reports `App installed`, bundle ID above, bundle directory
`/private/var/containers/Bundle/Application/4829D234-F0D7-4F4B-9228-034038983C18/Runner.app/`,
database sequence **2156**. Launch at **14:17:01 Australia/Perth** reports
`Launched application with com.wingmanbefree.wingmanApp bundle identifier.`
Launch JSON gives **PID 4763**, `activatedWhenStarted: true`, `startStopped:
false`, no debugger attached. Both subsequent process listings contain that
exact PID and installed executable path. Post-install app listing confirms
0.1.6 (7) at the new bundle path. This validates release standalone process
launch; it does not establish rendered UI correctness or physical tab behavior.

Logs and structured evidence are in `/tmp/wmapp-address-bar-install-20260910/`:
`signed-release.log`, `binary-signing.log`, `signing-identities.log`,
`profiles-summary.json`, `devices.{json,log}`, `device-details.{json,log}`,
`apps-before.{json,log}`, `install.{json,log}`, `launch.{json,log}`,
`apps-after.{json,log}`, `processes.{json,log}`, `processes-recheck.{json,log}`,
`push-origin.log`, `push-forgejo.log`. JSON app/process listing filters are
applied by inspection; CoreDevice JSON can include additional installed apps.
Raw device records stay local; no private keys were read or exported.

Validation inherited from the unchanged implementation: changed-file analyzer
passed and all 38 browser/focus widget tests passed, as recorded in the explicit
reveal handoff and accepted by the manager. Not rerun for documentation-only
changes. `git diff --check` passed. No physical UI interaction observed: Pete
should switch tabs (address stays hidden), click the active tab (reveals), and
switch while editing (hides). No VPN or authenticated WApp acceptance claimed.
No TestFlight/App Store upload, phone data wipe, signing change, or restart.

Task comments were read and evidence posted through broker MCP. CLI task show
was denied with `NIP-98 origin is not allowed`. Manager retains task review
state and thread replies; worker returns evidence via supervised final callback.
