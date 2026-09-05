# WMAPP avatar-menu new-user onboarding
Task: @[Avatar onboarding](mention:task:a3d52805-074d-4422-b939-b795a412e8b6). Read task/latest comments using explicit workspace above/below; report progress and completion evidence there when supported.
Pete's request: "the app should support a new user generating a key in the app and registering it, setting up a profile etc from the avatar menu."

Origin: @[Message](mention:message:b9f35445-9168-4392-8b6b-dbc8c9d25bee) in @[WMAPP features](mention:channel:d8d00881-ac84-41eb-ab0d-2c2afb77ddf3), thread 32517cf2-ea02-4553-94a4-1c464fddffd9, workspace 2e5caefd-dd65-45d2-b747-ee874e8e5fc9, scope 76d518f7-c477-4374-bf74-5d36fda570ed. No attachments or extra thread context at intake.

Implement in /Users/mini/code/wm/wmapp, main. Read applicable instructions. Preserve concurrent work; commit all nonignored tested state including this handoff, do not discard or overwrite other changes. No deploy, device install, service restart, or real-user secret access.

Confirmed: browser_screen.dart avatar menu offers Edit profile/Setup/Signer/Status; _editProfile only persists local NostrProfileStore, while relay client fetches kind 0. SetupScreen already has registerDevice; README describes Dart key generation/import and encrypted PIN vault. Investigate existing first-run/vault UI before changing it; reuse the existing cryptography and custody.

Outcome:
- A first-time user can reach a clear create-identity flow from avatar menu, generate a Nostr key securely in-app, persist/unlock through existing vault, and set name/display name, avatar URL and supported profile fields.
- Existing identity is never silently replaced. Import/unlock/back/cancel remain usable. No secret material in logs, network profile payloads or ordinary unencrypted preferences. Preserve signing approvals.
- Profile setup/edit supports signing and publishing Nostr kind-0 through existing relay settings with honest success/error/retry UI; retain local draft if publication fails. Remote refresh must not clobber a newer local edit or another identity's state.
- Registration interpretation is being clarified by manager. Default scope if no answer: public Nostr profile publication, with explicit Tower/device registration available when configured using existing supported path. Do not invent central Nostr registration or bundle a Tower URL; never equate local save with successful remote registration.
- Keep normal browser-signer first-run useful without Tower configuration. Mobile/desktop avatar menu and layout must work.
- Investigate whether the intended registration can reuse current app APIs. Stay in WMAPP; if shared contract/architecture changes required, stop at a concrete diagnosis, resolve/read latest Wingman Suite Architecture artifact (not hardcoded v3) before proposing changes, and report to manager.

Validation: focused meaningful tests for new-user avatar entry/key flow, existing-identity/cancellation protection, profile signed publication ack/failure and persistence; flutter analyze, flutter test in app; an appropriate available Flutter build. Cargo tests only if Rust changes. Use local fakes/test keys; don't publish real profile events. Report exact commands/results, commit, changed files, remaining device/live tests.

Manager owns final thread reply and task review state. Worker should read task/latest comments, post concise progress and validation to task if route available; if not, return evidence to manager, do not fabricate routing. Do not post chat or mark review itself. Set session goal for this outcome and next-action reflect while work remains; final handoff includes any blocking assumption.

## Worker implementation handoff

Implemented on `main` in the requested checkout. The intake above is preserved.

- First launch opens the browser without Tower. Avatar → Create identity / Import key opens the existing PIN-vault screen with secure Dart generation or import. New identities continue to profile setup. Locked identities offer Unlock identity; logout retains the encrypted vault. Back/cancel before creation does not persist a key. Explicit reset remains destructive and warns about loss without a backup.
- Reused `NostrCrypto.generateIdentity`, `SignerVault.create/unlock`, AES-GCM, PBKDF2 and per-install secure storage. Creation refuses existing or unreadable vault records and concurrent creation attempts. Setup public-key fields are read-only and cannot change the vault identity. No signing-policy/approval bypass was added.
- Profile editor supports the existing six public fields, local Save, explicit Sign and publish, acknowledged relay counts/URLs, failure status and Retry publication. The publisher saves a draft before signing kind 0 through existing Dart cryptography. Only a matching Nostr `OK` with `true` counts as acceptance; rejection, unrelated/malformed frames, disconnect and timeout do not.
- Publication uses the existing profile relay client configuration (default Damus and Primal). There was no separate persisted relay-settings UI in this checkout. No Tower endpoint was bundled. Public payloads are built only from `toKind0Json`; key and avatar-cache material are excluded.
- Profile writes are serialized per identity. Local authorship is persisted; local/legacy saved edits, including clearing fields, remain authoritative across restarts. UI refresh generations and identity checks reject delayed refreshes. This deliberately means automatic refresh will not replace a locally authored profile with edits from another Nostr client.

