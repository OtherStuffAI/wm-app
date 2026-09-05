# Flight Deck refresh and iPhone Release — 2026-09-05

Status: implementation and device install/launch succeeded; awaiting manager acceptance and manual visual confirmation. Leave tracking task `a4b8b5ab-9aab-4ffd-a225-26c0da1696c4` in_progress. No separate Pete thread post.

## Source and bundle evidence

- WMAPP implementation commit: `6f91308bb448341805c0e87b0f6e1d126de666ce` on main, starting from `f004cbe` matching fetched origin/main.
- Flight Deck committed HEAD: `c7e6064d8d79cac022f37ab88d667d7ff77401fe`; tracked source was clean at intake and after verification. Existing untracked Flight Deck operational handoffs were preserved and excluded from this package.
- Packaged build: **1874**, build ID `20260905-0420-3-1874`, builtAt `2026-09-05T04:20:09.532Z`.
- Established flow: `./tools/update_flightdeck_bundle.sh --use-existing-dist`. All 21 files match sibling Flight Deck dist byte-for-byte and file-for-file.
- Independently rebuilt a git archive of c7e6064 in `/tmp/wmapp-refresh-20260905/source`, with the existing public app identity and deterministic build number/ID/epoch. All 18 generated files other than version.json match existing dist exactly; version.json differs only in subsecond build timestamp. Existing dist additionally retains two prior hashed assets. The active Flight Deck checkout was not rebuilt or edited.
- Initial isolated build stopped because the public app npub was absent; supplying that existing public build configuration resolved it. No raw signing keys were searched or exported.
- Entry asset: `assets/index-C8q1lKlc.js`, SHA-256 `f9fb9cc9c2284b00d023b341ea11f524421b1fd6777b34b5c94f4ea440e14eb9`.
- CSS: `assets/index-DaVAVcKw.css`, SHA-256 `666d74eef620b9a149e3fe6675bb1d6b4a8b58d2ae2793a2986caabdcc96c5c3`.
- Sorted relative-file SHA-256 manifest: `/tmp/wmapp-refresh-20260905/bundle.sha256`; manifest SHA-256 `fb594e51fd66802f97f6ab308d903cb099d4dda4f5b1f7c6869139c77a06dafa`.
- HTML build meta, service worker build ID, version metadata and current entry asset agree. No source/display inconsistency found in packaged files; live on-phone display remains unobserved.

## Validation and signed artifact

- Flight Deck `bun run verify:dist`: passed.
- `./tools/test_update_flightdeck_bundle.sh`: passed.
- `flutter test`: **104 passed**.
- `flutter analyze`: no issues.
- `git diff --check` and staged diff check: passed.
- `./build_ios_release.sh`: passed; Xcode build 14.3 seconds, Flutter reports 28.3 MB device app. Existing dependency-update notices were informational.
- Artifact: `app/build/ios/Release-iphoneos/Runner.app` (ignored local build output).
- Identifier `com.wingmanbefree.wingmanApp`; version **0.1.5 (6)**, unchanged from the existing install.
- `codesign --verify --deep --strict`: passed; existing Apple Development identity/team `N5DRUM6S94`, unchanged project signing configuration.
- All 21 Flight Deck assets in `Runner.app/Frameworks/App.framework/flutter_assets/assets/flightdeck` match repository assets exactly.
- Runner executable SHA-256: `852779fa6d33cd4cfae91374f69853e68c2537143fadf0609b17a128ce012537`.
- AOT App.framework/App SHA-256: `e63be5591e59e8a82d3e7c891ff552f2b4bef9b06383f39a9107b75df8178816`.

## Physical iPhone evidence

- Peter’s iPhone, iPhone 15 Pro, iOS 26.6.1; physical wired connection, paired, Developer Mode enabled, passcodeRequired false.
- CoreDevice identifier `8A1C111C-F340-5C1A-B609-B022E9B7D832`; UDID `00008130-001824141442001C`.
- `devicectl device install app`: succeeded in place; installed bundle container `C5F9B571-FB48-4402-9E84-EF34DFDC27C4`.
- `devicectl device process launch ... com.wingmanbefree.wingmanApp`: succeeded at 04:40:54 UTC / 12:40:54 Perth, foreground activation requested, startStopped false, no console/debugger attached.
- New installed Runner PID **36364** was present immediately and at 04:41:20 UTC (26 seconds later), with the executable path matching the new install container. A different pre-existing Runner PID was not mistaken for this app.
- No uninstall, reset, wipe, sign-out, preferences/keychain modification, Debug build, or persistent debugger. Existing sign-in was preserved by an in-place install, but its UI state was not independently observed.
- Visual limitation: available devicectl subcommands expose process/display metadata but no screenshot capture; no installed idevicescreenshot/pymobiledevice3 or connected screen-control tool was available. Smallest remaining user check: look at Wingman App on the iPhone and confirm the first screen renders; confirm build 1874 in its Flight Deck version display when accessible.

## Repository and coordination

- Existing GitHub origin `https://github.com/OtherStuffAI/wm-app.git` and Forgejo remote preserved. Normal origin/main push authorized by the request; no force, rebase, reset, or Forgejo push.
- The only pre-existing WMAPP change was the supplied refresh request handoff. It was included with compatible source state; this is the documented private WMAPP repository and no applicable handoff-publication prohibition was found. Flight Deck’s public-source handoff restriction was respected in its own repository.
- Build and device JSON/log evidence is local under `/tmp/wmapp-refresh-20260905/`; operational acceptance evidence is persisted here.
- Broker task-comments read failed: “No pipeline run, document binding, or Agent Direct context found for this session.” CLI fallback also lacked Flight Deck PG Tower URL. Return milestone/final evidence to manager; no raw-key fallback or separate thread post attempted. Manager owns execution contract, task comments and acceptance.
- Session goal set through sessions metadata-update; nextAction reflect while working, stop after evidence handoff.
- Tower and Autopilot services, configuration and code were not edited or restarted. Only this worker’s authorized session metadata was updated.

Final process check: PID 36364 still present at 2026-09-05T04:42:34.422710+00:00, more than one minute after launch. Implementation commit 6f91308bb448341805c0e87b0f6e1d126de666ce was pushed normally to origin/main and confirmed by git ls-remote. This evidence-only follow-up commit is also pushed; see the final manager callback for its SHA.
