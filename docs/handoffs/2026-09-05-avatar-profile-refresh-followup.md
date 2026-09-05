# Required review correction: profile refresh after publishing

Implement in /Users/mini/code/wm/wmapp on main. Read docs/handoffs/2026-09-05-avatar-new-user-onboarding.md for complete original goal, constraints and reporting context. Task @[Avatar onboarding](mention:task:a3d52805-074d-4422-b939-b795a412e8b6). Original implementation f2343ad is committed and passed 119 tests, analyze and iOS simulator build. Manager reviewed it but withheld acceptance for this focused issue.

nostr_profile_store.dart saveRemote freezes local_edit=true permanently even after acknowledged publication. Protect unsent drafts but allow genuinely newer remote kind-0 profiles after acknowledged publication. Persist publication state/timestamps; never let a stale ack clear a newer draft. Same-second local publishes must get strictly increasing created_at. Propagate relay fetched event timestamps as needed. Preserve identity guards and local data migration. Add focused behavioral regression coverage for newer remote update after success, unsent draft survives newer remote event, failed publish preserves draft, stale ack/new edit race, and monotonic timestamp ordering.

Do not change other features. Do not deploy/install/restart or publish real user events. Preserve concurrent work; commit all nonignored tested state on main, including handoffs. Run flutter analyze and flutter test, plus unsigned iOS simulator build if production code changed. Report exact evidence, commit and limitations. Manager owns task comments/state and chat; worker task route was unavailable, do not spend time retrying. Finish with a self-contained final. Set session goal to this correction. Do not set next-action stop until final evidence complete.

## Worker correction handoff — 2026-09-05

Implemented on `main`, following original implementation `f2343ad`. The correction
commit is the commit containing this handoff (resolve with
`git log -1 --format=%H -- docs/handoffs/2026-09-05-avatar-profile-refresh-followup.md`).

### Result

- The existing per-identity v1 preference record now persists `draft_revision`,
  `last_publish_created_at`, `published_created_at`, and `remote_created_at`, along
  with `local_edit`. Local saves increment the revision, including identical
  content and cleared fields. Existing fields/avatar data and identity keys remain
  in place; legacy records with missing authorship metadata remain protected drafts.
- Publication atomically saves the draft and reserves a timestamp before signing.
  `created_at` is greater than the last reserved local timestamp and the last
  accepted remote timestamp, even across store recreation or same-second concurrent
  publishes. Failed attempts retain their reservation and unsent draft.
- Only a successful matching relay acknowledgement invokes publication persistence.
  It clears `local_edit` only if the saved revision and reserved timestamp still
  match. Older acknowledgements cannot clear later edits or reduce the acknowledged
  timestamp, including acknowledgements received out of order.
- Relay fetch returns the profile together with its event timestamp. Browser refresh
  retains the existing identity and generation guards and forwards that timestamp.
  The store protects drafts and rejects remote timestamps equal to or older than
  its acknowledged publication or accepted remote event. A genuinely newer remote
  event is accepted after publication of the current draft succeeds.
- README and the original handoff now point to the corrected refresh semantics.
  No unrelated feature, shared service contract, Rust code, or task routing changed.

### Validation evidence

All commands below ran from `/Users/mini/code/wm/wmapp/app` and exited 0:

```text
flutter test test/nostr_profile_publication_test.dart test/avatar_onboarding_test.dart
# 19 tests passed
flutter analyze
# No issues found! (ran in 1.4s)
flutter test
# 126 tests passed
flutter build ios --simulator --debug --no-codesign
# Xcode build done. 9.4s
# Built build/ios/iphonesimulator/Runner.app
```

`git diff --check` from the repository root passed. Seven additional behavioral
regressions cover acknowledged publication followed by newer remote data, stale/equal
remote rejection across store recreation, an unsent cleared draft, a delayed real
loopback relay acknowledgement after a new identical edit, concurrent same-second
publication and later publication above a remote timestamp, out-of-order
acknowledgements, legacy migration through publication, and fetched timestamp
propagation. Existing failure tests now attempt a far-newer remote event after
rejection, unrelated acknowledgement, disconnect, or malformed-frame timeout.
Existing identity isolation and onboarding UI tests continue to pass.

### Limits and reporting

- Tests use test identities, memory preferences, injected clocks/fakes and loopback
  WebSockets. No real user event was published. The simulator app was built only;
  no deployment, install, launch or service restart occurred.
- Physical-device persistence and actual relay interoperability remain untested.
  Rapid publications can intentionally reserve timestamps ahead of wall time;
  relay rejection still leaves a retryable draft. Remote events with equal
  timestamps are conservatively ignored.
- Previously saved profiles have no reliable historical publication receipt.
  They remain drafts until explicitly published successfully; the migration does
  not infer publication from identical remote content.
- The session goal was set to this correction in Codex and Autopilot, with Autopilot
  next-action `reflect` while working. The unavailable worker task route was not
  retried. Manager owns task comments, acceptance/state and chat reporting.
