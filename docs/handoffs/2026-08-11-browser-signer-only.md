# Ship WM App as browser signer only

Remove pre-packaged Flight Deck and Tower destinations from the shipped WM App. Pete will add destinations himself; the initial product should be a neutral browser signer.

Flight Deck task: `95b39d29-c2ac-4450-ba0f-becdcb3920e3`. Origin message: `69a77278-49e0-4a8b-b782-9668ce9015e5` in thread `aedc228d-a8da-49fb-9929-a8f4c7137403`.

## Acceptance

- Default configuration includes no bundled Tower URL or Flight Deck URL.
- Do not pre-create or pin a Flight Deck tab on first launch.
- Remove Flight Deck/Tower/Autopilot pre-packaged shortcuts from the new-tab page.
- First launch should open a useful neutral browser/new-tab signer surface, not an invalid URL or service-specific error.
- Preserve the browser signer, tab/navigation behavior, bookmarks, Focus Mode, settings, and user-added URLs/bookmarks.
- Existing users' intentional persisted configuration should not be silently erased; clearly document any migration behavior needed to distinguish old packaged defaults from user-entered values.
- Keep Tower/Flight Deck configuration fields only where they are genuinely needed for users to add them manually later. Pete asked to remove pre-packaged URLs, not prohibit future configuration.

Investigate `app_config.dart`, startup tab creation/restoration in `browser_screen.dart`, new-tab HTML, settings/setup, and current widget tests before editing. Update focused tests for clean first launch, no packaged shortcuts/pinned tab, persisted user config retention, and bookmark/signer regressions.

Run Dart formatting, `flutter analyze`, focused tests, full `flutter test`, `flutter build web`, and `git diff --check`. Work on `main`; preserve concurrent changes; commit all nonignored tested state. Do not deploy, publish, install to a device, or restart a managed runtime.

Report exact validation, commit hash, changed files, migration behavior, and remaining device checks on the task. Rick will review and update the originating thread.

## Migration behavior

- Fresh installs use empty Tower, Flight Deck, workspace, channel, app-npub, workspace-service-npub, and trusted-origin defaults. The Tower and Flight Deck setup fields remain available for manual configuration.
- Existing `wingman.app.config.v1` values are read unchanged. This intentionally preserves user-entered destinations. Because the previous schema did not record whether a value came from the package or the user, the app does not erase persisted values that happen to match an old packaged default.
- Existing per-signer tab snapshots retain every saved home tab and URL. The old package-owned `pinned` flag is ignored during restoration, so a previously stored Flight Deck tab becomes an ordinary closeable/reorderable tab instead of remaining permanently pinned.
- No bookmark or signer storage keys are changed.

## Remaining device checks

- On an upgraded iOS/Android installation, confirm previously configured destinations and tabs remain present but no tab is pinned.
- On a clean iOS/Android installation, confirm the first unlocked signer view is the neutral New Tab page and that manually adding Tower/Flight Deck settings still works.
