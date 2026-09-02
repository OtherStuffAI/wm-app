# Bundle Flight Deck performance fix into WM-App for Pete's Mac

## Goal

Package the exact Flight Deck performance fix at commit `4d416b5` (build 1868) into the active WM-App repository, build a macOS debug application, and leave Pete with a locally launchable app for testing the large Pete workspace and composer typing performance.

Flight Deck task: `26f054c5-7265-4f1f-8ad1-9c154d0f24c9` — **Bundle Flight Deck performance fix into WM-App for Mac testing**.

Origin: @[Message](mention:message:0b7c5683-c0a8-4f5f-a7ee-ac57f59ff351) in thread `ea2aacdb-8e2a-47cc-8627-702ea87270a2`, workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`, channel `0617d526-88dc-4dc2-9876-08349ab60eca`.

Source fix: @[Fix Pete workspace tab and typing performance](mention:task:6f50304b-f959-454f-8fe9-9b081668624d).

## Starting evidence

- Active WM-App repo: `/Users/mini/code/wm/wmapp`.
- Active Flight Deck repo: `/Users/mini/code/wm/flightdeck`.
- Flight Deck `main` is at `4d416b5` and clean at dispatch time. The fix was already validated with 3,349 tests plus build/dist verification.
- The existing WM-App bundle reports Flight Deck build 1867. A normal production rebuild increments the generated number, but Flight Deck supports deterministic build inputs; use those supported inputs to reproduce build 1868 from the exact source commit without leaving source metadata changed.
- WM-App `main` is at `fe69eda`, one commit ahead of `origin/main`, with unrelated untracked handoff files dated 2026-09-02. These are concurrent work: preserve them and include all nonignored tested state in the final commit under the repo's state semantics.

## Required work

1. Read the repository instructions and inspect the current worktree before changing anything. Do not reset, discard, rebase, force-push, or overwrite unexplained work.
2. Confirm `/Users/mini/code/wm/flightdeck` still resolves to commit `4d416b5`. Preserve the source worktree and use Flight Deck's supported deterministic build variables to reproduce its build 1868 identity when running the updater. If source `HEAD` has moved, stop and report rather than silently packaging a different commit.
3. From `/Users/mini/code/wm/wmapp`, run:

   ```bash
   FLIGHT_DECK_DIR=/Users/mini/code/wm/flightdeck ./tools/update_flightdeck_bundle.sh
   ```

4. Verify `app/assets/flightdeck/version.json` identifies build 1868 and inspect the asset diff. Confirm the embedded JavaScript contains the performance-fix signatures from `4d416b5`, not only a bumped version file.
5. Run proportionate validation:
   - `git diff --check`
   - relevant bundle/Flutter tests
   - `flutter build macos --debug` from `app/`
   - inspect the generated app at `app/build/macos/Build/Products/Debug/wingman_app.app`
   - confirm the generated app bundle contains Flight Deck build 1868
6. Launch-smoke the new macOS app if safe. Pete explicitly requested a bundle he can test on this machine, so replacing the currently running WM-App process with the new local debug build is in scope. Do not restart Autopilot, Tower, Flight Deck servers, or any other service. Record the exact app path and log path.
7. Work on `main`. Commit all nonignored tested WM-App state, including concurrent nonignored work already present, using a Conventional Commit. Do not push, publish a release, or deploy anything.

## Acceptance criteria

- WM-App's tracked embedded Flight Deck assets are deterministically generated build 1868 from source commit `4d416b5`.
- A successful macOS debug build exists at the documented app path.
- The built `.app` itself contains the expected Flight Deck build/version and performance-fix content.
- A launch smoke test succeeds, or a precise blocker and manual launch command are documented.
- All tests/checks and the final WM-App commit are reported with evidence.
- No unrelated work is discarded and no service is restarted.

## Reporting and lifecycle

- Set your session goal to this exact packaging objective and keep your next action current.
- Post meaningful milestones and the final technical handoff to the Flight Deck task. Use the task as the durable record; Rick will summarize the result in the originating chat thread.
- Re-read the task and latest comments before final handoff in case requirements changed.
- Move the task to `review` only when the bundle, macOS build, and validation are complete.
- Stop your session only after a terminal handoff or a concrete blocker is recorded.
