# Wingman App Flutter Shell

This is the first Flutter shell shape for Wingman App.

It is intentionally thin:

- Setup captures Tower URL, workspace/channel IDs, and a development device key.
- Status calls a bridge abstraction for `wmapp-core`.
- Drive shows the expected workspace/scope/channel/file surface.
- Browser reserves the future WApp/WebView signer area.

Flutter platform folders have been generated for macOS, Linux, and web. To run
the current shell locally:

```bash
cd app
flutter pub get
flutter test
flutter build web
flutter build macos --debug
flutter run -d macos
```

The bridge currently returns fixture data. The next implementation slice should
connect `NativeCoreBridge` to the Rust core through FFI, platform channels, or a
local control process.
