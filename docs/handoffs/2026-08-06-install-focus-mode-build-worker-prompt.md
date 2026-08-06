Install the current WM-App Focus Mode update on Pete's physically connected iPhone.

Read `docs/handoffs/2026-08-06-install-focus-mode-build-on-petes-iphone.md` completely and follow its linked iPhone deployment instructions. Use the current `main` commit containing `fddb540`. Build a signed release artifact, install it on Pete's connected physical iPhone, launch `com.wingmanbefree.wingmanApp`, and verify launch/process success. Do not target a simulator, leave a debugger running, modify source to force installation, expose signing secrets, deploy Flight Deck, restart services, or clear shared Xcode/provisioning state.

If the device is locked/untrusted or signing is blocked, provide the exact safe user action required. Return concise evidence through the supervised callback. Flight Deck task `623233a8-3849-4284-8b67-35fb3ac79a20` is related, and originating message is `1612137d-b849-4c7c-9231-747bc35eff94`.
