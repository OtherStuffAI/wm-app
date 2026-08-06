Implement the corrected WM-App Focus Mode follow-up in this Flutter repository.

Read `docs/handoffs/2026-08-06-focus-mode-show-controls-and-safe-area.md` and the referenced original Focus Mode handoff completely. This is explicitly a WM-App native-shell task; do not modify `wm-fd-2`.

Acceptance: remove the floating Focus Mode restore button; preserve the left-edge swipe navigation while focused; add a labelled `Show controls` action there using the existing Focus Mode exit state/callback; preserve active WebView/tab state; remove the unintended empty strip below WM-App's iPhone bottom Deck / Chat / Tasks navigation while keeping real home-indicator protection correctly composed; add focused tests; run format, tests, analysis, and relevant build validation; commit all nonignored tested shared-worktree state on `main`.

Do not deploy, launch, publish, or restart a managed app. Preserve concurrent work and do not reset/discard changes you do not understand.

Tracking task: `623233a8-3849-4284-8b67-35fb3ac79a20`, workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`. Post milestones/evidence to the task if broker-aware tools permit it; otherwise include them in the supervised callback. Rick owns Pete's chat-thread updates.
