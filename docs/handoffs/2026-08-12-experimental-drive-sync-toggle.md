# Gate experimental Flight Deck Drive sync UI

## Goal

Hide the unfinished Flight Deck Drive-sync configuration and Drive navigation behind an explicit experimental feature checkbox.

Origin: Flight Deck features-channel message `a230adf3-71ca-4d50-b795-54967ec47a83`, thread `c922d1a7-a156-4d89-975a-5a77c73e7031`.

Flight Deck task: `4faf9bd9-616d-4f16-a9a3-79853e4fb366` in workspace `2e5caefd-dd65-45d2-b747-ee874e8e5fc9`.

## Required behavior

- Add a checkbox at the bottom of Setup labelled exactly: `Display experimental future Flight Deck Drive sync`.
- The setting defaults to `false` for a fresh install/configuration.
- Persist the setting with the existing app configuration so an explicit opt-in survives restart.
- When false, hide all Drive-sync configuration fields shown in Setup:
  - Tower URL
  - Flight Deck App npub
  - Flight Deck URL
  - Workspace ID
  - Workspace service npub
  - Default Channel ID
  - any other controls that exist solely for the unfinished Drive/device-sync workflow
- When false, hide the `Drive` destination from the left navigation.
- When true, restore the existing fields and Drive navigation behavior without changing their semantics.
- Preserve previously stored field values while hidden; toggling the experiment off must not erase configuration.
- Keep browser-signer settings and unrelated Setup controls visible and unchanged.

## Compatibility and UX

- Existing saved configs that lack the new property must resolve to false.
- The checkbox itself remains visible at the bottom of Setup in either state.
- Avoid presenting this as production-ready sync; it is explicitly experimental/future functionality.
- Keep changes scoped to `wm-app`.

## Validation

- Add/update focused widget/config persistence tests for default false, opt-in persistence, conditional Setup fields, and conditional Drive navigation.
- Verify toggling off does not clear pre-existing Drive configuration values.
- Run Dart formatting, `flutter analyze`, focused tests, full `flutter test`, `flutter build web`, and `git diff --check` where the environment supports them.
- Work on `main`, preserve concurrent changes, and commit all nonignored tested state. Do not deploy, publish, install, or restart managed services.

## Reporting

Report implementation path, files changed, exact validation, commit hash, and any remaining device-only checks on the linked Flight Deck task. Rick will review the result and update the originating chat thread.
