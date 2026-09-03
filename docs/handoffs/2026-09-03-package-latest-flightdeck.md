# Package latest Flight Deck into WMapp

## Objective

Build the latest committed Flight Deck checkout and refresh WMapp's embedded
Flight Deck assets, then commit and push the tested WMapp state to GitHub so
Pete can pull, rebuild, and run it on his home machine.

Origin: @[Message](mention:message:3c5c8fb4-6873-4bd3-b594-4b3234cf7718)
in @[features](mention:channel:d8d00881-ac84-41eb-ab0d-2c2afb77ddf3).

Tracking task: @[Package latest Flight Deck build into WMapp and push GitHub](mention:task:e7f0eecd-ccbe-44d4-a19f-dc9940db69f0)
in workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`.

## Repositories and current evidence

- Source: `/Users/mini/code/wm/flightdeck`, branch `main`, clean at manager
  inspection, HEAD `f7e17e4` (`feat(chat): branch Tower threads from any
  message`). It is two commits ahead of `origin/main`: `4d416b5` and `f7e17e4`.
- Target: `/Users/mini/code/wm/wmapp`, branch `main`, clean before this handoff
  document was added, HEAD `68d1d40`.
- WMapp's `tools/update_flightdeck_bundle.sh` defaults to the active sibling
  `../flightdeck` checkout and replaces `app/assets/flightdeck/` with its
  generated `dist/`.

Re-read both worktrees and their nearest instructions before acting. Treat the
live worktrees as authoritative if concurrent work has appeared.

## Required work

1. Work from `/Users/mini/code/wm/wmapp` on `main`. Preserve and understand all
   concurrent nonignored state. Do not reset, stash, discard, rebase,
   force-push, or overwrite unexplained changes.
2. Package the exact committed Flight Deck HEAD seen at execution time. Avoid
   leaving build-generated metadata changes in the active Flight Deck checkout;
   preferably build a temporary detached worktree at the selected commit and
   point `FLIGHT_DECK_DIR` at it. Do not commit or push the Flight Deck repo as
   part of this task.
3. Run `tools/update_flightdeck_bundle.sh` (using the safe source checkout), and
   verify `app/assets/flightdeck/` exactly matches the generated `dist/`.
4. Record the packaged `version.json`, source commit, and a meaningful summary
   of changed generated assets.
5. Run proportionate validation, including at minimum:
   - `./tools/test_update_flightdeck_bundle.sh`
   - the Flight Deck production build performed by the updater
   - exact comparison of generated `dist/` and `app/assets/flightdeck/`
   - `cd app && flutter test`
   - `cd app && flutter analyze`
   - `cd app && flutter build bundle`
   - `git diff --check`
6. Commit all compatible nonignored tested WMapp state on `main`, including this
   handoff document, with a Conventional Commit.
7. Push WMapp `main` to the GitHub `origin`. Do not push Forgejo unless needed
   for an already-documented repository invariant; report any remote divergence
   rather than rewriting history.

## Reporting and lifecycle

- Add useful progress and final evidence to the tracking task if broker-aware
  Flight Deck task tools are available. Rick owns the originating chat reply.
- The final callback must include: selected Flight Deck source commit and build
  number/build ID, WMapp commit, GitHub push result, changed bundle summary,
  exact validation results, and any remaining manual home-machine step.
- Do not deploy, install to a device, launch WMapp, or restart any managed
  service.
- Set the worker session goal to this completed outcome, keep next action at
  `reflect` while work/reporting remains, and set it to `stop` only after the
  commit, push, evidence, and task handoff are complete.

## Execution evidence

- Selected Flight Deck source: `f7e17e44d3f848a181201a4503b59d2037faa934`
  (`feat(chat): branch Tower threads from any message`). The production build
  ran from a detached temporary worktree; the active Flight Deck checkout was
  not modified.
- Packaged metadata: build number `1870`, build ID
  `20260903-0210-2-1870`, built at `2026-09-03T02:10:01.680Z`.
- Bundle change: advanced the embedded Flight Deck from build 1868 to 1870;
  added the branch-from-message controls and inherited read-only thread
  context; replaced the generated main entry, TipTap adapter, and Tower
  materialization-worker hashes; removed both superseded main-entry assets;
  retained the unchanged stylesheet and sync worker.
- Exact bundle comparison: `diff -qr` passed, and checksum-based
  `rsync -rcn --delete --itemize-changes` reported no differences between the
  temporary source `dist/` and `app/assets/flightdeck/`.
- Validation passed: `./tools/test_update_flightdeck_bundle.sh`; the updater's
  Vite production build (456 modules, 17 published files); `flutter test`
  (104 tests); `flutter analyze` (no issues); `flutter build bundle`; and
  `git diff --check`.
