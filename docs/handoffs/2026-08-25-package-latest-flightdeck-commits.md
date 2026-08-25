# Package latest committed Flight Deck in WM App

## Goal

Build the latest committed active Flight Deck checkout and replace WM App's embedded Flight Deck bundle with that build. Validate and commit the resulting WM App state on `main`.

Flight Deck task: `d344cd69-ac2c-4d85-9dff-99aa651666ce` — **Package latest Flight Deck commits in WM App**.

Origin: @[Message](mention:message:63ba3802-dce7-4be3-b711-fe2753b97eb5) in thread `9c3fd041-a5a2-473a-bd4c-b92c6836bb6d`, workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`, channel `d8d00881-ac84-41eb-ab0d-2c2afb77ddf3`.

## Confirmed dispatch state

- Canonical Flight Deck source: `/Users/mini/code/wingmanbefree/wm-fd-2`.
- Flight Deck `main` was clean at `7fb314d` (`Fix document editor save reconciliation flicker`).
- WM App `main` was clean at `0cd0dd9` before this handoff was added.
- `tools/update_flightdeck_bundle.sh` defaults to `../wm-fd-2`, confirming this source boundary.
- Do not use `/Users/mini/code/wm/flightdeck`. It is a separate checkout with unrelated uncommitted work and is outside this task.

## Execution

1. Re-read the Flight Deck task and its latest comments before acting.
2. Inspect both worktrees again. Preserve concurrent work; do not reset, discard, rebase, force-push, stash, or overwrite unexplained changes.
3. Confirm the committed source to package. If `wm-fd-2` advanced beyond `7fb314d` through new committed work before execution, package the latest clean committed `main` HEAD and report the exact commit. Never package uncommitted source changes without explicit approval.
4. From `/Users/mini/code/wingmanbefree/wm-app`, run `./tools/update_flightdeck_bundle.sh`. This builds the source and replaces `app/assets/flightdeck` from its generated `dist`.
5. Confirm the embedded bundle changed as expected. Record the generated `version.json` build ID/build number and summarize meaningful changed assets.
6. Run proportionate validation, including the Flight Deck build performed by the update script, `git diff --check`, and any focused WM App embedded-bundle or Flutter asset validation exposed by the repo that can run safely.
7. Work on `main`. Commit all nonignored tested WM App state so the repository captures the packaged state. Follow the repo semantics: include safe concurrent nonignored state that is understood; never discard or hide it.
8. Do not push, deploy, build/install a device app, or restart any service.

## Handoff evidence

Comment on the task with:

- exact Flight Deck source commit;
- resulting WM App commit;
- generated Flight Deck build ID/build number;
- changed bundle summary;
- validation commands/results;
- any blocker and the smallest safe next step.

Move the task to `review` only after the bundle is validated and the WM App state is committed. Rick will mirror the concise outcome to the originating chat thread.
