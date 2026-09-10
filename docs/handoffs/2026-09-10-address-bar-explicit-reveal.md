# Address bar: explicit reveal only

Task: 74221975-27da-4b25-ba45-dd56aaf5fcf1

Pete requests: “When i swap tabs I no longer want to see the address bar for 5 seconds, the address bar should only be displayed when I explicitly click the tab bar again to show it.”
Implement in /Users/mini/code/wm/wmapp only. Source: @[Request](mention:message:7be77b42-9b1c-4c4c-908c-f3a53fbcfa63) in @[WMAPP features](mention:channel:d8d00881-ac84-41eb-ab0d-2c2afb77ddf3), thread 8687ace2-9047-4b98-933e-940ad22c1bbd, workspace 2e5caefd-dd65-45d2-b747-ee874e8e5fc9, scope 76d518f7-c477-4374-bf74-5d36fda570ed.
Current starting evidence: app/lib/src/features/browser/browser_screen.dart manages _addressBarVisible and timed reveal. Inspect tab selection and new-tab/restore/close selection paths. Eliminate automatic five-second address-bar reveal on switching tabs; switching while visible should hide it. Explicit click/tap on already-active tab should still reveal it. Preserve normal editing/dismissal and focus mode; interpret only explicit tab-bar action as reveal, investigate any automatic creation/restore reveals consistently. Cover relevant desktop/mobile shared interactions. No architecture or cross-repo changes expected.
Work on main; preserve concurrent changes, inspect full worktree and commit all nonignored tested state, do not reset/revert others. Read repo instructions. Validate using Flutter analyze on changed Dart files and focused existing browser widget tests; add meaningful behavioral regression tests for switching hidden/visible and active-tab reveal, using repository toolchain. Report exact commands/results, commit, changed files, residual limitations. Do not release/store-publish or restart Autopilot. Manager handles chat and final task review state. Worker should read task/comments and leave validation evidence on task if broker access permits, otherwise return evidence to manager.

Set worker session metadata goal to implement and validate this behavior, next-action reflect while working and stop on handoff. Send no chat reply; return final to manager through supervised callback.

## Worker implementation and validation

Implemented on main in wmapp. Pointer selection, Ctrl+Tab/edge selection,
active-tab close, and activated home/web tab creation hide the address bar and
cancel its timer before changing selection. Startup and restored tabs stay hidden.
Clicking the already-active tab retains the existing reveal/dismiss toggle and
three-second reveal timeout; focused editing and normal dismissal are preserved.
Background-tab close does not automatically reveal the address bar.

Changed implementation: `app/lib/src/features/browser/browser_screen.dart`.
Changed regressions: `app/test/widget_test.dart`. Tests cover macOS (1280x800),
iOS and Android (390x844), hidden/visible switching, active-tab reveal, editing
across switches, creation/openTab, active/background/last-tab close, restoration,
keyboard selection, and existing focus mode/edge navigation behavior.

Toolchain: repository's PATH Flutter 3.44.4, Dart 3.12.2.
Final commands and results:

- From repo: `dart format app/test/widget_test.dart` — success.
- From app: `flutter analyze lib/src/features/browser/browser_screen.dart test/widget_test.dart` — exit 0; no issues found (1.1s).
- From app: `flutter test test/widget_test.dart test/focus_edge_gestures_test.dart` — exit 0; all 38 tests passed (12s).
- From repo: `git diff --check` — exit 0.

Initial regression runs exposed test-harness issues (platform override cleanup
and offscreen/lazily built mobile tabs); corrected before the final passing run.
Full nonignored worktree inspected: only the two Dart files and this pre-existing
untracked worker brief. Brief preserved and included as requested.

Limitations: widget tests use fake WebViews/platform overrides, with no physical
mobile or desktop runtime smoke test or release build. No publish, restart or
push performed. Task comments were readable and writable, but CLI task show
was denied with `NIP-98 origin is not allowed`; supplied brief and task comments
provided the execution contract. Manager handles final review state and chat.
