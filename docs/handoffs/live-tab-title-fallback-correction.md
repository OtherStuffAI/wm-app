# Correct WM-App local Flight Deck title fallback

Perform a focused manager-review correction on commit `88b694c` for @[Show live page titles in WM-App tabs](mention:task:8d192eae-e801-4506-9e94-512f3f21beeb).

The live-title and SPA observer implementation is accepted in principle. One fallback regression is not accepted: local/bundled Flight Deck currently displays `127.0.0.1` when `getTitle()` is blank, throws, or the observer reports a blank title. The pre-change human-friendly product fallback was `Flight Deck`, and that must remain the fallback for `_isLocalFlightDeckUrl(url)`.

Required change:

- Preserve the current behavior where any non-empty trimmed live page title wins for local Flight Deck and all other pages.
- In the shared resolved-title logic, when the title is blank and the URL is local/bundled Flight Deck, return `_flightDeckTitle`; otherwise use the existing URL fallback.
- Ensure a blank `WingmanTitle` SPA message on a local Flight Deck tab returns to `Flight Deck`, not `127.0.0.1`.
- Update the focused tests so initial blank, blank observer message, retrieval failure, and the older browser-state seeding assertion all expect `Flight Deck`; retain the real-title and SPA-title assertions.
- Re-read the latest task comments before editing; manager correction comment `07283bf3-0105-4fbc-b75b-fbc7c74fed44` records this decision.

Run focused tests, full `flutter test`, `flutter analyze`, Dart formatter check, and `git diff --check`. Commit all compatible nonignored tested state on `main` with a Conventional Commit. Do not push, deploy, install, preview, or restart anything. Report the new commit and exact validation evidence in the callback. Rick will update the Flight Deck task and thread.
