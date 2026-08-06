# Install the Focus Mode update on Pete's connected iPhone

Pete explicitly asked to update the WM-App build on his iPhone after commit `fddb54083f39de2fe7a2b818860caa610de3a9fe` (`Move Focus Mode restore into mobile drawer`).

Origin: @[Pete's request](mention:message:1612137d-b849-4c7c-9231-747bc35eff94) in Flight Deck thread `43b88820-7a5b-4aaa-bdcc-e3ec1fc6e13e`. Related implementation task: `623233a8-3849-4284-8b67-35fb3ac79a20`.

Follow `docs/deploy/iphone.md` and `docs/handoffs/2026-08-06-connected-iphone-flutter-build.md`.

## Required execution

- Work in `/Users/mini/code/wingmanbefree/wm-app` on current `main`; verify HEAD is `fddb54083f39de2fe7a2b818860caa610de3a9fe` or a later commit containing it.
- Preserve the worktree and do not modify source merely to force installation.
- Enumerate Flutter/Xcode devices and select Pete's physically connected iPhone, not a simulator.
- Keep secrets, signing certificates, and provisioning details out of logs and reports.
- Run `flutter pub get` and a proportionate pre-install validation if dependencies or state require it. The implementation has already passed 31 tests, analysis, web build, and a no-codesign iOS build.
- Build a signed **release** iPhone artifact using the existing Xcode signing configuration (`./build_ios_release.sh` is the documented path).
- Install `app/build/ios/Release-iphoneos/Runner.app` on the connected physical iPhone with `xcrun devicectl` and launch bundle `com.wingmanbefree.wingmanApp`.
- Verify launch success and that the installed process remains present. Detach cleanly; do not leave a long-running `flutter run` process.
- If blocked by phone lock, trust/pairing, Developer Mode, provisioning, signing, or device availability, stop after safe diagnostics and report the exact action Pete must take. Do not clear shared Xcode caches, delete provisioning data, reset the phone, or alter signing identities.
- Do not deploy Flight Deck/web assets, push branches, restart services, or build the macOS app.

Report device, source commit, release artifact, install result, launch result, and any blocker in the supervised callback. Update the related task if broker-aware Flight Deck task tooling is bound; otherwise Rick will report in the originating thread.
