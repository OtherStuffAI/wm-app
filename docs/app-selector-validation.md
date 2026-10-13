# Saved-app selector

The native browser new-tab page shows saved apps as icon tiles. Use the cog to
enter edit mode: editable apps expose an Edit pill and a small corner ×. Flight
Deck remains a built-in launch tile and cannot be edited or deleted. The native
editor changes the app name and **actual launch URL**. Save validates the complete
HTTP(S) URL and rejects conflicts with another app or built-in Flight Deck.
Cancel discards changes. Query strings and fragments are preserved unless the
user deliberately edits them; route paths and trailing slashes remain distinct.

Custom thumbnails use a native image chooser, are decoded and normalized into
bounded PNG data, and persist with each identity's existing v1 bookmark records.
They take precedence over automatic icons. Use automatic icon removes the custom
image when saved. Existing title/URL records need no migration. Background
selection is also identity scoped; Default background restores the bundled voxel
beach sunset. Image input is limited to 5 MB/40 megapixels and PNG output to 2 MB;
thumbnail dimensions are at most 512 pixels and background dimensions at most
1920 pixels. Images are stored locally without uploading or signing.

Automatic icons start with the origin's `/favicon.ico`. Saving or visiting a saved
app reads its favicon/apple-touch-icon links and bounded same-origin manifest in
that visited document's ordinary web context. A manifest icon takes precedence
when available. Cross-origin manifest/icon discovery, redirects, credentials and
FIPS metadata fetching are excluded. Legacy entries can obtain manifest metadata
on their next visit. Invalid or unavailable metadata leaves the icon/initial
fallback. These decorative values never change a launch URL, service identity,
consent decision or signature. The selector has a restrictive CSP, no-referrer
images and no network connection capability beyond decorative image loads.

## Focused checks

Run from `app/`:

```sh
flutter test test/browser_bookmark_store_test.dart test/bookmark_editor_test.dart \
  test/browser_app_selector_test.dart test/widget_test.dart \
  test/profile_avatar_picker_test.dart test/grasp_browser_consent_test.dart \
  test/native_signer_lock_test.dart
flutter analyze
flutter build macos --debug
flutter build ios --debug --no-codesign
flutter build apk --debug
```

Build availability depends on the local Flutter, Xcode, Android SDK/JDK and native
FIPS libraries. A build does not install or update a running app.

## Rendered browser checks

Generate fixtures only in a verified ignored directory. From the repository root:

```sh
git check-ignore tmp/docs/handoffs/app-selector-validation/selector.html
cd app
APP_SELECTOR_EVIDENCE_DIRECTORY="$(pwd)/../tmp/docs/handoffs/app-selector-validation" \
  flutter test test/browser_app_selector_test.dart
cd ..
node app/test/browser_app_selector_browser_test.mjs \
  tmp/docs/handoffs/app-selector-validation
```

The Node check uses Playwright. If it is installed outside the current repo, set
`PLAYWRIGHT_MODULE` to its absolute module entry; optionally set
`CHROMIUM_EXECUTABLE` to a supported local Chromium/Chrome binary. It blocks real
network traffic, validates exact launch URLs and controls, checks layouts at
320/390/768/1440 pixels and writes screenshots to the supplied ignored directory.
It exercises favicon/manifest resolution, malformed/oversized manifests,
credential omission, custom-image precedence and service/cross-origin rejection.
Browser renders complement the fake-WebView native wiring tests. Native device
photo chooser and WebView appearance still require manual review in a separately
installed build.

## Manual review

- Open several apps and confirm tile taps reuse the active tab and preserve the
  full destination URL. Verify built-in Flight Deck and ordinary tab navigation.
- Enter edit mode using the cog. Edit a long URL into a deliberately shorter
  route, save, restart the app and reopen it. Verify query/fragment preservation
  for an untouched URL and reject duplicates without dropping either app.
- Choose a custom thumbnail, cancel to discard, then choose again and save.
  Restart and verify persistence. Restore the automatic icon and test a missing
  favicon/manifest. Verify unreadable and oversized images report an error.
- Select/reset a background and switch identities. Each identity must restore its
  own saved apps, thumbnails and custom background. Change identity or lock while
  editing; a stale editor must not save into another identity.
- Check keyboard focus, readable names, corner-delete touch targets, narrow
  portrait/tall scrolling and wide desktop layouts.

The bundled `app/assets/app-selector/voxel-beach.png` was generated using the
built-in imagegen tool from a user-supplied beach sunset reference. Prompt:
transform the reference into a polished voxel beach sunset; preserve the low
horizon, broad blue-gray-to-orange sky, ocean waves, sand, sparse volleyball poles,
small distant people, foreground path and grass; wide landscape, quiet warm mood,
no text, logos, UI, watermark or borders.
