# Daily private TestFlight release

Autopilot's supported scheduler starts one bounded agent session daily at
20:00 `Australia/Perth` (`0 20 * * *`, 12:00 UTC). The enabled trigger stores
the full execution contract, repository paths, identity and reporting route.
No Autopilot restart is needed for scheduler CRUD.

## Current authentication boundary

The existing Organizer account has delivered a private build. That does not
prove unattended CLI account resolution or App Store Connect API access.
The current nightly helper deliberately reports `blocked_auth`: there is no
verified unattended history, audience, upload and readback integration. A
credential-reference file alone cannot make it ready. The scheduled session
must report this boundary and finish without building/uploading speculative
artifacts, requesting passwords, scraping browser sessions or accepting agreements.

For unattended releases, the human operator should provision an App Store
Connect API credential in Apple and place it in an approved secure store.
Provide only its credential reference and key ID/issuer ID to the operator;
never put the private key in source, prompts or chat. The operator must wire
and validate the integration for exact app history, private group membership,
manual distribution, upload and processing readback. Existing Xcode GUI access
remains usable for a human release via [testflight.md](testflight.md).

## Release execution contract

1. Set a session completion goal and `nextAction=reflect`. Read the task and
   complete current thread, latest comments, all repository agent guides and
   the current release-tool implementation before acting.
2. Run `python3 tools/ios/nightly_testflight.py claim`. Save the returned Perth
   day. Duplicate daily claims and any prior active claim fail closed, even
   for the same session. A crash never automatically expires a claim. The
   operator reconciles its session, Apple receipts and run state before any
   explicitly authorized repair. Do not edit the ledger to bypass a gate.
3. Inspect both working trees, staged changes, branch and upstream. Default
   to `main`; stop on another branch, conflicts, incompatible work or moving
   inputs. Preserve unrelated and concurrent files. Never stash, reset,
   rebase, force-push or bypass hooks.
4. Flight Deck comes first. Review all compatible nonignored software and
   reusable documentation, run focused tests and required public-source,
   unit, release-note, build and distribution checks. Follow its release-note
   numbering rules for source changes. Build in an isolated snapshot with
   pinned build number/ID/time so generated metadata cannot dirty shared
   source. Verify the exact tested staged tree remains unchanged, then commit
   a Conventional Commit checkpoint. A clean tree retains its existing commit.
   Push the configured authoritative upstream only as a normal fast-forward
   when safely permitted; divergence/auth failures are blockers, never a reason
   to substitute stale remote source for the newer local commit.
5. Validate WMAPP analysis/tests sequentially and release tooling tests. Review
   and commit all compatible tested nonignored source/docs on `main`, checking
   for concurrent edits before committing. Ignore operational evidence and
   generated bundles. Never stage everything without inspecting the candidates.
6. Check authentication before expensive packaging. While `dry-run` reports
   `blocked_auth`, record the exact prerequisite and both commits, report once,
   finish the claim as blocked and stop. This is a scheduled preparation flow,
   not a completed nightly distribution.
7. Once a verified integration exists, query complete Apple history including
   processing builds and reconcile all local pending receipts before choosing
   a number. Reserve a build greater than every observed Apple/local reserved
   build under the existing global release lock. Never reuse uncertain numbers
   or re-upload a pending delivery. Version must satisfy current Apple history.
8. Create isolated snapshots of the exact committed Flight Deck and WMAPP trees
   under ignored private evidence. Use `git archive` or a private local clone;
   never build the shared working copy. Install frozen Flight Deck dependencies,
   pin `FLIGHTDECK_BUILD_NUMBER`, `FLIGHTDECK_BUILD_ID`, `SOURCE_DATE_EPOCH`,
   build and verify `dist`, then pass that snapshot through `FLIGHT_DECK_DIR`
   to the existing WMAPP release workflow. Record commit, version/build and
   asset hashes. Keep generated output in the snapshot, not shared tracked files.
9. Use `testflight_release.py` barriers and signing checks for Runner and Packet
   Tunnel. Validate the exact exported artifact, archive, profiles, entitlements,
   identifiers, team and matching monotonic build. No upload until every gate
   passes. One upload attempt only; uncertainty requires readback, never retry.
10. App `6809077710`, bundle `com.wingmanbefree.wingmanApp`, existing Pete Private
    internal group, sole Pete and manual distribution remain mandatory. No
    external group, public link, tester invitation or production submission.
    Resolve actual standard encryption beyond OS crypto accurately using the
    documented inventory and authorized territories. Do not invent exemptions
    or change territories. Assign only the exact processed build to the existing
    group and independently read it back. Report `Testing`, `Processing`, action
    required or failure; never call a receipt or IPA a published release.
11. Write one readable result on the originating task and same thread, including
    commits, FD build/assets, Apple build/receipt if any and exact blocker/status.
    Finish with the exact claimed `--day` and `--result blocked_auth|failed|processing|testing`.
    Set `nextAction=stop` only after reporting and handoff. If reporting or upload
    outcome is uncertain, retain the active claim for reconciliation.

Operational prompts, logs, screenshots and receipts belong only in verified
ignored, untracked `tmp/docs/handoffs/`. Check every destination before writing;
reject symlink paths. Preserve existing evidence and verify hashes when moving
it. Do not raise the deployment target for a future nonblocking warning.

## Read-only validation

```sh
python3 tools/ios/nightly_testflight.py dry-run
python3 -m unittest discover -s tools/tests -p 'test*testflight*.py'
git diff --check
```

The dry run reads branches, commits, status and upstream configuration, checks
required tool availability and the private storage boundary, and reports actual
auth readiness. It never claims a real day, changes a release state or uploads.
Guard tests exercise duplicate claims, overlapping days, owner-only completion
and failure-closed outcomes using temporary fixtures. Read back the live enabled
schedule, timezone, next run, identity, paths and full reporting contract after
activation; do not manually fire a duplicate release merely to test scheduling.
