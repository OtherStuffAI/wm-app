# WMAPP browser bar overlay

## Goal

Make the transient browser/address bar and navigation controls overlay the browser content instead of consuming layout height. Showing, hiding, or changing the bar while switching tabs must not resize, translate, or visibly jump the content viewport.

## Source and reporting

- Flight Deck task: `e3006c5d-8b41-4d5c-8412-e9f7d590f476` — **Overlay browser bar without shifting WMAPP content**
- Originating message: `5f13573e-a287-4422-ad80-fee4cebec3eb`
- Workspace/channel/thread: `2e5caefd-dd65-45d2-b747-ee874e8e5fc9` / `d8d00881-ac84-41eb-ab0d-2c2afb77ddf3` / `63259962-c93e-4ede-8732-8f774335e007`
- Report investigation, implementation milestones, validation evidence, and final commit on the Flight Deck task. Rick will mirror meaningful milestones to the originating thread.

## User-reported symptom

When WMAPP displays the browser bar while switching between tabs, the app currently inserts the address bar and controls into the layout above the web content. That pushes the content area down and makes the entire window jump. Pete wants the bar to float over the web content instead.

## Required behaviour

- Render the browser/address bar and controls as a positioned overlay above the existing web-content viewport.
- Showing or hiding the bar must not change the content area's dimensions, vertical origin, browser/WebView geometry, or scroll position.
- The overlay must remain readable and interactive with appropriate background, elevation/border, stacking, and pointer handling.
- Preserve current address display/editing, back/forward/reload, focus, keyboard, tab switching, visibility timing, and dismissal behavior.
- Avoid permanently obscuring content beyond the intended transient overlay. Preserve existing hide/show timing unless changing it is necessary to eliminate the jump.
- Respect current titlebar/safe-area/platform handling and verify both narrow and wide window sizes.

## Acceptance and validation

- Add or update focused tests that demonstrate bar visibility changes do not alter the content viewport offset/size while the overlay controls remain operable.
- Run focused tests, the complete relevant test suite, formatting/static analysis, and build/package validation exposed by the repo.
- Perform a practical manual/visual check while switching tabs at narrow and wide sizes. Record what was checked; do not start an unmanaged preview or restart a managed app.
- Report the root cause, files changed, exact commands/results, manual evidence, and commit hash on the Flight Deck task.

## Repository constraints

- Work in `/Users/mini/code/wingmanbefree/wm-app` on `main`.
- The shared worktree is already dirty, including changes in `app/lib/src/features/browser/browser_screen.dart` and other app files. Inspect and preserve all current work. Concurrent changes are part of the shared state; do not discard, reset, or overwrite them.
- When ready, commit all nonignored tested worktree state unless there is a concrete safety conflict. Note the two untracked APK files explicitly and decide whether they are intentional release artifacts before including them; do not silently delete them.
- Do not deploy, push, start a separate preview, or restart managed processes.
