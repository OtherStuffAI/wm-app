# Avatar photo-library implementation and device release evidence

## Implementation

`ProfileAvatarUpload.pick()` uses `image_picker` 1.2.3 (iOS implementation
0.8.13+7) with `ImageSource.gallery` on iOS/iPadOS. Other platforms retain the
existing `file_selector` picker and JPEG/PNG/WebP filters. The native picker
requests a 512 × 512 bounding box and JPEG quality 90, with
`requestFullMetadata: false`. The iOS photo-library usage description explains
avatar selection; camera/microphone access is not used.

Reviewed official documentation on 2026-09-06:
- https://pub.dev/packages/image_picker
- https://pub.dev/packages/image_picker_ios

Reviewed the resolved plugin's `FLTPHPickerSaveImageToPathOperation`,
`FLTImagePickerPhotoAssetUtil`, and `FLTImagePickerMetaDataUtil`: PHPicker loads
image data (including HEIC), scales via UIImage, and converts unsupported source
encodings to JPEG. The resulting file then passes through existing Dart byte,
format, dimension, and PNG upload-size checks. Limits apply to the native
converted image, allowing large original iPhone photos to become bounded avatars.
Dart PNG re-encoding discards original metadata before upload. Cancellation returns
null; access, platform, read, and decode failures become user-facing errors.
Signer identity checks, Blossom authorization, receipt validation, and the prior
locked-signer repair (`4e278d9`) remain intact.

## Automated validation

- `flutter test`: all 151 tests passed, including 16 new picker tests and the
  saved-vault/restored-tabs regression coverage.
- Targeted picker/upload run: all 21 tests passed.
- `flutter analyze`: no issues found.
- `plutil -lint app/ios/Runner/Info.plist`: OK.
- `git diff --check`: passed.
- Tests use generated image bytes, mocked pickers/transports, and synthetic signer
  identities. No private device photos or keys were accessed and no uploads made.
- HEIC native conversion was verified by resolved plugin source inspection;
  physical-device HEIC selection is still a manual check, not an automated claim.

## Flight Deck

Source: `/Users/mini/code/wm/flightdeck`, main at
`1f6e076ac68eb2670b726d3784ef2585f0eead68`. Tracked source state was clean;
pre-existing untracked handoffs were preserved. `.build-meta.json` reports 1884.
Dist reports build **1884**, ID **20260906-0507-1-1884**, built at
**2026-09-06T05:07:08.193Z**.

`node scripts/verify-dist-assets.mjs` verified both entry asset references.
`./tools/update_flightdeck_bundle.sh --use-existing-dist` copied this verified
build without rebuilding or changing the source checkout. All **19 files** in
`app/assets/flightdeck` matched source dist by relative path and SHA-256.
`version.json` SHA-256:
`476e3704a167aa654561099d9213d04c89da2b6c30516c7df70fc2037dea6a3e`.
Generated bundle changes are included according to existing ignore policy.

## Device validation

Both existing installations were confirmed as `com.wingmanbefree.wingmanApp`,
version 0.1.6, build 7, before the upgrade. `./build_ios_release.sh` completed successfully (Xcode build: 25.3 seconds;
Flutter artifact: 28.5 MB). Installed artifact:
`app/build/ios/Release-iphoneos/Runner.app`.
`codesign --verify --deep --strict` passed. Signing team remains `N5DRUM6S94`,
Apple Development identity `76V7H4Y22U`, signed 2026-09-06 15:13:33 +0800.
Release version is still 0.1.6+7; this is an in-place local device release, not a
new TestFlight version. Runner SHA-256:
`8cebaa8db1286bbe1df72ecce210df6401d97e4a55fd6ad252c03bd101c6b9f7`.
All 19 Flight Deck files inside the signed App.framework matched the source
bundle by SHA-256, and the built plist contains the photo-library description.

Both installs used `devicectl device install app`, followed by
`devicectl device process launch` with no debugger, console attachment,
start-stopped option, or terminate-existing option. No uninstall, data clearing,
private storage inspection, TestFlight upload, external post, service deployment,
or Autopilot restart occurred.

| Device | CoreDevice identifier | Launch (+0800) | PID | New installed bundle container |
| --- | --- | --- | --- | --- |
| Peter’s iPhone, iPhone 15 Pro | `8A1C111C-F340-5C1A-B609-B022E9B7D832` | 15:14:26 | 51666 | `F90871CA-D02E-4075-9E5C-A6D8CCD6CCF8` |
| iPad (168), 9th generation | `7E708832-4F84-5B48-996B-67160DBED6E6` | 15:14:36 | 1652 | `2BD7302D-3A88-4E8D-BCFA-2B2BB4A6EC1C` |

Initial process queries confirmed each PID executing `Runner.app/Runner` from
its newly installed bundle container. The changed bundle containers distinguish
the new release from the prior same-version installations. In-place upgrades
preserve the app data/Keychain through the supported OS install path; private
contents were not read to independently compare them.

Local machine-readable evidence is under `/tmp/wmapp-{iphone,ipad}-` with
`before.json`, `install.json`, `launch.json`, `process-first.json`, and
`process-final.json` suffixes. Build/test logs are
`/tmp/wmapp-avatar-release-build.log`, `/tmp/wmapp-avatar-flutter-tests.log`,
`/tmp/wmapp-avatar-targeted.log`, and `/tmp/wmapp-avatar-analysis.log`.

Final process queries at **2026-09-06 15:15:42 +0800** confirmed the original
launch PIDs and executable paths on both devices: iPhone **51666** after **76
seconds**, iPad **1652** after **66 seconds**, without a debugger.

Native implementation/bundle commit: **44ff507** on `main`, descended from
signer repair `4e278d9`. The subsequent evidence-only commit records this final
persistence check; it does not change the installed build. Manager can use the
source/version/hash and device identifiers above for independent verification.

## Remaining manual visual check

Pete/manager should confirm the first Flutter screen renders on each device and,
after unlocking the saved signer normally, confirm avatar selection presents the
Photos sheet on iPhone and iPad and Cancel preserves the avatar. Do not select a
private photo for testing: selection enters the existing upload flow. Physical
HEIC selection should use a synthetic fixture only in an explicitly authorized
upload test. No private-library browsing or screenshot capture was performed.
