# Edit saved bookmark display names

## Goal

Allow a user to change the display name of an existing saved bookmark in Wingman App without changing its URL or recreating it.

Flight Deck task: `78347bff-b6ba-40a4-a9b9-5cef988757cc` — **Allow editing saved bookmark display names**.

Originating Flight Deck message: `7cd9afe0-4e8e-44cc-8f6e-79202d2cad9a` in the WMAPP features thread.

## Current implementation landmarks

- Bookmark persistence/model: `app/lib/src/features/browser/browser_bookmark_store.dart`.
- Bookmark state, generated new-tab HTML, and JS bridge handling: `app/lib/src/features/browser/browser_screen.dart`.
- Existing persistence tests: `app/test/browser_bookmark_store_test.dart`.
- Existing end-to-end widget coverage for add/reload/open/remove and narrow layouts: `app/test/widget_test.dart`.

## Required behavior

- Add a discoverable edit/rename affordance to each saved bookmark on the new-tab bookmark surface.
- Editing changes only the user-facing title. The bookmark URL, identity/deduplication behavior, ordering, and navigation target remain unchanged.
- Persist the changed title through the existing signer-scoped bookmark storage so it survives home-page refresh and app relaunch/reload.
- If inline editing is used, support keyboard save and cancel as appropriate. A blank or whitespace-only value must not silently replace a useful title; either reject it or restore a safe existing/fallback title.
- Escape all values used in generated HTML/attributes and keep bridge payload validation consistent with existing open/remove handling.
- Preserve add/remove, bookmark-state reporting, malformed stored-data recovery, long-title wrapping, narrow layouts, and all existing browser/signer behavior.

## Validation and handoff

- Extend focused store/widget tests to prove rename, persistence/reload, URL preservation, and blank/cancel behavior.
- Run formatting and the relevant Flutter tests; run the repository's normal broader validation/build where practical.
- Work on `main`. Preserve concurrent work. Commit all nonignored tested state so the repository captures the actual validated state.
- Do not push, deploy, or restart any managed process.
- Report the commit hash, files changed, exact validation commands/results, and any UX decision or remaining limitation to Rick. Rick owns the Flight Deck task/thread updates.
