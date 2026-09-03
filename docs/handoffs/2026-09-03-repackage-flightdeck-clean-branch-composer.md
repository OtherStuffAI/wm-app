# Repackage corrected Flight Deck branch composer in WMapp

## Objective

Rebuild the embedded Flight Deck bundle in WMapp from exact Flight Deck commit `504dde20d9e95bd6a614ebadf3cb4bf0ab767957` (`504dde2`), commit the resulting WMapp state on `main`, and push `origin/main` to GitHub so Pete can update another machine.

The existing WMapp package at `2660784` reports build 1870 but was produced from older Flight Deck commit `f7e17e4`. It therefore lacks the follow-up that removes the branch composer explanation and visible automatic Rick mention while retaining internal Agent Direct routing.

## Source and target

- Source repo: `/Users/mini/code/wm/flightdeck`
- Required source commit: `504dde20d9e95bd6a614ebadf3cb4bf0ab767957`
- Expected source version metadata before any rebuild:
  - `buildNumber`: `1870`
  - `buildId`: `20260903-0542-2-1870`
  - release label: `Cleaner branched chat composer`
- Target repo: `/Users/mini/code/wm/wmapp`
- GitHub remote: `origin` (`OtherStuffAI/wm-app`)
- Originating Flight Deck task: `21890e45-a4f3-4448-9fcb-01ebc1ebe9e8`
- Originating thread: `7f1fe637-5b39-4e9b-a213-927f2a5e37b3`
- Originating message: `d3e33474-b76e-448d-a636-b12747375289`

## Required work

1. Inspect the nearest repository instructions and current WMapp/Flight Deck Git state before changing anything.
2. Work on WMapp `main`. Preserve concurrent work and never reset, discard, or overwrite changes you do not understand.
3. Package the exact required Flight Deck source commit into `app/assets/flightdeck/` using the repository updater workflow.
   - Avoid mutating or committing the active Flight Deck checkout.
   - The active Flight Deck `dist/` was already built from the required commit. If rebuilding is needed, use a temporary detached worktree at the exact commit so build-number mutation cannot contaminate the active checkout.
4. Verify the packaged directory is byte-for-byte/file-for-file equivalent to the selected source `dist/`, including `version.json` and hashed asset removal/addition.
5. Run proportional WMapp validation:
   - `./tools/test_update_flightdeck_bundle.sh`
   - `flutter test` from `app/`
   - `flutter analyze` from `app/`
   - `flutter build bundle` from `app/`
   - `git diff --check`
6. Inspect the full WMapp worktree and commit all compatible nonignored state, including this handoff, with a Conventional Commit message. Do not hide essential state in uncommitted files.
7. Push WMapp `main` to GitHub `origin/main`.
8. Fetch and verify local/remote parity, and verify the public remote ref SHA with `git ls-remote`.

## Constraints

- Do not push or otherwise change the Flight Deck repository.
- Do not install or launch WMapp.
- Do not restart Tower, Autopilot, Flight Deck, or any managed service.
- Do not push Forgejo unless repository policy proves it is required; Pete explicitly requested GitHub.
- Do not update Flight Deck chat or task records directly. Return a self-contained callback with commit SHA, bundle metadata, validation evidence, remote verification, and any remaining caveat; the supervising Rick session will update Flight Deck.
- Set the worker session goal and next action metadata if the runtime permits.

## Acceptance criteria

- WMapp’s embedded Flight Deck is sourced from exact commit `504dde2`, not the older `f7e17e4` package.
- The branch composer has neither the explanatory “First message starts…” line nor a visible prefilled Rick mention.
- Bundle equivalence is demonstrated, not inferred from the reused build number.
- Required validations pass.
- WMapp is committed on `main`, the worktree is clean, and GitHub `origin/main` resolves to the new commit.
