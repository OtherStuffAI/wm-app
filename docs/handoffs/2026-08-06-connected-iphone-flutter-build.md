# Build and install WM-App Flutter on Pete's connected iPhone

Flight Deck task: `db795939-b289-489a-ae08-1bd084fc8920`.

Pete explicitly requests a fresh Flutter WM-App build installed onto his currently connected physical iPhone. A prior manager action incorrectly deployed Flight Deck web assets; do not repeat that.

Origin: message `e5c94f1f-e308-480b-81af-44731b6584ed`, thread `cc772551-c396-409d-ba5c-42f5aae173a6`, channel `0617d526-88dc-4dc2-9876-08349ab60eca`, workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`.

Repo: `/Users/mini/code/wingmanbefree/wm-app` on `main`. Flutter app: `/Users/mini/code/wingmanbefree/wm-app/app`.

## Required execution

- Inspect repository and worktree first; preserve concurrent changes.
- Enumerate Flutter and Xcode devices. Select Pete's physically connected iPhone by name/UDID and availability; do not use a simulator.
- Inspect the existing iOS bundle/team/signing setup without exposing certificates, keys, provisioning contents, or other secrets.
- Run `flutter pub get` and appropriate focused Flutter tests when practical.
- Build the current Flutter iOS app with codesigning for the physical device, install it, and launch it on that exact iPhone.
- Prefer a command that finishes after successful installation/launch. If `flutter run` is the supported route, detach cleanly once launch is confirmed rather than leaving an indefinite worker process.
- Capture exact evidence: device name/UDID, source commit, worktree state, build mode, signing/team success, app artifact path, installation success, and launch success.
- If blocked by lock state, pairing/trust, Developer Mode, provisioning, signing, or device availability, stop after safe diagnostics and report the exact Mac/iPhone action Pete must take. Do not reset the device, delete provisioning data, alter signing identities, or perform destructive Xcode cleanup.
- Do not modify source merely to force a build unless a genuine current-source defect is proven. If code changes are needed, report that before expanding scope.
- Do not push, deploy Flight Deck/web assets, restart services, or build the macOS app.

Report the final evidence to the Flight Deck task. Rick will mirror it to the originating chat thread.
