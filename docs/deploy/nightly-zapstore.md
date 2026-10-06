# Wingman Nightly on Zapstore

Wingman Nightly uses `com.wingmanbefree.wingman_app.nightly`, installs alongside
stable WMAPP and has its own private persistent Android signing keystore.
Stable package, publisher and `zapstore.yaml` remain unchanged. Nightly's public
catalog and repository ownership proof live at
https://github.com/OtherStuffAI/wingman-nightly; the catalog's root `zapstore.yaml`
pins Rick's publisher. `zapstore-nightly.yaml` is the reusable source configuration.

## Release procedure

Use `tools/nightly_zapstore.py` under an authorized Rick broker session. Provision
an owner-only PKCS12 Android keystore and owner-only password reference outside
Git at `~/.config/wmapp/wingman-nightly-release.p12` and
`~/.config/wmapp/wingman-nightly-release.password`, alias `wingman-nightly`.
These are Android credentials, separate from the Nostr identity. Never derive,
export or provide a Nostr private key. Back up Android credentials privately;
future APK updates require the same certificate.

1. One existing 22:00 `Australia/Perth` scheduler session prepares validated,
   compatible source checkpoints on main: Flight Deck first, WMAPP second.
   Preserve incompatible/concurrent edits and report them. TestFlight executes
   its existing private release contract, records its result and finishes its
   claim before Android. An Apple failure does not silently skip Android.
2. Set the verified `FLIGHT_DECK_PG_APP_NPUB` from scoped Flight Deck context.
   Run `python3 tools/nightly_zapstore.py build`. It checks no TestFlight claim
   is active, queries relay history, reserves above all local/remote numbers,
   builds Flight Deck then Android from isolated committed archives, validates
   Flight Deck public source/tests/dist, Flutter analysis/tests and ARM64 APK.
   Generated files never modify shared source. Local reservations never expire.
   For independently authorized first-publication setup only,
   `--committed-source` may preserve incompatible active edits and records their
   exclusion while validating the exact committed snapshots. Scheduled runs
   require clean, validated source and must not use this exception.
3. Run `prepare`. It verifies the APK signature, exact package/version/name,
   certificate, ARM64 contents, FIPS library/service and canonical extracted icon.
   zsp v0.4.17 emits JSONL with `SIGN_WITH` set to Rick's **public** npub,
   `--offline --no-compress --channel nightly --commit <commit>`.
   No publisher signing or upload occurs inside zsp. The adapter signs kind 3063
   first, rewrites kind 30063's asset reference to the actual broker-signed ID,
   then signs kinds 30063 and 32267. It rejects stable packages, changed identity,
   templates/signatures and unexpected asset hosts.
4. zsp's `identity --offline` signs NIP-C1's ownership message with the Android
   keystore and outputs unsigned kind 30509 (`d`, `signature`, `expiry`). The
   broker independently signs that event. Its timestamp must exactly match the
   Android proof timestamp; the adapter verifies the RSA proof against the DER
   certificate and rejects a mismatch. At most three fresh proofs are generated
   before publication; broker denials never trigger fallback or policy widening.
5. Publish committed source archives and public build-proof JSON as GitHub
   release assets using the authorized public Nightly catalog. Proof includes
   exact WMAPP/Flight Deck commits, source archive hashes, FD build identity and
   asset hashes, APK hash/version/package/certificate and publisher identity.
   Never include operational logs, local paths, credentials or device identifiers.
6. Run `publish` once. It records `delivery_pending` before network mutations,
   uploads APK/icon through the broker's Blossom client, retrieves public bytes,
   verifies the downloaded APK certificate/hash, publishes signed proof and
   release events to `wss://relay.zapstore.dev`, and reads every event back.
   Only all gates passing produce `published`. A receipt alone is insufficient.
   Independently verify the public listing and linked release/asset records.
7. On uncertainty use `readback --day <original-day>` and inspect the exact
   retained signed IDs and public APK. Never retry upload or publication, repair
   ledger state, reuse a version code, or infer success from upload receipts.
   Reporting is independent for TestFlight and Android. Keep pending state until
   exact delivery and reporting are reconciled by an authorized operator.

Run-specific evidence and state are ignored under `tmp/docs/handoffs/`.
Use `status` for read-only inspection. A duplicate day, active prior reservation,
wrong owner, invalid history or Android version limit fails closed. No extra
scheduler trigger or runtime restart is required. Future proof expiry requires
fresh Android ownership proof and broker signing.

## Validation

```sh
bun test ./tools/zapstore_broker.test.ts
python3 -m unittest discover -s tools/tests -p 'test_nightly_zapstore.py'
python3 -m unittest discover -s tools/tests -p 'test*testflight*.py'
```

Official formats: [publisher documentation](https://zapstore.dev/docs/publish),
[zsp source](https://github.com/zapstore/zsp),
[trust model](https://zapstore.dev/docs/trust-model). Repository proof must be
publicly readable before the app event reaches the relay. The Android certificate
and Rick's Nostr publisher are distinct cryptographic identities.
