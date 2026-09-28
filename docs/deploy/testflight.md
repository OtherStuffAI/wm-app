# Private iOS TestFlight release checks

Use the existing Apple team `N5DRUM6S94` and these identifiers:

- Runner: `com.wingmanbefree.wingmanApp`
- Packet Tunnel: `com.wingmanbefree.wingmanApp.FipsPacketTunnel`

## Account and version

Open [App Store Connect](https://appstoreconnect.apple.com/apps) using the
authorized Apple account. Verify the app by bundle identifier, inspect its
TestFlight build history, and record the existing internal group that contains
the intended tester. Check its current members and automatic distribution
settings before uploading. Do not create another group, invite testers, enable
a public link, or distribute to other groups.

Choose a build number greater than the existing iOS builds and update
`app/pubspec.yaml`. Runner and FipsPacketTunnel use Flutter's generated version
and build settings. A local build number remains provisional until checked
against App Store Connect.

For account recovery on the build Mac, use **Xcode → Settings → Accounts**.
Sign in or reauthenticate the existing authorized Apple account and verify
that the intended team appears. Complete Apple's two-factor challenge directly
in Apple's UI. Also sign in to App Store Connect in the browser so build history,
compliance and tester access can be inspected. Never put credentials in chat,
source files or build logs.

Both App IDs require the Network Extensions `packet-tunnel-provider`
capability. Automatic distribution export needs Apple Developer Program access
and suitable distribution profiles for both targets. A development certificate
or a macOS Developer ID certificate does not establish iOS distribution access.

## Build and inspect

Run Flutter validation sequentially; concurrent Flutter commands can race while
regenerating iOS package files:

```sh
cd app
flutter analyze
flutter test
cd ..
./build_ios_testflight.sh
```

The helper builds the pinned FIPS core, fetches and builds Flight Deck main,
archives Runner, and checks that a fresh IPA was exported. Record the Flight
Deck commit and bundle version from the build output. Preserve an existing
archive before rebuilding if it is needed for comparison or recovery.

Inspect each signed target, not just Runner:

```sh
codesign --verify --deep --strict app/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
codesign -d --entitlements :- app/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
codesign -d --entitlements :- app/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/PlugIns/FipsPacketTunnel.appex
```

Check the target Info.plists for the expected identifiers and matching
`CFBundleShortVersionString`/`CFBundleVersion`. Decode each embedded provisioning
profile with `security cms -D -i <profile>` into private local evidence. Report
only the team, application identifier, expiry, profile class and required
entitlements; do not publish provisioned device identifiers. Verify the exported
IPA separately after extraction: its distribution profiles should not contain
`ProvisionedDevices`, and `get-task-allow` should be false. Verify the app icon
and record SHA-256 checksums for the IPA and signed executables.

After restoring account access, retry an existing archive without rebuilding:

```sh
xcodebuild -exportArchive \
  -archivePath app/build/ios/archive/Runner.xcarchive \
  -exportPath app/build/ios/ipa \
  -exportOptionsPlist docs/deploy/TestFlightExportOptions.plist \
  -allowProvisioningUpdates
```

If the provisional build number conflicts with Apple's history, update the
version first and rebuild; do not upload the conflicting archive.

## Encryption inventory

WMAPP uses encryption beyond Apple's operating system HTTPS APIs:

| Component | Implementation and purpose |
| --- | --- |
| Signer vault | Dart `cryptography`: AES-256-GCM with PBKDF2-HMAC-SHA256 to protect the stored signer secret; see `app/lib/src/core/signer_vault.dart`. |
| Native FIPS mesh | Bundled Rust FIPS: Noise IK/XK with secp256k1 ECDH, ChaCha20-Poly1305 and SHA-256/HKDF to protect link/session traffic. The source revision is pinned by `tools/ios/prepare_core.py`; inspect its generated `src/noise` implementation. |
| Nostr authentication | secp256k1 signatures for identity and exact request authentication; see `app/lib/src/core/nostr_crypto.dart`. |
| Browser HTTPS | Platform TLS in the WebView, alongside the bundled implementations above. |

FIPS here names the mesh protocol; it is not a FIPS 140 certification claim.
The encryption inventory does not establish an export exemption. Do not answer
that the app uses no encryption or only operating system encryption. Keep
`ITSAppUsesNonExemptEncryption` unset until the applicable classification is
established. Do not invent an `ITSEncryptionExportComplianceCode`.

In App Store Connect, use **TestFlight → build → Manage** beside missing
encryption information, or **App Information → App Encryption Documentation**.
Answer using the implementations above and the actual distribution territory.
If Apple requires documentation, complete that process and use Apple's approved
code. A protocol that combines standard algorithms needs assessment against
Apple's questions; its name alone does not establish the answer.

## Upload and tester acceptance

Use the authorized Xcode account in Organizer: validate the archive, then
distribute as **TestFlight Internal Only**. CLI upload can use the existing
export plist copied to a private location with `destination=upload`, preserving
`testFlightInternalTestingOnly=true`. Local export and upload are distinct steps.

After upload:

1. Record Apple's receipt/build ID and verify processing completes.
2. Resolve any encryption/compliance state using the inventory above.
3. Add only the intended existing internal group; verify its build assignment
   and eligible tester membership independently by reading them back.
4. Verify the tester can see/install the exact version/build in TestFlight.
   An upload receipt or successful local install does not establish this.

Keep run logs, operational notes, screenshots and device records only in ignored
`tmp/docs/handoffs/`. Keep the task in progress until the supervising reviewer
accepts the release evidence.

## Official references

- [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios)
- [Apple beta distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Apple internal tester groups](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [Apple encryption documentation workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/)
