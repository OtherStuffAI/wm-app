Task: @[Publish WMAPP iOS build to TestFlight](mention:task:c283a246-f555-4128-8359-ade7a11b454c)

Publish the current WMAPP iOS app to TestFlight for Pete. Full request: "Can we publish a version of this app to test flight please?" No tester audience was specified: use existing private/internal testing configuration for Pete; do not create a public link or invite arbitrary people.
Origin @[Message](mention:message:e1263a56-c148-4d5c-8b82-b8492ccb90be) in @[WMAPP features](mention:channel:d8d00881-ac84-41eb-ab0d-2c2afb77ddf3), thread 832a5265-752a-48ee-8ecd-be15eb3077c4, workspace 2e5caefd-dd65-45d2-b747-ee874e8e5fc9, scope 76d518f7-c477-4374-bf74-5d36fda570ed.
Workdir /Users/mini/code/wm/wmapp on main. Read applicable instructions, docs/deploy/iphone.md, build_ios_release.sh. Current helper only builds signed device app; no verified TestFlight process yet. Inspect current signing team, distribution eligibility, Apple tools and existing authorized App Store Connect authentication WITHOUT printing/extracting secrets. Never search for or export Nostr keys. No account purchase, agreement acceptance, destructive signing changes or service restart. User authorizes TestFlight upload; do not ask again for that authorization.
Check official Apple/Flutter documentation where needed. Prepare release metadata, archive/export and upload via available authorized signing/authentication. If authentication or distribution setup blocks upload, still complete useful safe local release prep and report precise blocker and smallest user action; stop repeated blocked paths after two evidenced failures. Do not change bundle identifier/team without evidence it is intended. Do not make speculative export-compliance declarations.
Software changes are delegated to you: preserve concurrent work, default main, commit all nonignored tested worktree state including handoff, inspect entire state first, do not reset/rebase/force-push or discard unrelated edits. Push source if appropriate for release. No changes outside repo except local build diagnostics.
Acceptance: produce a correctly versioned archive/IPA, validate relevant iOS build behavior, upload to App Store Connect and verify processing/TestFlight availability if authorized credentials exist. Distinguish local build/upload/processing/tester availability. Report version/build, bundle/team, source commit, validation, artifact paths, Apple receipt/status, and exact blockers. Never claim published on local build alone.
Read task and latest comments at start and before handoff. Post execution contract and significant milestones plus final evidence to task using broker-aware Flight Deck CLI; manager handles originating thread and review state. Set your session goal and next action reflect; return final callback with evidence.


## Execution contract and release evidence — 2026-09-06

Status: **blocked at distribution export; not published to TestFlight**.
Manager owns originating-thread reporting and task review state.

### Contract

Prepare the current main app for Pete's existing internal/private TestFlight
configuration, validate the iOS release archive, export/upload through existing
authorized Apple access, and distinguish upload, processing and tester access.
Preserve bundle/team and concurrent work; no public links or additional testers.

The worker could not post this contract or read task/latest comments: the normal
Flight Deck CLI and explicit `--bot-crypto` route both returned `Missing Flight
Deck PG Tower URL`. The context helper returned no workspace, backend URL, task
or thread. No further identical route attempts were made. This remains unresolved
at handoff; the manager must read latest comments and post this evidence using its
working task context. No task comment/state mutation or chat reply was claimed.
Session goal was set with next-action `reflect`.

### Version and source

- Version/build: **0.1.6 (7)**, advanced from repository **0.1.5 (6)**.
- Bundle: `com.wingmanbefree.wingmanApp`; display name: `Wingman App`.
- Team: `N5DRUM6S94`, profile team name `Peter Winn`.
- Archive: release configuration, arm64, iOS minimum 13.0.
- Source base: `aed4797` on `main`, including existing commits `f2343ad` and
  `aed4797` (avatar onboarding/profile publication and refresh correction).
- Release source commit: the commit containing this handoff; resolve with
  `git log -1 --format=%H -- docs/handoffs/2026-09-06-testflight-release.md`.
  Archive application source equals this commit's app tree. The archive was
  built after the version change; subsequent changes are release tooling/docs.
- App Store Connect build-number uniqueness could not be checked without access.

### Local results

- `flutter test --reporter expanded`: **126 tests passed**.
- `flutter analyze`: **no issues found**.
- `flutter build ipa --release --export-options-plist=../docs/deploy/TestFlightExportOptions.plist`:
  **archive built**, 188.0 MB, Xcode archive duration 61.6 seconds. Flutter's app
  settings validation passed. Flutter returned 0 despite IPA export failure.
