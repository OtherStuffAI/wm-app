# Bundle the newest Flight Deck into WM-App and install it on Pete's iPhone

## Goal

Build the current Flight Deck from `/Users/mini/code/wm/flightdeck`, embed that build in the Flutter Wingman App, produce a signed iOS Release, install it on the connected physical iPhone, launch it, and validate that it remains running.

Flight Deck tracking task: `bbba2b78-1f0b-4d26-bddf-6bf3ea0e4b65` — **Bundle newest Flight Deck into Wingman iOS app and install on connected iPhone**.

Origin: @[Message](mention:message:be856331-0940-4002-b35e-3c269f866984) in thread `da6afa67-ab39-4e4b-9736-2a677a88de27`, workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`, channel `d8d00881-ac84-41eb-ab0d-2c2afb77ddf3`.

At dispatch time:

- Flight Deck `main` is clean and at `b9538df0f5bfa68564a14fc4d9fd786228e696b1`, two commits ahead of its remote.
- WM-App `main` is clean and at `ccd2c8df632e2703e7a98f10b1de5ea61c7a1cfe`.

## Execution

1. Inspect both repos again and preserve concurrent work. Do not reset, discard, rebase, force-push, or overwrite unexplained changes.
2. Use `/Users/mini/code/wm/flightdeck` as the Flight Deck source. Build its current `dist` and record the exact source commit.
3. In WM-App, run `FLIGHT_DECK_DIR=/Users/mini/code/wm/flightdeck ./tools/update_flightdeck_bundle.sh`. Confirm the embedded bundle under `app/assets/flightdeck` was refreshed from that source.
4. Run proportionate validation, including `git diff --check` and any focused bundle/app checks available without delaying the physical-device goal.
5. Follow `docs/deploy/iphone.md`: identify the connected physical iPhone, run `./build_ios_release.sh`, install `app/build/ios/Release-iphoneos/Runner.app` with `xcrun devicectl`, and launch `com.wingmanbefree.wingmanApp`.
6. Verify the app process remains present. If device tooling permits, verify the embedded Flight Deck reaches its initial rendered screen; otherwise state the exact manual visual check Pete must perform. Do not leave `flutter run` or a debugger attached.
7. Work on `main`. Commit all nonignored tested WM-App state so the repository captures the build input. Do not push or deploy services.

## Reporting

Post meaningful milestones and the final handoff to the Flight Deck task. Include:

- Flight Deck source commit and WM-App commit;
- bundle refresh evidence and changed asset summary;
- validation commands/results;
- connected device name/identifier as reported by tooling;
- signed Release artifact path;
- install result;
- launch and process-presence result;
- whether the Flight Deck UI was visually confirmed, or the exact remaining manual check;
- any blocker and the smallest next step.

Move the task to `review` only after installation and launch validation succeed. Rick will mirror concise milestones and the final result into the originating chat thread.
