# WMapp channel sync repair — supervisor handoff

Tracking task 0c243046-68bc-4c43-af97-1cde780cc9c6 remains in_progress for supervisor acceptance. No direct originating-thread post.

## Diagnosis and repair

Reproduced FD1874 before changing configuration using the existing local diagnostic capture and production worker in Playwright WebKit 18.4. First page (81 changes, including 31 channels) failed with `No workspace database open — call openWorkspaceDb(workspaceDbKey) first`. The production dynamic delta chunk imports its worker entry, which WebKit evaluates again, creating a second unopened database singleton and duplicate listeners. The synthetic production-worker test independently failed identically; /tmp/wmapp-regression-before.log records this failure.

Flight Deck main repair 4212ac7: vite.config.js keeps ES workers but sets worker.rollupOptions.output.inlineDynamicImports=true. No shared architecture, Tower protocol, wrapper bridge, identity, database migration or cursor changes. scripts/verify-incremental-worker-browser.mjs now supports WebKit and a selectable packaged asset root; tests first application, cached worker restart, replay, cursor/fallback guards, explicit reset, one reply per request, persisted channel reads into a minimal DOM harness, and startup of the other sync worker. Release metadata/notes advance to 1875. Commit pushed normally to GitHub origin/main (including four existing ancestor commits).

No live phone reproduction was available. Prior local diagnosis is docs/handoffs/2026-09-05-live-sync-regression-diagnosis.md in active Flight Deck. This worker independently reproduced its reported failure and post-fix offline replay. Tower repositories were identified but neither edited nor restarted. No services restarted.

## Validation and package

- Flight Deck: bun run test --maxWorkers=4: 250 files, 3421 tests pass. Includes existing old-schema cache/pending-command preservation and protocol rollback/restoration coverage.
- bun run build: pass, build 1875 / 20260905-0623-4-1875 / builtAt 2026-09-05T06:23:13.529Z.
- bun run verify:dist, git diff --check: pass.
- Public-source check: existing 107 findings remain; before/staged/final reports byte-identical. No bypass or checker change. Existing private operational handoffs in the public Flight Deck repo are preserved locally and excluded from public commits; no captured private workspace pages committed.
- Production worker regression: WebKit 18.4 and Chrome 152.0.7977.76 pass. Seven materialization replies for seven requests; channel persisted and visible to main-thread IndexedDB. Minimal DOM harness is NOT the real Alpine channel screen.
- All 54 locally captured live pages replay successfully in WebKit (8471 changes), versus failure on page zero before repair. Local log /tmp/wmapp-live-replay-after.log. Captures contain private workspace data and stay outside repositories.
- WMapp updater --use-existing-dist and source-resolution test: pass.
- Flutter test: 104 pass; flutter analyze: no issues.
- ./build_ios_release.sh: signed Release passes; Xcode 15.9 seconds, reported app 28.3 MB. Existing signing configuration retained.
- codesign --verify --deep --strict: pass.
- Artifact app/build/ios/Release-iphoneos/Runner.app. Its Frameworks/App.framework/flutter_assets/assets/flightdeck, tracked app/assets/flightdeck, and active Flight Deck dist match file-for-file and byte-for-byte (20 files).
- Active materializer tower-pg-materialization-worker-zCHi6Bhq.js SHA256 3847bdbcfc24b5ac91188430d7aed6b1a686a3bf279c8108e3f25bac4b59a682. Current entry points to this repaired worker. Build output retains some prior hashed assets per existing build policy.
- Same WebKit regression passes against both tracked WMapp assets and assets read directly from signed Runner.app.

## Device and acceptance limits

Peter’s iPhone 15 Pro, CoreDevice 8A1C111C-F340-5C1A-B609-B022E9B7D832, is unavailable on repeated devicectl list devices checks. No install or launch attempted while unavailable. No wipe, uninstall, sign-out, key access or pending-data deletion. Connect/unlock the paired phone, then install the prepared Release in place using docs/deploy/iphone.md and verify the real channel screen through normal authenticated startup.

No physical screenshot/console or Pete-authenticated end-to-end navigation captured. The fix is a reproduced shipped-artifact WebKit compatibility bug, not proof that every reported phone symptom is resolved. Native bridge/authentication and actual Alpine startup remain physical acceptance checks; no speculative changes made there.

## Coordination

All three requested task-comment reads and the progress-comment write failed: No pipeline run, document binding, or Agent Direct context found for this session. Flightdeck_context returned no workspace binding. No raw signing fallback. Supervisor must copy evidence into task comments and reread latest task history before acceptance. Manager owns final originating-thread report and state transition; task deliberately remains in_progress.

Worker session b8abb72f-c024-435d-99be-0eb4d944b081 goal set and nextAction reflect during implementation. Final response is the supervised callback payload. WMapp includes its pre-existing request handoff and this evidence file with generated bundle in its private repository. Final callback provides WMapp commit/push state.
