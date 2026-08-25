# Repackage Flight Deck NIP-98 reconnect signing fix

## Goal

Rebuild and embed Flight Deck commit `55fb0c0` in WM App so SSE reconnect requests sign the complete resolved URL and Tower accepts the NIP-98 proof. Validate and commit the resulting WM App state on `main`.

Flight Deck task: `7780da5b-1940-4001-8036-4326dc51a43b` — **Repackage Flight Deck NIP-98 reconnect signing fix in WM App**.

Origin: @[Message](mention:message:97987140-8b6b-44c6-916c-c74496cfebef) in thread `9c3fd041-a5a2-473a-bd4c-b92c6836bb6d`, workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`, channel `d8d00881-ac84-41eb-ab0d-2c2afb77ddf3`.

Prior package task: @[Package latest Flight Deck commits in WM App](mention:task:d344cd69-ac2c-4d85-9dff-99aa651666ce).

## Confirmed dispatch state

- Intended Flight Deck source: `/Users/mini/code/wm/flightdeck`.
- Source `main` committed HEAD: `55fb0c0` (`Sign complete SSE reconnect URLs`), locally ahead of origin.
- The source worktree has an untracked `docs/handoffs/` directory. Inspect and preserve it. Do not include untracked docs as browser build input.
- WM App `main`: clean at `d38bf3919b1d0c115432f0386a6770798cff3e46` before this handoff was added.
- This source override is deliberate: `55fb0c0` contains the NIP-98 change Pete identified. Do not silently fall back to `../wm-fd-2`.

## Execution

1. Re-read the Flight Deck task and latest comments.
2. Re-inspect both worktrees. Preserve concurrent tracked and untracked work; do not reset, discard, rebase, force-push, stash, or overwrite unexplained changes.
3. Inspect `55fb0c0` and confirm it signs the fully resolved SSE reconnect URL, including reconnect query parameters, before the signed fetch reaches Tower.
4. Package committed source HEAD with:

   ```bash
   FLIGHT_DECK_DIR=/Users/mini/code/wm/flightdeck ./tools/update_flightdeck_bundle.sh
   ```

5. Confirm `app/assets/flightdeck` exactly matches the generated source `dist`. Record `version.json` build ID/build number and summarize changed hashed assets.
6. Run proportionate validation:
   - source test(s) focused on SSE/NIP-98 reconnect signing if present;
   - the production source build performed by the updater;
   - generated asset reference and checksum/dry-run comparison;
   - Flutter formatting/analysis/tests appropriate to the complete nonignored state;
   - `flutter build bundle` or equivalent proof that Flutter accepts the embedded assets;
   - `git diff --check` and staged/committed checks.
7. If building increments a tracked source-side build counter, restore only that exact build-generated counter change after confirming no concurrent edit overlaps it. Leave all pre-existing source state intact.
8. Work on WM App `main` and commit all nonignored tested state per repository semantics. Do not push, deploy, install on a device, or restart any service.

## Handoff evidence

Comment on the task with:

- exact Flight Deck source commit and evidence of the signing change;
- resulting WM App commit;
- embedded build ID/build number;
- changed bundle summary;
- validation commands/results;
- both repositories' final worktree state;
- any blocker and the smallest safe next step.

Move the task to `review` only after the bundle is committed and validation passes. Rick will mirror the concise outcome to the originating chat thread.
