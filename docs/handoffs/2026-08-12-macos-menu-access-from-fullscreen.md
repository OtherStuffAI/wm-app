# macOS menu access from full-screen

## Goal

Give Mac desktop users a reliable native menu-bar command that reveals or navigates to the Wingman App menu/sidebar, especially when the window is in macOS full-screen and the left-edge swipe gesture cannot be used.

## Source and symptom

Pete reported from the WMAPP features channel that, after entering full-screen on a Mac, he can become trapped in the current view because he cannot swipe the left-hand menu in from the side. He asked for an option in the Mac menu bar that takes him to the menu.

Originating Flight Deck message: `c0458b06-3b25-4188-a95b-c4cf569f1696`; thread: `13429d09-114e-4951-bc58-6895c015a1e0`.

## Required behavior

- Add a native macOS application-menu item with a clear label such as **Show Wingman Menu** or **Go to Menu**. Choose the menu grouping and wording that best match the existing macOS shell conventions.
- The command must work while the app window is in native macOS full-screen.
- Activating it must reveal/open or navigate to the same Wingman App menu/sidebar available through the normal left-side interaction.
- Preserve the current tab, embedded app/webview state, authentication, and navigation state; this is a shell/menu visibility action, not an app reset.
- If the menu is already open, the command should remain harmless and deterministic.
- Add a sensible keyboard shortcut if it does not collide with existing application or platform shortcuts. Surface the shortcut in the menu label and ensure keyboard-only use works.
- Keep non-macOS behavior unchanged, and do not introduce a second competing menu implementation.
- If the current architecture cannot deliver a native menu command to the Flutter/UI state directly, identify the smallest maintainable bridge and document its event/state path.

## Investigation notes

Inspect the existing macOS runner menu construction, Flutter method/event channels, and the UI state/controller that opens the shell sidebar. Reuse the current sidebar action rather than duplicating navigation logic. Check whether recent focus-mode or browser-shell work changes which chrome is visible in full-screen and make the command restore enough shell chrome for the menu to be usable.

## Validation

- Add or update focused tests for the command-to-sidebar action where practical.
- Run the repo's relevant Flutter/Dart tests, analyzer/lint, formatting checks, and macOS build command supported by the project.
- Manually or instrumentally verify normal window and native macOS full-screen behavior: invoke the menu-bar item, confirm the Wingman menu/sidebar becomes usable, invoke it again, and confirm the active tab/content state is retained.
- Verify keyboard invocation and that existing macOS application menu items still work.
- Record any signing/hardware limitation honestly; do not claim an on-device/full-screen visual check if only compilation or unit testing was possible.

## Worktree and reporting

Work on `main` in `/Users/mini/code/wingmanbefree/wm-app`. Inspect and preserve concurrent changes. Commit all nonignored tested worktree state unless there is a clear safety reason to pause. Do not push, deploy, install a build, or restart a managed runtime. Report the implementation path, validation output, commit hash, and any remaining manual test step to Rick through the linked Flight Deck task.

## Implementation path

The existing macOS `View` menu sends `showWingmanMenu` over the
`au.com.otherstuff.wingman/menu` Flutter method channel. `ShellHome` listens to
that channel only on macOS and calls its existing `_openDrawer()` action. The
same `Scaffold` drawer is therefore used by the native menu, the in-app menu
button, and the left-edge gesture. In browser Focus Mode the drawer also retains
the existing **Show controls** recovery action. Opening the drawer does not
select a surface or rebuild the browser tabs/webviews.

The native item is **View > Show Wingman Menu** with the keyboard equivalent
Shift-Command-M. Repeated invocation calls the idempotent `openDrawer()` path.

## Validation completed

- `dart format lib/src/features/shell/macos_menu_bridge.dart lib/src/features/shell/shell_home.dart test/widget_test.dart` — clean.
- Focused Flutter widget test for the native command path — passed.
- `flutter test` — all 42 tests passed.
- `flutter analyze` — no issues found.
- `flutter build macos --debug` — succeeded and produced
  `app/build/macos/Build/Products/Debug/wingman_app.app`.
- Compiled bundle inspection found `Show Wingman Menu`,
  `showWingmanMenu:`, and the existing `Enter Full Screen` item in
  `Contents/Resources/Base.lproj/MainMenu.nib`.
- `git diff --check` — clean.

The focused test invokes the macOS channel while browser Focus Mode is active,
opens the drawer twice, and verifies the active browser tab and webview
controller count do not change. It also verifies the existing **Show controls**
action remains available from the opened drawer.

## Remaining manual check

The app was compiled but not launched or installed during this task. On a Mac,
open the debug or signed app in both a normal window and native macOS
full-screen, choose **View > Show Wingman Menu**, and repeat with Shift-Command-M.
Confirm the drawer is usable both times, **Show controls** exits browser Focus
Mode when needed, the active tab retains its page/session, and the existing
View/Window application-menu commands still behave normally.
