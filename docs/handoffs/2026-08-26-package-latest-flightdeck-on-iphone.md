# Package latest Flight Deck in WMAPP and install on Pete's iPhone

## Goal

Build the latest committed Flight Deck from `/Users/mini/code/wm/flightdeck`, embed that build in `/Users/mini/code/wm/wmapp`, produce a signed iOS Release, install it on Pete's connected physical iPhone, launch it, and verify that it remains running.

Origin: @[Message](mention:message:5c9591f5-19f6-4e2c-a4d3-b9884e61532d) in @[Channel](mention:channel:d8d00881-ac84-41eb-ab0d-2c2afb77ddf3), thread `43594e0c-52ec-4f7a-a1f6-b3978ba85a06`, workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`.

Tracking task: @[Package latest Flight Deck in WMAPP and install on Pete’s iPhone](mention:task:5f760578-d918-4e1d-a1b4-643850a349e2).

At manager preflight:

- Flight Deck was clean on `main` at `28396b2` (`fix(inbox): clarify attachment source actions`).
- WMAPP was clean on `main` at `1a8cc16` (`fix: set Pete as Zapstore publisher`) before this handoff file was added.
- The established physical-device path is documented in `docs/deploy/iphone.md`.
- Prior device evidence identifies Pete's phone as **Peter's iPhone**, iPhone 15 Pro, with UDID `00008130-001824141442001C`; re-enumerate devices and confirm that it is currently connected and available before using it.

## Required execution

1. Re-inspect both repositories. Work on `main` and preserve concurrent work. Do not reset, discard, stash, rebase, force-push, or overwrite unexplained state.
2. Use `/Users/mini/code/wm/flightdeck` as the only Flight Deck source. Record its exact committed HEAD. Do not modify Flight Deck merely to package it.
3. In WMAPP, run `FLIGHT_DECK_DIR=/Users/mini/code/wm/flightdeck ./tools/update_flightdeck_bundle.sh`. Confirm `app/assets/flightdeck/version.json` and hashed assets reflect the new build.
4. Run proportionate validation before committing:
   - Flight Deck: `bun run check:public-source`, `bun run test`, `bun run build`, and `bun run verify:dist`.
   - WMAPP: `./tools/test_update_flightdeck_bundle.sh`, Flutter tests and analysis appropriate to `app/`, and `git diff --check`.
5. Commit all compatible nonignored tested WMAPP state on `main` with a Conventional Commit so the packaged source state is durable. Include this handoff file. Do not push.
6. Enumerate Flutter/Xcode devices and select Pete's connected physical iPhone, not a simulator. Keep identifiers in the handoff, but keep secrets, signing certificates, and provisioning details out of logs and reports.
7. Follow `docs/deploy/iphone.md`: run `./build_ios_release.sh`, install `app/build/ios/Release-iphoneos/Runner.app` with `xcrun devicectl`, and launch bundle `com.wingmanbefree.wingmanApp` on the confirmed device.
8. Verify the app process remains present after launch. If tooling allows, confirm the embedded Flight Deck reaches its initial rendered UI. Otherwise give Pete one exact manual visual check. Do not leave `flutter run` or a debugger attached.
9. If blocked by device availability, lock state, trust/pairing, Developer Mode, provisioning, or signing, stop after safe diagnostics and report the exact action Pete must take. Do not clear shared Xcode caches, delete provisioning data, reset the phone, or alter signing identities.

## Reporting

Report to the linked Flight Deck task:

- exact Flight Deck source commit and final WMAPP commit;
- bundle version and meaningful changed-asset summary;
- validation commands and results;
- physical device name and identifier as reported by tooling;
- signed Release artifact path;
- install, launch, and process-presence evidence;
- embedded Flight Deck visual confirmation or the one remaining manual check;
- any blocker and the smallest next action.

Move the task to `review` only after the package, install, and launch validation are complete. Do not push branches, deploy services, or restart managed processes.

This is a supervised Autopilot dispatch. Return the complete evidence in the terminal callback even if direct Flight Deck task-comment tooling is unavailable. Rick will validate it, keep the task/thread aligned, and close the callback.
