# Tower workspace identity pairing

The current native contract supersedes the earlier HTTPS logical-Tower pairing.
Built-in Flight Deck and the explicitly configured external Flight Deck origin
receive the production bridge even when native `towerUrl` is empty. General
signer-trusted pages do not gain Tower transport access.

```js
window.wingmanTowerTransport.pairingIdentity === 'service-npub';
await window.wingmanTowerTransport.connect({ endpoint, serviceNpub });
// { version: 2, endpoint, serviceNpub, transport: 'native' }
```

Flight Deck supplies the selected workspace's stored Tower service npub, not the
mesh node identity. Native approval binds page origin, service npub, exact mesh
endpoint and active signer. The new grant namespace requires approval once after
upgrading; browser data, workspace identity and outbox are unaffected.

After approval, native code reads `/health` only through the pinned mesh proxy.
The returned service identity must match before the route permits mesh signing
or page requests. Failed verification, cancellation and document revocation close
the probe. Flight Deck checks the signed workspace descriptor and disconnects on
identity failure. No public Tower lookup or HTTPS fallback participates.

The NIP-98 URL is the exact mesh endpoint plus path and query, matching the URL
passed to native fetch. Existing signer approval, target checks, mesh IPv6 pin,
redirect rejection, frame boundary and streaming cancellation remain enforced.
The existing backend locator is retained only as Flight Deck's compatibility
lookup key; it need not be reachable and is not entered again in native Setup.
TowerSyncService remains the sole network-update owner.

Both clients must support this contract: an older native v2 bridge lacks the
`pairingIdentity` capability and prompts an update; an older Flight Deck caller
supplying only `logicalTower` receives an instruction to update Flight Deck.

Validation uses blank-config BrowserScreen injection/signing tests with real
socket health responses, native probe cancellation/identity tests, and
`python3 tools/test_tower_bridge_wkwebview.py`. The WK fixture bundles the actual
Flight Deck transport consumer (sibling checkout, or `FLIGHT_DECK_DIR`) and runs
production native JS/Dart through stock HTTPS WKWebView. Public Tower fetches
are forced unavailable while reconnect, target mapping, binary/auth transport,
SSE and worker cancellation run. Fixture authorization and the counting signer
are test doubles; live cryptographic authentication and Tower ACL validation
remain separate deployment checks.
