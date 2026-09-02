Implement @[Support native file pickers in WMAPP WebViews](mention:task:b1dffc5b-a138-40ec-a5eb-e0d4291ff028) in `/Users/mini/code/wm/wmapp` on `main`.

Read `docs/handoffs/2026-09-02-webview-file-picker-support.md` completely before changing code. It is the self-contained source of truth for the symptom, current evidence, required macOS and Android behavior, constraints, acceptance criteria, and validation.

Core goal: standard HTML `<input type="file">` must open the native/system chooser in WMAPP. The confirmed macOS Forgejo avatar case currently does nothing because the WebKit UI delegate path does not implement the native open-panel callback. Add the narrowest maintainable repository-owned integration; do not patch the global Pub cache or replace the browser stack without first proving and reporting that the narrow path is infeasible. Add Android's supported file-selector/system-picker path without broad storage permissions. Keep file selection separate from the existing `window.open`/`_blank` tab capture.

Before implementation, inspect the live worktree and recent history. This is a shared worktree and `main` is already ahead of `origin/main`. Preserve all concurrent work. Do not reset, discard, stash, rebase, force-push, or overwrite changes you did not create. When ready, commit all compatible nonignored tested state on `main` using a Conventional Commit so the repository captures the tested state.

Update the Flight Deck task with concise milestones: diagnosis/implementation path, implementation complete, and validation/handoff. Re-read task comments before final handoff. Move the task to `review` only when the work is ready for Pete to test. Do not post separately to the originating Agent Direct chat; Rick owns that thread and will review your callback/task evidence before reporting.

Run formatter, focused/full relevant Flutter tests, `flutter analyze`, and available macOS/Android build validation. Manually validate the Forgejo avatar choose/select/submit flow on macOS if feasible without restarting any managed service. If native UI or device validation is unavailable, state exactly what remains unproven. Do not push, deploy, restart managed processes, or alter signing identities/provisioning.

At completion, report the diagnosis, architecture choice, files changed, tests/builds/manual checks with exact results, commit hash, task state, and remaining risks or validation gaps. Set your session next action to `stop` only after all required evidence and task reporting are complete.
