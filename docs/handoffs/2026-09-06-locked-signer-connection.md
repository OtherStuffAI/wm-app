# Repair locked signer startup regression

Pete reports existing Flight Deck workspaces repeatedly route to Connect to a Tower and fail with `FormatException: secret key must be 32-byte hex or nsec` on iPhone, both bundled and hosted long-tin-knob.rick.runwingman.com. Origin is direct manager chat with no Flight Deck record binding; report to supervising session only.

Read-only diagnosis identifies f2343add8493625d62a1eb7fb76002ceab73f704 (September 5 avatar onboarding). app.dart now restores public identity and opens ShellHome while deviceSecret remains empty, and browser_screen.dart advertises window.nostr / returns getPublicKey then passes signing requests into NativeCoreBridge with empty key. Dart crypto emits screenshot error. Same-identity unlock does not refresh tabs because didUpdateWidget only checks npub changes. Screenshot path is /Users/mini/code/wm/autopilot/tmp/uploads/images/npub1jss47s4fvv6usl7tn6yp5zamv2u60923ncgfea0e6thkza5p7c3q0afmzy/codex/ad8c5199-88f6-47de-a81b-09e314b65276.png.

Implement smallest complete repair: existing saved-vault startup must obtain unlock before authenticated tabs sign, retaining fresh-install avatar onboarding. Prefer reusing established unlock UI for existing vault; if maintaining locked browsing, signing must await an actual unlock flow. Explicit locked guards for native signEvent and signNip98 should prevent empty secret reaching crypto after logout/in-flight requests. Preserve tabs/bookmarks/web storage and intentional onboarding/profile changes. Do not generate replacement identity or persist plaintext keys. Use synthetic fixtures only, never read real vault/keys/env secrets.

Test cold start existing fixture vault, fresh install, locked signEvent/signNip98, post-unlock signing, logout and same-identity recovery. Run repo-required focused/full Flutter tests and analysis. Inspect current concurrent changes before edits: browser_screen.dart, shell_home.dart, profile upload/export files and tests are intentional. Main default; preserve all and commit compatible nonignored tested state, no destructive git. Do not change adjacent repos, restart Autopilot, publish TestFlight or install on device. Report exact device build/release requirement and remaining iPhone smoke test. Separate worker repairs Flight Deck workspace selection erasure; coordinate through manager only.

## Implementation and validation

Saved-vault cold startup now presents the established PIN unlock screen before
constructing ShellHome or any restored WebView. Fresh installs still enter the
browser and create/import identity through the avatar. Logout retains the shell
and public identity; same-identity unlock reloads existing non-home WebViews to
retry authentication without switching identities, replacing controllers, or
clearing browser data.

Both native signing entry points reject empty/whitespace secrets with
`Signer is locked. Unlock your identity with your PIN and retry.` The browser
also rejects locked signing requests before approval UI. Native calls use the
current widget configuration after asynchronous approval/policy work, so a
logout during those waits reaches the native locked guard.

Synthetic in-memory vault coverage verifies cold-start gating, restored tabs,
post-unlock signing, logout rejection through the JavaScript bridge, and
same-identity recovery with unchanged controller count and no cookie clearing.
Existing fresh create/import and profile tests remain passing. No real vault,
private key, environment secret, or device data was accessed.

Validation: 11 focused Flutter tests passed; all 135 Flutter tests passed;
`flutter analyze` reports no issues; `git diff --check` passes. Bundled HTML/JS
asset references resolve in the existing concurrent bundle state. Existing
onboarding/profile upload/export changes and their tests are retained in this
checkpoint, together with the concurrent bundle cleanup and iOS test-team
configuration. Flutter's compatibility migration normalized Xcode objectVersion
back to 54 during the device build.

## Required iPhone follow-up (supervisor only)

The installed native WMApp must be rebuilt with this repair. Updating hosted or
bundled Flight Deck JavaScript alone cannot repair its locked native signer.
For standalone Home Screen use, build a **signed release**, using
`./build_ios_release.sh` (`cd app && flutter build ios --release`), preserving
bundle `com.wingmanbefree.wingmanApp` and existing signing configuration. The
repository's device install artifact is
`app/build/ios/Release-iphoneos/Runner.app`. The local version remains `0.1.6+7`;
a future TestFlight upload requires a verified unused build number, distribution
archive/export, and separate upload/processing approval. An unsigned validation
build is not an installable or published release.

Remaining physical iPhone smoke test: upgrade in place without uninstalling or
resetting storage; cold-launch an existing vault; verify PIN unlock precedes
restored bundled and hosted Flight Deck authentication; confirm selected tabs,
bookmarks, workspace/cache data and drafts remain; sign via both NIP-07 and
NIP-98; log out, verify explicit locked rejection, unlock the same identity and
confirm authentication recovers; separately verify fresh-install avatar
onboarding using a disposable fixture environment. Workspace selection-loss
repair remains the separate Flight Deck worker's responsibility.

No device installation, TestFlight publication, Autopilot restart, adjacent-repo
change, or external status message was performed.

Local iPhone compilation passed: `cd app && flutter build ios --release
--no-codesign` produced `app/build/ios/iphoneos/Runner.app` (25.8 MB), with
codesigning explicitly disabled. Xcode build completed in 36.8 seconds.
