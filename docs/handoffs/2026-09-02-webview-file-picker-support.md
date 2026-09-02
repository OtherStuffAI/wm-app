# WMAPP WebView file-picker support

## Objective

Make standard HTML file inputs work inside WMAPP's embedded browser, beginning with the confirmed macOS failure and adding the corresponding Android integration without replacing the existing browser stack.

Pete's confirmed reproduction is Forgejo profile settings on macOS: clicking **Choose File** for a custom avatar inside WMAPP does nothing, while the same page opens the system file chooser in Firefox. The screenshot is attached to the originating Flight Deck message as storage object `f502c69e-4b0e-44b9-bad9-8c9267de31c9`.

## Repository and ownership

- Repository/workdir: `/Users/mini/code/wm/wmapp`
- Branch: `main`
- Primary surface: `app/lib/src/features/browser/browser_screen.dart` and the platform WebView integration it creates.
- This is a WMAPP shell change. Do not change Forgejo, Flight Deck, Tower, Autopilot, or unrelated repositories unless investigation proves a shared contract defect; stop and report that boundary before crossing it.

## Current evidence

- WMAPP uses `webview_flutter` with `webview_flutter_wkwebview` on macOS and the Android implementation transitively.
- `BrowserScreen._createWebViewController` configures JavaScript channels and a navigation delegate but no file-selection callback.
- The installed Android controller exposes `AndroidWebViewController.setOnShowFileSelector`.
- The installed WebKit plugin's `WKUIDelegateImpl` handles new WebViews, media permissions, and JavaScript dialogs, but does not implement macOS `webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:)`. This matches the silent macOS failure.
- WMAPP separately injects `_tabCaptureScript()` to route `window.open` and non-`_self` links into WMAPP tabs. Preserve that behavior; file input is not a popup/new-window request.

## Required work

1. Reproduce or prove the current macOS failure with a minimal local HTML page containing single-file, multiple-file, and filtered image inputs.
2. Add a maintainable macOS integration that opens `NSOpenPanel`, honours single versus multiple selection, applies accepted file types where the WebKit parameters expose them, returns selected file URLs to WebKit, and completes cancellation cleanly.
3. Do not patch the global Pub cache. If the upstream plugin lacks the required hook, use a repository-owned local package/fork or a narrowly scoped WMAPP macOS plugin/bridge with explicit rationale and upgrade notes.
4. Add Android file selection using the supported Android WebView callback and a native/system document picker. Return content URIs accepted by WebView, respect selection mode and MIME accept types, and treat cancellation as an empty selection. Avoid broad storage permissions when the system picker suffices.
5. Preserve normal navigation, existing WMAPP tabs, `window.open` capture, signer injection, FIPS handling, focus mode, browser state, and WebView identity/lifecycle.
6. Add focused automated coverage for configuration/callback routing and any pure selection-policy helpers. Where native picker UI cannot be automated reliably, add a deterministic manual fixture/checklist and record the limit precisely.
7. Document any platform caveat for iOS. Do not claim iOS validation without evidence.

## Acceptance criteria

- On macOS, clicking Forgejo's custom-avatar **Choose File** opens the native chooser; selecting a valid image attaches it to the HTML input and Forgejo can submit it.
- macOS cancellation leaves the page usable and does not navigate, reload, or hang the WebView.
- macOS single/multiple selection and image accept filtering behave consistently with the HTML input request as far as WebKit exposes those constraints.
- On Android, a standard `<input type="file">` opens the system picker and selected content is returned to the page without requesting broad filesystem access.
- Existing target-blank/window-open routing still opens WMAPP tabs and is not conflated with file selection.
- No global Pub-cache edits, unrelated repo changes, service restarts, deployment, or push.

## Validation and handoff

- Run formatter, focused Flutter tests, the full relevant Flutter test suite, `flutter analyze`, and macOS/Android build validation proportionate to available SDKs/devices.
- Perform the Forgejo macOS avatar flow manually if the app can be launched without disrupting a managed process. Do not restart any managed Wingman service.
- Inspect the complete shared worktree, preserve concurrent changes, and commit all compatible nonignored tested state on `main` using a Conventional Commit. The existing branch is already ahead of `origin/main`; do not reset, rebase, force-push, or discard it.
- Report diagnosis, design choice, changed files, exact validation output, manual evidence or limitation, commit, and any remaining platform/device validation needed on the Flight Deck task. Rick will review and report in the originating Agent Direct thread.
