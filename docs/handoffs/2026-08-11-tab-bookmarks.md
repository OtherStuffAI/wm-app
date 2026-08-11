# WM App tab bookmarks

## Goal

Implement persistent page bookmarks in the Wingman App Flutter shell. Pete wants to swipe open a tab's existing left-side menu, choose **Add bookmark**, and then see that page in the bookmark list shown when opening a new tab.

Flight Deck task: `4a87589b-cc5f-44ce-993b-38723d9880a8` — **Add tab bookmarks to Wingman App**.

Originating chat: workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`, channel `d8d00881-ac84-41eb-ab0d-2c2afb77ddf3`, thread `aedc228d-a8da-49fb-9929-a8f4c7137403`, message `5a301da5-8ddd-4b7e-9fdf-375821ce589e`.

## Required product behavior

- Add **Add bookmark** to the current tab's existing left swipe/context menu.
- Save the current page URL/route and useful title. Retain an icon/favicon only if the existing architecture already supplies one safely.
- Persist bookmarks across app relaunches using the established local settings/storage pattern.
- Display saved bookmarks on the existing new-tab screen as clear, tappable items.
- Opening a bookmark should navigate the new/current tab through the same normal navigation path used elsewhere, preserving expected history/auth/webview behavior.
- Prevent duplicate entries for the same canonical page URL. Make already-bookmarked state clear.
- Support removal/unbookmarking. Prefer the same tab menu plus a discoverable affordance on new-tab bookmark entries where consistent with current UI patterns.
- Handle no bookmarks, malformed/stale stored data, and long titles/URLs gracefully.
- Preserve tab switching, swipe gestures, navigation, focus mode, browser overlay behavior, authentication, and embedded webview state.
- Use appropriate Flutter semantics/tooltips and keyboard activation.

## Investigation guidance

Start in `app/lib/src/features/browser/browser_screen.dart` and its tests. Identify the existing left swipe menu, new-tab representation, browser tab/page model, persistence conventions, and navigation path before choosing data structures. Reuse the app's established store/persistence approach instead of introducing a parallel framework.

Canonicalization should be conservative: prevent obvious exact duplicates without changing distinct routes or meaningful query parameters. Document the chosen rule in code/tests.

## Validation

- Add focused tests for add, persistence/reload, duplicate prevention, new-tab rendering/opening, removal, corrupt stored data, and long-label layout where practical.
- Run formatting and static analysis.
- Run relevant focused tests, then the full repo test suite appropriate to the touched Flutter package.
- Run the normal build/check command available in this repo if environment provisioning permits it.
- Manually inspect or exercise the swipe menu, new-tab list, opening/removal flow, narrow sizing, and supported themes; report anything not directly testable in the worker environment.

Report exact commands and results, changed files, commit hash, and whether Pete needs an app rebuild/install or managed-runtime restart. Do not deploy, install to Pete's devices, publish, or restart a managed runtime without explicit approval.

## Git/worktree rules

- Work directly on `main` unless current repository evidence makes that unsafe.
- This shared worktree is currently clean and `main` is five commits ahead of `origin/main`; preserve that existing state.
- Re-check the full worktree before committing because concurrent agents may add changes.
- Commit all nonignored tested state in the shared worktree unless Pete explicitly excluded it or there is a clear safety reason to pause.
- Do not reset, discard, overwrite, rebase, force-push, or deploy.

## Reporting

Post investigation and meaningful progress to the Flight Deck task, including validation and final commit evidence. Rick will relay concise milestones into the originating chat thread and review the worker's terminal callback.
