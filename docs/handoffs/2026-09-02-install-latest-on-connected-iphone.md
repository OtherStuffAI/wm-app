# Install latest WMAPP on Pete's connected iPhone

## Goal

Build the newest safe committed `main` state of `/Users/mini/code/wm/wmapp` as a signed standalone iOS Release, install it on Pete's physically connected iPhone, launch it, and verify it remains running.

Flight Deck origin: @[Message](mention:message:82a9fb6e-075c-48cd-8351-c9503342f538) in thread `ce0e0f36-47c7-4fd9-820c-b7eae8d0170e`, workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`, channel `d8d00881-ac84-41eb-ab0d-2c2afb77ddf3`.

Tracking task: @[Install latest WMAPP on Pete’s connected iPhone](mention:task:48d6647e-f1bd-4110-bb6e-e073e9ffb90c). If the worker session cannot reach Flight Deck PG through its broker-bound environment, return all evidence in the supervised callback and let Rick update the task; do not search local Autopilot databases or delay the device handoff.

At intake, WMAPP `main` was clean at `a29c3b3` and matched `origin/main`. Reinspect before acting because other agents may work in this shared checkout.

## Execution

1. Read `docs/deploy/iphone.md` and inspect the current worktree, branch, HEAD, and remote relationship. Preserve concurrent work. Fetch and fast-forward `main` only if the remote is ahead and the worktree remains safe. Do not reset, discard, rebase, force-push, or overwrite unexplained changes.
2. Enumerate Flutter and Xcode devices. Select Pete's physically connected iPhone by name and identifier; do not use a simulator.
3. Run `./build_ios_release.sh` using the repository's existing Xcode signing configuration. Do not alter signing identities, provisioning data, or shared Xcode caches.
4. Install `app/build/ios/Release-iphoneos/Runner.app` using `xcrun devicectl device install app` for that exact physical device.
5. Launch `com.wingmanbefree.wingmanApp` with `xcrun devicectl device process launch` and verify that the app process remains present.
6. If device tooling permits, verify the first WMAPP screen renders. Otherwise report the exact one-step visual check Pete must perform on the phone. Do not leave `flutter run` or a debugger attached.
7. If blocked by phone lock, trust/pairing, Developer Mode, provisioning, signing, or device availability, stop after safe diagnostics and report the smallest exact user action required. Do not reset the phone or perform destructive cleanup.

## Reporting

Post useful milestones and final evidence to the Flight Deck task created for this request. Include:

- exact source commit, branch, remote relationship, and material worktree state;
- connected device name and identifier as reported by tooling;
- signed Release command/result and artifact path;
- install result;
- launch and process-presence evidence;
- visual verification status or the exact remaining manual check;
- any blocker and smallest next step.

Move the task to `review` only after installation and launch validation succeed. Do not push, publish external artifacts, restart services, or make unrelated code changes.
