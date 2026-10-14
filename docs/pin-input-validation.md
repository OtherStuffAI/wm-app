# Immediate PIN masking

The unlock, create/import PIN, confirmation PIN and private-key export PIN use
`ImmediatePinField`. Its `EditableTextState.buildTextSpan` override always renders
one obscuring character per UTF-16 code unit while `obscureText` is enabled.
Flutter documents this method as an appearance extension point. The default
implementation can briefly replace a mask with the newest digit when the platform
requests password reveal on Android, iOS or Fuchsia. The PIN renderer bypasses
that replacement without modifying the controller, input connection, secure-input
semantics, selection, formatters or PIN/vault/signing code. It does not change the
application's platform or global password/accessibility settings.

The onboarding Show PIN toggle intentionally reveals both PIN fields. Hide PIN
masks them immediately. The nsec and registration-key fields remain separate
non-PIN inputs with their existing behavior.

From `app/`, run:

```sh
flutter test test/immediate_pin_field_test.dart
flutter analyze
flutter test
flutter build macos --debug
```

The regression enables the platform brief-reveal preference on Android and iOS.
It inspects `RenderEditable.text` on the first input frame and eight subsequent
250 ms frames for incremental typing, backspace, replacement and paste. It checks
controller values/selections, secure text-input configuration, clipboard paste,
export digit/length filters, the explicit visibility toggle and submission. A
standard obscured TextField control must reveal its newest digit, proving the
leaking platform behavior is active in the test. Existing onboarding, encrypted
vault and export tests verify the surrounding flows.

For manual validation on a test device, enable the OS password-character reveal
preference, type a disposable PIN slowly and quickly on each surface, delete and
paste digits, and verify only masks appear unless Show PIN is explicitly selected.
Confirm focus, numeric keyboard, selection, submit and accessibility labels still
work. Render tests simulate platform preferences; they do not validate a physical
keyboard/IME, OS keyboard previews or third-party keyboard behavior. Building the
macOS app does not install or replace a running application.
