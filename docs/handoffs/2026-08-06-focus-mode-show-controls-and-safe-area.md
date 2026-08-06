# Focus Mode: move restore into left navigation and remove bottom gap

## Correction and source

This is a **WM-App Flutter shell** change, not a Flight Deck UI change. Flight Deck is merely the page shown inside WM-App's WebView.

Pete's request: @[Message](mention:message:38ff0378-9625-4c5a-a9cd-fd18eb310dbd). Tracking task: @[Improve WM-App fullscreen controls and remove bottom navigation gap](mention:task:623233a8-3849-4284-8b67-35fb3ac79a20).

Read `docs/2026-07-28-focus-mode-handoff.md` for the original Focus Mode implementation intent. This request revises that design based on real iPhone use.

## Required change

1. Remove WM-App's floating square/corners restore button from Focus Mode.
2. When Focus Mode is active, keep the left-edge swipe gesture available so Pete can reveal WM-App's left navigation/drawer.
3. Add a clearly labelled **Show controls** option to that left navigation. Activating it exits Focus Mode and restores the existing WM-App shell controls, preserving the active tab, WebView, URL, page state, and tab collection.
4. Remove the unintended blank strip beneath WM-App's bottom Deck / Chat / Tasks bar seen on iPhone. Diagnose the Flutter safe-area/scaffold/view-padding composition and make the navigation meet the usable bottom edge. Preserve any genuinely required home-indicator protection inside the bar; do not leave an empty reserved band below it.

## Evidence

- Screenshot storage IDs: `5a224164-e0f8-42b7-adad-eaf0d746ee8e5fc9` and `4133c0f0-703d-46b6-aa0f-09cb8ddcda21`.
- A local copy of the second screenshot is `/Users/mini/wingmen/wingman21/data/attachments/4133c0f0-703d-46b6-aa0f-09cb8ddcda21.png`.
- It shows WM-App running Flight Deck, the floating restore control over the lower-left content/navigation, and a pale empty band below the bottom navigation.
- The first object currently returns a Tower storage HTTP 500 to Rick's session. Do not block on it.

## Likely implementation surface

- `app/lib/src/features/shell/shell_home.dart`
- `app/lib/src/features/browser/browser_screen.dart`
- Existing Focus Mode widget tests and iOS safe-area/layout code

Inspect current code before deciding ownership. Reuse the existing Focus Mode state and exit callback. Keep existing WebView/controller identity alive.

## Acceptance and validation

- Focus Mode has no floating restore button.
- A left-edge swipe still reveals the appropriate WM-App navigation while focused.
- That navigation exposes **Show controls**, with semantics, adequate hit target, and keyboard/tap behavior.
- **Show controls** exits Focus Mode without losing active tab/WebView/page state.
- iPhone bottom navigation no longer leaves the blank band, and content is not obscured by the home indicator.
- Normal, focused, narrow/mobile, and non-iPhone layouts are unchanged except where required.
- Add focused Flutter widget tests for gesture/drawer access, action visibility, focus exit/state preservation, and safe-area structure where practical.
- Run formatting, focused tests, `flutter test`, `flutter analyze`, and the relevant iOS/build validation available without launching or restarting an app. Record exact results.

Work on `main`, preserve concurrent changes, and commit all nonignored tested state. Do not deploy, publish, launch, or restart WM-App.
