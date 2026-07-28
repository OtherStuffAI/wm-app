# Wingman App Focus Mode implementation handoff

## Goal

Implement a reversible Focus Mode in the Flutter Wingman App shell. When Pete is viewing a browser tab such as Flight Deck, one control on the grey browser tab bar should let that tab fill the app window. Normal app chrome disappears; a small floating control at bottom-left restores it.

This is a `wm-app` Flutter implementation task. Do not use or modify the `wm-fd-2` Flight Deck UI project; Flight Deck is only the embedded example page and the reporting surface. Begin directly with repository inspection and implementation. If any required skill/tool lookup stalls, skip the optional lookup and report the exact blocker.

Flight Deck tracking task: `c7c14566-251e-466a-a35d-5b844bab77a0` (Add Focus Mode to Wingman App).

Originating message: `054bfc27-f425-4612-8d37-e7629f65a06a` in workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`, channel `d8d00881-ac84-41eb-ab0d-2c2afb77ddf3`, thread `bd073934-e4be-4fd3-84b7-98fb714c0457`.

Pete attached a placement screenshot as Flight Deck storage object `8b031edd-40fd-40af-b9cc-f03e8932b10c`.

## Required interaction

- Put a recognizable square/corners-style Focus Mode button on the grey browser tab bar.
- On activation, keep the active browser tab/WebView alive and selected while expanding its content to the full available app window.
- Hide the normal Wingman App chrome: grey tab bar, hamburger/menu, and avatar/account control.
- While focused, overlay a small restore button at bottom-left. It should use the same recognizable icon, remain above browser content, and not reserve a full bar of space.
- Activating the floating button exits Focus Mode and restores the exact prior shell with active tab and browser state intact.
- Focus Mode should be transient window/session UI state. It must not strand the user after a fresh app launch.
- Both enter and restore controls need tooltips/semantic labels, keyboard focus, and adequate contrast/hit area.
- Check safe-area/window-inset behavior so the restore control is not obscured on supported platforms.

## Likely implementation surface

The selected shell surface is held by `app/lib/src/features/shell/shell_home.dart`. The browser tab strip, hamburger, avatar, and WebViews are primarily in `app/lib/src/features/browser/browser_screen.dart`. Inspect the live widget structure before deciding whether Focus Mode state belongs in `ShellHome`, `BrowserScreen`, or is coordinated between them.

Prefer hiding/recomposing chrome around the existing tab/WebView widgets rather than replacing the browser screen or rebuilding controllers. Preserving `IndexedStack`/tab identity and WebView controller state is an acceptance requirement.

## Acceptance checks

1. Open Flight Deck in a browser tab, enter Focus Mode, and confirm the WebView/content fills the app surface.
2. Confirm the tab strip, hamburger, and avatar/account control are absent while focused.
3. Confirm the floating bottom-left restore control is visible, labelled, keyboard reachable, and does not create a replacement bar.
4. Exit Focus Mode and confirm the same tab, URL, page state, and existing tab collection remain intact.
5. Repeat with multiple tabs and at small/narrow desktop window sizes.
6. Check light/dark theme treatment if the app supports both.
7. Add focused widget tests for entering/exiting and active-tab preservation. Avoid brittle pixel-only assertions where semantic/widget-state assertions are possible.
8. Run `flutter test`, formatting/static analysis used by the repo, and at least the relevant build command (`flutter build web` unless platform-specific code requires more). Record exact results.

## Work and reporting rules

- Work directly on `main` unless the current repository state proves that unsafe.
- Inspect the full worktree first and preserve concurrent changes. Do not revert, reset, or overwrite work you did not create.
- When ready, commit all nonignored tested worktree state so `main` represents the tested state.
- Do not deploy, publish, launch, or restart a managed app/runtime without Pete's explicit approval.
- Post the implementation path, milestone updates, exact validation output, commit hash, and manual test instructions to the Flight Deck task. Rick will mirror useful status into the originating thread.