- `codesign --verify --deep --strict --verbose=2` on the archived Runner.app:
  **valid on disk; satisfies its Designated Requirement**.
- Archive and application plists independently confirm bundle/team/version/build.
  Embedded profile has `get-task-allow=true`: this is development signing awaiting
  App Store distribution export, not a distribution-signed IPA.
- `bash -n build_ios_testflight.sh build_ios_release.sh`, export plist lint and
  `git diff --check` passed. The helper's full build invocation was exercised by
  the equivalent direct Flutter command; the new wrapper itself was syntax-checked.
- Tools: Xcode 26.3 (17C529), Flutter 3.44.4, Dart 3.12.2; Apple `altool` and
  `iTMSTransporter` are installed under Xcode.
- No physical device install/launch was performed. Widget tests cover onboarding,
  browser and identity flows, but do not establish on-device runtime behavior.

### Apple distribution failure and smallest next action

Two export attempts were made, then stopped:

1. Flutter archive/export: `exportArchive No Accounts`, `No signing certificate
   "iOS Distribution" found`, and `No profiles for
   'com.wingmanbefree.wingmanApp' were found`.
2. Explicit `xcodebuild -exportArchive ... -allowProvisioningUpdates`: exit **70**,
   with the same account/certificate/profile errors.

Only one valid local signing identity was found, an Apple Development identity.
The available provisioning profile is an iOS development wildcard profile,
expiring 2027-07-31. Xcode preferences contain an Apple account entry, but Xcode's
export process reports **No Accounts**. No relevant Apple auth environment
variables or `.p8` files in the two standard home API-key directories were found.
No credential contents were printed or extracted; no Nostr keys were searched.
Paid-program eligibility, app-record existence and Pete's tester configuration
remain **unverified**, not proven absent.

**Pete/account administrator:** in Xcode Settings > Accounts, sign in or restore
the authorized Apple Developer account for `N5DRUM6S94` and confirm this team's
App Store Connect/distribution access. If the team is already eligible, allow
Xcode's normal distribution signing setup, then retry the documented export.
If eligibility or an agreement needs attention, the account holder must handle
that separately. No purchase, agreement acceptance, certificate revocation,
bundle/team replacement, or service restart was performed.

After access returns, inspect the existing App Store Connect app and build history
before upload, validate in Organizer, upload with internal-only settings, and
verify processing and Pete's existing private group. No speculative encryption
answer was added: `ITSAppUsesNonExemptEncryption` remains absent. Encryption use
requires an informed declaration before any compliance prompt can be completed.

Additional preflight observations: Flutter warns that the launch image is still
the default placeholder. The existing 1024px WM bird icon is branded, but its PNG
reports an alpha channel; App Store validation has not run, so check asset
acceptance before upload. These assets were preserved.

### Artifacts and reproducible preparation

All paths below are relative to `/Users/mini/code/wm/wmapp`:

- Signed development archive: `app/build/ios/archive/Runner.xcarchive`.
- Archived app: `app/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app`.
- **IPA: none**; export destination was `app/build/ios/ipa`.
- Diagnostics (ignored local files): `build/testflight-diagnostics/archive.log`,
  `export-retry.log`, `flutter-test.log`, `flutter-analyze.log`,
  `codesign-verify.log`.
- Reusable helper: `build_ios_testflight.sh`; it fails when Flutter has not
  produced a fresh IPA, protecting against false success and stale artifacts.
- Export options: `docs/deploy/TestFlightExportOptions.plist`, local App Store
  Connect export, automatic signing for the existing team, internal-only testing,
  explicit version preservation and symbol upload.
- Updated runbook: `docs/deploy/iphone.md`.

Apple receipt/build ID: **none**. Upload: **not attempted because export failed**.
Processing: **not started**. Pete's TestFlight availability: **not verified / this
build was not delivered**. No public link or tester invitation was created.

### Draft What to Test

Open Wingman App and check the bundled Flight Deck browser. Exercise avatar
onboarding, creating or importing an identity, PIN lock/unlock and profile editing.
Check profile publication feedback and that a newer remote profile can refresh
after an acknowledged publication while an unsent local edit remains protected.
Use test identities for publication testing. Confirm the app reopens normally
from the iPhone Home Screen without a debugger.

### References

- [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios)
- [Apple distribution workflow](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Apple internal testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)
- Installed `xcodebuild -help` confirms `app-store-connect`, `destination`,
  `testFlightInternalTestingOnly` and `manageAppVersionAndBuildNumber` options.
