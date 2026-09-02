# WM-App live tab titles

## Objective

Implement @[Show live page titles in WM-App tabs](mention:task:8d192eae-e801-4506-9e94-512f3f21beeb) from Pete's Agent Direct request @[Message](mention:message:1993f270-e0dc-41dc-9bef-074e39ceb1df).

WM-App tabs must show the embedded page's useful title as Firefox/Chrome would. In particular:

- distinct Flight Deck tabs show each page's `view + workspace` title;
- distinct Wingman tabs show each session name;
- users can identify same-product tabs at a glance.

## Confirmed implementation clue

`app/lib/src/features/browser/browser_screen.dart` already calls `WebViewController.getTitle()` in `_onPageFinished`, but local Flight Deck URLs are explicitly assigned `_flightDeckTitle` instead of the returned title. Inspect the full lifecycle before editing: this explains the generic label at page finish but may not be the only issue, because Flight Deck and Wingman are SPAs whose document titles can change after initial load or without navigation.

## Required behavior

1. Prefer a non-empty, trimmed current page title for all real web content, including bundled/local Flight Deck.
2. Retain deterministic fallbacks while loading, when the title is blank, when retrieval fails, and for internal new-tab content.
3. Reflect later document-title changes that happen during SPA navigation or session/view switches, using a bounded and maintainable mechanism supported by the current WebView stack.
4. Do not let restored/persisted generic labels prevent later live title refreshes.
5. Preserve bookmarks and unrelated navigation/signing behavior.
6. Add focused tests that fail on the current generic-local-Flight-Deck behavior and cover blank/fallback and post-load title refresh as far as the current test harness permits.

## Worktree and authority

- Repo/workdir: `/Users/mini/code/wm/wmapp`.
- Default to `main`.
- Preserve concurrent work. Do not reset, discard, rebase, force-push, or overwrite changes you did not create.
- Per repo semantics, commit all compatible nonignored tested state present when ready; understand any concurrent changes first.
- Use a Conventional Commit.
- Do not push, deploy, install to a device, start a preview server, or restart a managed process.
- Stay in this repo unless live evidence proves Flight Deck or Wingman does not publish the expected document title. If so, report the evidence rather than silently broadening scope.

## Validation

Run, at minimum:

- formatter check for changed Dart files;
- focused Flutter tests for browser title behavior;
- broader relevant Flutter test/analyze command if proportionate and available;
- `git diff --check` before commit;
- post-commit clean/status and commit inspection.

## Reporting and closeout

Comment on the task with:

- root cause and chosen title-update lifecycle;
- changed files and commit hash;
- exact commands and results;
- any limitation that still needs a packaged/live smoke test.

Move the task to `review` only after the committed change and validation are ready for Pete. Do not post directly to the originating chat thread; Rick will review the callback, diff, tests, and task state, then report there.
