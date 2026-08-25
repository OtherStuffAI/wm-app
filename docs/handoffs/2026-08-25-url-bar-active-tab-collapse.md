# WMAPP URL bar: active-tab collapse and complete URL

## Goal

Improve the Wingman App tab/navigation interaction so the temporary URL bar can be dismissed deliberately and reports the actual page URL.

## Source

- Flight Deck workspace: `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`
- Features channel: `d8d00881-ac84-41eb-ab0d-2c2afb77ddf3`
- Thread: `8c25d725-8c8b-43b5-9221-b0958e580e82`
- Pete's message: `13900fd3-7831-48f8-8715-edb8055469ab`

Pete reports that switching to a page displays the URL bar for about five seconds before it collapses. He wants a second click on the already-selected tab to collapse it immediately. He also wants the URL bar to display the complete current URL, for example `rick.runwingman.com/live/<sessionid>`, rather than truncating it to `rick.runwingman.com/`.

## Required behavior

1. Preserve the existing behavior where switching to a different tab/page reveals the URL bar temporarily and it auto-collapses after the existing delay.
2. While that URL bar is visible, clicking/tapping the already-selected tab collapses it immediately.
3. Repeated-active-tab handling must not reload the page, recreate the webview, reset navigation state, or trigger a duplicate navigation.
4. The URL text must represent the complete current page URL, including path, query string, and fragment when present. It may omit the scheme if that is the established visual style, but it must not discard the path or other meaningful URL components.
5. The URL display must update when the active embedded page navigates, including routes such as `/live/<sessionid>`.
6. Keep the existing timer safe: manual collapse must cancel or neutralize any stale delayed callback so it cannot unexpectedly affect later tab selections.
7. Preserve existing tab switching, close/reopen behavior, webview/browser history, navigation controls, focus mode, authentication, and desktop/mobile input behavior.

## Investigation notes

- Identify whether current truncation happens in view formatting, URL parsing, state persistence, or an embedded webview navigation callback. Fix the narrowest correct layer.
- Confirm the active-tab click/tap event is observable even when selection does not change; selection-change-only logic will not satisfy this interaction.
- Check any tests that use host-only display strings or expect a repeated tab selection to be a no-op.

## Acceptance checks

- Switch from tab A to tab B: URL bar appears and still auto-collapses after the normal delay.
- Before timeout, click/tap tab B again: URL bar collapses immediately.
- The second click does not reload tab B or change its current page/history/state.
- Navigate an active tab to `https://rick.runwingman.com/live/example-session`: the URL bar displays `rick.runwingman.com/live/example-session` or the full scheme-bearing equivalent.
- Verify query strings and fragments are not stripped.
- Manually collapse, then switch tabs promptly: no stale timer collapses the newly displayed URL bar early.
- Add or update focused automated tests for repeated-active-tab collapse, timer cleanup, full URL rendering, and navigation-driven URL refresh where the repo's test architecture supports them.
- Run the repo's relevant format/analyze/lint/test/build commands and record exact results.

## Worktree and delivery rules

- Work in `/Users/mini/code/wingmanbefree/wm-app` on `main` unless live repo instructions require otherwise.
- Inspect and preserve concurrent work. Do not revert, reset, overwrite, or exclude nonignored state you do not understand.
- When ready, commit all nonignored tested worktree state so the repository reflects the validated state.
- Do not deploy, publish, or restart the managed WMAPP runtime without Pete's explicit approval in the originating conversation.
- Report changed files, validation commands/results, commit hash, any manual checks still needed, and whether a rebuild/restart is required for Pete to see the change.
