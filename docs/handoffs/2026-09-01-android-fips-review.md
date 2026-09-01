# Android embedded FIPS independent review

Review commit `c472aec5a66ecc0d49b472f752543e3b30e2ab8c` on `main` in
`/Users/mini/code/wm/wmapp`. This is a focused implementation and release audit,
not a redesign.

## Goal

Establish whether the Android `VpnService` implementation genuinely exercises
the official FIPS v0.5.0 app-owned TUN and UDP-FD interfaces safely. Fix any
confirmed defect, rerun proportionate validation, commit all tested nonignored
state with a Conventional Commit, and push `main`. If no fix is required, do not
create an empty commit; report exact evidence.

## Required review points

1. Trace startup ordering end to end: Flutter channel, VPN consent, service,
   native prepare, app-owned TUN/UDP FD enabling, `VpnService.protect(fd)`, node
   start/run. Confirm no FIPS transport socket can loop into the VPN.
2. Trace stop, failure, repeated start, and process recreation. In particular,
   determine whether the TUN reader can remain blocked on a duplicated FD while
   teardown joins its thread. Prove clean unblocking or fix it.
3. Check Rust/JNI ownership and signatures, descriptor duplication/closing,
   exception handling, identity secrecy, and the exact pinned FIPS commit.
4. Verify only `fd00::/8` and the deliberate DNS interception address are routed;
   normal internet remains outside the VPN and WM-App itself is not excluded.
5. Review DNS packet reconstruction, checksums, MSS clamping, and `.fips`-only
   proxy behavior against tests.
6. Review peer-status parsing so a disconnected bootstrap or a different
   connected peer cannot yield a false positive.
7. Inspect the final APK: ARM64-only, contains `libwmapp_fips_android.so`, and no
   identity/private-key material or generated cache is tracked.
8. Re-run Rust fmt/clippy/tests, Kotlin unit tests and androidTest compilation,
   Flutter analyze/tests, and the supported ARM64 debug APK build if a fix is
   made. If no fix is made, at minimum rerun the focused native and Kotlin tests
   and independently inspect existing build evidence.
9. There is no attached Android target. Do not claim device validation. Confirm
   the exact `.fips` WebView instrumentation test is deterministic and documents
   the Chromium ULA/AAAA uncertainty honestly.
10. Explicitly verify ordinary DNS while the VPN is active. Android's configured
    `Builder.addDnsServer(10.1.1.1)` may direct non-FIPS system queries to the
    routed interception address; simply dropping packets whose questions are not
    all `.fips` would then break normal hostname resolution despite split IP
    routes. Prove ordinary DNS bypasses the VPN, or add a safe protected upstream
    fallback/other split-DNS solution and a regression test.

## Constraints

- Work on `main`; preserve concurrent work and never reset/discard changes.
- No Autopilot or registered-app restart.
- Do not weaken exact-origin trust or replace `.fips` with an IPv6 literal.
- Do not use `addDisallowedApplication` for WM-App.
- Report findings first, then commit/test/APK evidence and the precise remaining
  hardware validation gap.
