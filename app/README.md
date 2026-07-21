# Wingman App Flutter Shell

This is the first Flutter shell shape for Wingman App.

It is intentionally thin:

- Setup captures Tower URL, workspace/channel IDs, and a development device key.
- Status calls a bridge abstraction for `wmapp-core` where the local process is available.
- Drive shows the expected workspace/scope/channel/file surface.
- Browser provides the embedded WApp/WebView signer area.
- Local key generation/import, NIP-07 `signEvent`, and NIP-98 signing are implemented in Dart for desktop and mobile.

Flutter platform folders have been generated for macOS, Linux, web, Android,
and iOS. To run the current shell locally:

```bash
flutter pub get
flutter test
flutter build web
flutter build macos --debug
flutter run -d macos
flutter build apk --debug
flutter build ios --debug --no-codesign
```

The root repo also has convenience scripts:

```bash
../build_runapp.sh
../build_android_apk.sh
../build_ios_debug.sh
../build_ios_debug.sh simulator
```

Desktop still uses `wmapp-core` for Drive sync, device registration, channel
validation, local file mounting, and NIP-44 encryption/decryption. Mobile builds
currently report those process-backed operations as unavailable instead of
attempting to shell out to Rust.
