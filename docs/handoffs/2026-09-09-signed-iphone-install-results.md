# Signed iPhone install after restored Xcode login — 2026-09-09

Signed Release build, in-place install and standalone process launch succeeded.
This supersedes the earlier No Accounts / missing Network Extensions profiles
blocker. Rendered UI and physical FIPS traffic are not verified.

Origin: @[Signing retry](mention:message:fe0f49e5-3dd9-4f70-b500-070b771ae8ed).
Task `05cfb9b1-b6d8-42a7-a801-b197a00a78da` remains `in_progress`; manager owns
acceptance and the originating chat reply. Full current task/comments/thread read.
No AGENTS.md exists in this checkout or its parent directories.

## Build and preserved package

Built source `98e60f70e51aae7ff28c525f56d9baa876604573` on `main`.
Ran `flutter build ios --release` directly from `app`: exit 0, Xcode 44.4 seconds,
40.3 MB at `app/build/ios/iphoneos/Runner.app`, version **0.1.6 (7)**, arm64.
The wrapper and bundle/core preparation were not rerun. No source changes were
needed. Existing behavioral test evidence remains in the prior handoff.

Flight Deck **1915**, ID **wmapp-0f7dccb2ef30-1915**, from exact source
`0f7dccb2ef3042bd026fb1e5061b22e594faed96`, builtAt
`2026-09-09T06:53:53.000Z`. All **19** packaged asset paths and SHA-256 values
match `build/iphone-refresh/package-evidence.json` exactly, with no extra files.
Version metadata fields match; prior evidence stores a summary while the actual
version.json also contains release history. An initial verifier compared the
whole version object to that summary and was corrected to compare the recorded
fields; full file hashes already matched.

- version.json SHA-256: `bb2f0ae978a05561f7aaa778ef241d81cde830b7fdd55ab00f169ceb775004db`
- Canonical sorted complete asset manifest SHA-256: `0aa66d6c8c3b45f57358e3abc2507e6c55b6d1885d1608116f9044625ff3b481`
- Signed Runner executable SHA-256: `8fc4a6df52af03ad987724f80d84b075f3e83a5707a9432ca52f0ccf1d1f1a50`
- Signed extension executable SHA-256: `8b3f92bde2a4458f6777b36002f57f921ff49af7b85d392f532632440ab1eb12`

## Signatures and provisioning

`codesign --verify --deep --strict --verbose=2` exits **0** independently for
Runner.app and `PlugIns/FipsPacketTunnel.appex`: valid on disk and satisfies its
Designated Requirement. Both have Apple Development signatures, team
**N5DRUM6S94**, and signed
`com.apple.developer.networking.networkextension = [packet-tunnel-provider]`.
Exact application identifiers match the team plus existing bundle IDs below.

| Target | Profile UUID | Profile expiry (UTC) |
| --- | --- | --- |
| `com.wingmanbefree.wingmanApp` | `65603417-1e61-48b6-ac35-91cd8f6d96b9` | 2027-09-09 07:53:34 |
| `com.wingmanbefree.wingmanApp.FipsPacketTunnel` | `27d85918-f57d-48eb-b66c-de22309717b7` | 2027-09-09 07:53:36 |

Both embedded profiles permit packet-tunnel-provider, match the exact App ID/team,
and contain phone UDID `00008130-001824141442001C`. Automatic provisioning
succeeded with the restored account; no explicit xcodebuild fallback needed.
These are development profiles (`get-task-allow = true`), with Release app code.
No debugger was attached. No private keys/profile credential export was performed;
only existing embedded public provisioning metadata was decoded in memory.

## Install and launch

Exact phone: **Peter’s iPhone**, iPhone 15 Pro (iPhone16,1), iOS **26.6.1 (23G83)**,
devicectl **8A1C111C-F340-5C1A-B609-B022E9B7D832**. Paired, wired, connected,
Developer Mode enabled, booted. Lock-state check: `passcodeRequired=false`,
`unlockedSinceBoot=true`. No unlock/trust blocker was returned.

```sh
xcrun devicectl device install app \
  --device 8A1C111C-F340-5C1A-B609-B022E9B7D832 \
  app/build/ios/iphoneos/Runner.app
xcrun devicectl device process launch \
  --device 8A1C111C-F340-5C1A-B609-B022E9B7D832 \
  com.wingmanbefree.wingmanApp
xcrun devicectl device info processes \
  --device 8A1C111C-F340-5C1A-B609-B022E9B7D832
```

Install exits **0**, bundle ID correct, database sequence **2120**, installed at
`/private/var/containers/Bundle/Application/BF26458F-919A-4078-A563-E9A22791E91C/Runner.app/`.
Launch exits **0**, PID **90817**, activated normally with `startStopped=false`,
no console/debugger. Same PID and exact installed executable present immediately
and **32.22 seconds later**, at **07:56:57 UTC** (launch **07:56:25 UTC**, timestamps
from evidence file mtimes). Phone remains connected at final enumeration.

## Remaining physical checks and handoff

No callable phone screenshot/UI tool is available in this session; devicectl
exposes process/display information but no screen-capture command, and neither
idevicescreenshot nor pymobiledevice3 is installed. A reported device screen-view
capability alone is not a rendered UI observation.

Pete's next check: look at WMAPP on the phone and confirm its first screen and
embedded Flight Deck render and respond. Then open Setup → FIPS transport,
enable it and accept Apple's VPN consent normally. Verify authenticated bootstrap,
exact `.fips` WApp load and Nostr login with expected origin approval. No VPN
consent, tunnel connectivity or WApp/login success is claimed here. Complete
[the physical checklist](../deploy/ios-fips.md): ordinary HTTPS/DNS, refusal/retry,
stop/restart/repair, lock/background/reboot identity, Wi-Fi/cellular/offline recovery,
other VPN interaction, diagnostics and memory/battery.

Raw logs and machine-readable verification are in ignored `build/iphone-signing-retry/`:
`flutter-release.log`, `signed-package-evidence.json`, `device-start.json`,
`lock-state.json`, `install.{json,log}`, `launch.{json,log}`,
`processes-{start,final}.{json,log}`, `process-evidence.json`, `devices-final.json`.
No tests repeated for documentation-only changes; final whitespace/diff reviewed.
Dispatch brief is committed with this report. Reviewer-owned
`docs/fips-tower-bridge-handoff-2026-09-09.md` and `tools/fips_bridge/` remain untouched.
No uninstall/data clearing, substitute device/team, entitlement removal,
publication, desktop disruption, Autopilot restart or history rewriting occurred.
Worker stops at this handoff; manager reviews callback and posts chat.
