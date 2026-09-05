# Wingman App Flutter Shell

This is the first Flutter shell shape for Wingman App.

It is intentionally thin:

- Setup manages browser approvals and optional Tower configuration. Identity fields come from the encrypted signer vault.
- Status calls a bridge abstraction for `wmapp-core` where the local process is available.
- Drive shows the expected workspace/scope/channel/file surface.
- Browser provides the embedded WApp/WebView signer area.
- Encrypted signer onboarding, NIP-07 `signEvent`, and NIP-98 signing are implemented in Dart for desktop and mobile.

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

Signer keys are not loaded from shell environment variables. First launch opens
the browser without requiring Tower configuration. Use the avatar menu's
**Create identity / Import key** action to generate a key securely in Dart or
import your existing nsec. Choose a PIN; the existing vault encrypts the key with
the PIN plus a per-install secure-storage secret. The clear nsec stays in memory
after unlock. An existing vault offers **Unlock identity** and cannot be replaced
without an explicit destructive reset. Keep the vault and PIN safe: this flow
does not provide a key backup/export step.

New identities continue to profile setup. The avatar's **Edit profile** supports
name, display name, avatar URL, NIP-05 address, website, and about. **Save** keeps
a local draft. **Sign and publish** explicitly authorizes a public Nostr kind-0
event on the existing profile relays (Damus and Primal). The UI reports which
relays accepted that exact event; failed or missing acknowledgements retain the
draft and offer **Retry publication**. Publication does not verify NIP-05 or
register a Tower account/device. Local edits, including legacy saved profiles,
remain authoritative on this device; automatic relay refresh never replaces
them, even after restarting or switching identities.

If Tower URL, workspace service npub, and device identity are configured, Setup
also exposes **Register device** through the existing desktop native-core path.
Mobile still reports this process-backed operation as unavailable. Public Nostr
profile publication works without Tower and does not require the native core.
