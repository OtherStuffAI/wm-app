# Diagnose WM-App iPhone launch failure

Pete reports that the freshly built and installed Flutter WM-App immediately fails when opened on his connected iPhone.

Device: Peter's iPhone, iPhone 15 Pro, iOS 26.5.2, UDID `00008130-001824141442001C`.
Installed bundle: `com.wingmanbefree.wingmanApp`, version 0.1.1 build 2.
Previous source: `main` at `31f93411443cea05f7b38bc5303fcbad16441e90`.
Flight Deck task: `db795939-b289-489a-ae08-1bd084fc8920`.

Required work:

- Preserve concurrent work and inspect the full worktree before editing.
- Reproduce on the physical iPhone, not a simulator.
- Capture the device console/crash/termination evidence for this bundle and identify the precise failing code or iOS contract.
- Implement only the evidence-backed fix in `wm-app`.
- Run focused and full relevant Flutter tests.
- Rebuild, sign, install, and launch on the same connected iPhone.
- Verify the process remains alive and the first screen renders; do not treat installation alone as success.
- Commit all nonignored tested repository state on `main`, preserving concurrent changes. Do not push or deploy.
- If the phone is locked or unavailable, use safe diagnostics and report the exact action needed without destructive cleanup or signing changes.

Report root cause, changed files, commit, tests, build/install evidence, and physical-device launch/stability evidence.