### Registration interpretation and supported APIs

No clarification arrived through the worker context. Applied the authorized default: “registration” means public Nostr profile publication, with optional Tower/device registration kept separate. A local save is explicitly described as an unpublished draft.

`SetupScreen._registerDevice` already calls `NativeCoreBridge.registerDevice`, which invokes the desktop `wmapp-core device register` path with the configured workspace-service and device npubs. Setup now exposes that action and its configured destination when `canRegisterDevice` is true, even with experimental Drive disabled. Its registration signer input and existing failure reporting are retained. The bridge reports the process-backed operation as unavailable on mobile. This work did not add a mobile Tower registration API or change any shared contract. No shared architecture proposal was needed; the conditional architecture-artifact escalation was not triggered. If the manager means mandatory mobile Tower account/device enrollment, that remains a distinct scope decision.

### Routing evidence

Task and latest-comment reads were attempted with explicit workspace in `/Users/mini/code/wm/autopilot`:

```text
bun clis/wingman.ts flightdeck task show a3d52805-074d-4422-b939-b795a412e8b6 --workspace 2e5caefd-dd65-45d2-b747-ee874e8e5fc9 --json
bun clis/wingman.ts flightdeck task comments a3d52805-074d-4422-b939-b795a412e8b6 --workspace 2e5caefd-dd65-45d2-b747-ee874e8e5fc9 --json
```

Both exited 1: `Missing Flight Deck PG Tower URL`. The `flightdeck_context` helper returned `hasRunContext: false`, null workspace/backend and empty routing. No task/comment route could therefore be verified. No chat, task-state or fabricated task-comment writes were made. Manager must attach this evidence to the original task and own the final thread/review-state update.

The worker's Autopilot session goal was set with `bun clis/sessions.ts metadata-update "$SESSION_ID" --goal ... --next-action reflect` while work remained; a matching session goal was also created in Codex.

### Validation

Final commands are run from `/Users/mini/code/wm/wmapp/app`:

```text
flutter analyze
flutter test
flutter build ios --simulator --debug --no-codesign
```

Results: `flutter analyze` exited 0 with no issues; `flutter test` exited 0 with **119 tests passed**; `flutter build ios --simulator --debug --no-codesign` exited 0 (Xcode build 10.3 seconds). `git diff --check` also exited 0.

The simulator artifact is `app/build/ios/iphonesimulator/Runner.app` (ignored build output). No device install, deployment, service restart, or live profile publication was performed. All identities, vault stores and relay acknowledgements in tests use test keys, memory stores, injected fakes or loopback WebSockets. Rust was unchanged, so Cargo tests were not applicable.

Focused coverage includes secure generated-vault round trips, import, invalid input, existing/unreadable/concurrent-vault protection, avatar/back/reset cancellation, profile setup and unlock at 390×844 and 1280×900, signed-event verification and public field whitelist, partial acknowledgement, rejection/unrelated frames/disconnect/malformed-frame timeout, empty relays, identity mismatch, persisted draft recovery, concurrent refresh/local edits, cross-identity refresh isolation, and configured Tower action visibility.

During development, the old mandatory-import first-run expectation was updated, and new test harness scrolling/Material issues were corrected. An initial `flutter analyze` from the repository root also traversed the separately vendored plugin without its package configuration; the authoritative analysis is the clean app-directory run above.

### Remaining live/device checks

- Physical iOS/Android and desktop secure-storage/PIN round trip after app restart; soft keyboard and system-back interactions; platform keychain behavior.
- Explicitly authorized publication with a disposable identity against actual relays, including offline/reconnect retry and independent profile retrieval.
- Configured desktop Tower device registration against an approved test workspace. Mobile Tower registration remains unsupported by the existing process bridge.
- The create flow does not add key backup/export. It explains that losing the vault/PIN can lose the identity; existing custody has been reused.

### Changed files

- `app/lib/src/app.dart`, `features/shell/shell_home.dart`: browser-first shell and avatar vault routing.
- `app/lib/src/core/signer_vault.dart`, `features/onboarding/signer_onboarding_screen.dart`: generation/import UI, custody reuse and overwrite protection.
- `app/lib/src/features/browser/browser_screen.dart`: avatar identity actions, explicit profile save/publish/retry and refresh guards.
- `app/lib/src/features/browser/nostr_profile_store.dart`, `nostr_profile_relay_client.dart`, new `nostr_profile_publisher.dart`: draft persistence, write ordering, signed publication and relay acknowledgements.
- `app/lib/src/features/setup/setup_screen.dart`: immutable identity fields and explicit configured Tower registration.
- `app/test/avatar_onboarding_test.dart`, `nostr_profile_publication_test.dart`, `signer_vault_test.dart`, `widget_test.dart`: focused and regression coverage.
- `app/README.md` and this preserved handoff: flow documentation, evidence and limitations.
