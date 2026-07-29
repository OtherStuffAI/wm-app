# WM-App Artifact iframe navigation fix

## Goal

Fix WM-App so Artifact WApp's preview iframe stays inside the Artifact control tab. Ordinary WebView subframe navigation must never be interpreted as a popup/new-tab request.

Flight Deck task: `684eb349-7f15-4ab0-96a4-b4f1dfb3990b` — **Keep Artifact iframe navigation inside its WM-App tab**.

Originating chat:

- Workspace: `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`
- Channel: `d8d00881-ac84-41eb-ab0d-2c2afb77ddf3`
- Thread: `2ff6d457-d32f-4c8a-977f-6427cab89917`
- Message: `2524b169-9032-4375-af8a-9644e4cfbd16`

## Confirmed fault

Artifact's control interface owns an ordinary iframe. Its initial `about:blank` document and later `/artifact-frame/...` URL arrive in WM-App as `NavigationRequest` values where `isMainFrame` is false.

`app/lib/src/features/browser/browser_screen.dart` currently maps every non-main-frame request to `_createTab(...)` and returns `NavigationDecision.prevent`. That creates a blank tab, then a raw-artifact tab, while preventing the iframe from rendering in the control UI.

`isMainFrame == false` means subframe navigation; it is not a unique popup signal.

## Required change

- In WM-App's navigation-request handling, allow ordinary subframe requests to navigate in place.
- A non-main-frame request must return `NavigationDecision.navigate` and must not call `_createTab()`.
- Do not modify Artifact WApp.
- Preserve actual new-tab behavior through the existing explicit `WingmanSigner` `openTab` bridge. The injected script already captures `window.open(...)` and links with `_blank` or other non-self targets.
- Native WebView create-window callbacks are optional future hardening and outside this fix unless necessary to preserve an existing tested contract.

## Regression coverage

Extend fake WebView support so widget tests can submit a `NavigationRequest` with `isMainFrame: false` and observe its returned `NavigationDecision`.

Prove all of the following:

1. `about:blank` subframe navigation returns `NavigationDecision.navigate` and creates no tab.
2. A same-origin `/artifact-frame/...` subframe request returns navigate and creates no tab.
3. A cross-origin iframe request returns navigate and creates no tab.
4. Starting with one Artifact control tab, the iframe requests leave exactly one Artifact tab.
5. An explicit `openTab` bridge message still creates and activates exactly one new tab.
6. The injected tab-capture script remains covered for `window.open` and target `_blank`/non-self links.

Prefer behavioral tests over assertions against implementation text. Reuse existing widget-test patterns and keep the fake narrowly useful.

## Working and Git rules

- Work in `/Users/mini/code/wingmanbefree/wm-app` on `main` unless current repo evidence requires otherwise.
- Inspect the complete worktree before editing. Multiple agents may be working concurrently.
- Preserve and understand existing nonignored changes; do not reset, discard, overwrite, or hide them.
- When ready, commit all nonignored tested state in the shared worktree unless a clear safety conflict requires escalation.
- Do not deploy, restart managed apps, or start an unrelated long-running process.

## Validation and reporting

- Run the narrow Flutter/widget tests proving the navigation behavior.
- Run the repo's appropriate broader test/analyze command in proportion to the change.
- Record exact commands and results.
- Add task comments at investigation, implementation, and validation/commit milestones using the typed Flight Deck PG task comment route if available in the worker session.
- On completion, leave a self-contained task handoff with changed files, behavioral result, tests, commit hash, and any manual device check still required. Move the task to `review` only when ready for Pete.
- The supervising Rick session will mirror meaningful status into the originating chat thread and review the callback before acceptance.

## Acceptance result

Opening Artifact from Flight Deck produces the pinned Flight Deck tab plus one Artifact WApp tab containing both controls and the rendered preview. It produces no blank tab and no separate raw-artifact tab.
