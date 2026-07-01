# Wingman App Flutter Shell

This is the first Flutter shell shape for Wingman App.

It is intentionally thin:

- Setup captures Tower URL, workspace/channel IDs, and a development device key.
- Status calls a bridge abstraction for `wmapp-core`.
- Drive shows the expected workspace/scope/channel/file surface.
- Browser reserves the future WApp/WebView signer area.

The current development host does not have Flutter installed, so this app has
not been compiled in this commit. After installing Flutter, generate platform
folders once if they are not present, then run the app:

```bash
cd app
flutter create --platforms=macos,linux .
flutter pub get
flutter test
flutter run -d macos
```

The bridge currently returns fixture data. The next implementation slice should
connect `NativeCoreBridge` to the Rust core through FFI, platform channels, or a
local control process.
