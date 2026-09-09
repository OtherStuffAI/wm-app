# WMapp Tower FIPS bridge

Task: b5f96311-d672-46ca-ab2d-e0bb0cdde8f8. WMapp implementation owner:
082e14f1-9e73-4d5d-b694-8907995e06a7. Source implementation and tests complete;
manager owns shared Tower activation and live workspace acceptance. Manager task
comments at 06:32 UTC report mesh and HTTPS health 200, unsigned/wrong-origin
rejections and gateway outage/recovery passing. Authenticated live mesh PG/SSE
validation remains pending a narrow broker signing-origin grant; this worker has
not bypassed that restriction or changed shared runtime state.

## Platform decision

The initially agreed v1 `connect -> proxyBaseUrl` cannot serve an HTTPS page in
stock macOS WKWebView. On macOS 15.6.1, an actual `https://example.com` page failed
`fetch(http://127.0.0.1:<port>/...)` with `Load failed`, including a compiled app
with WMapp's existing Info.plist ATS settings. The identical loopback server
returned 200 from a loopback page (`isSecureContext === true`). The independent
reviewer's `tools/fips_bridge/` probes also cover page/worker behavior.

Manager and Flight Deck primary accepted native **v2** on the task on September 9.
No mixed-content setting, TLS exception, ATS setting or global fetch/EventSource
function has been changed. A real HTTPS WKWebView page and Worker now pass the
native v2 integration harness using production JS/Dart and real upstream sockets.

## Definitive producer/consumer interface

```js
window.wingmanTowerTransport = {
  version: 2,
  available: true,
  connect: async ({endpoint, logicalTower}) => ({
    version: 2, endpoint, logicalTower, transport: 'native'
  }),
  fetch: async (meshUrl, requestInit) => Response,
  attachWorker: worker => undefined,
  detachWorker: worker => undefined,
  disconnect: async () => undefined,
};
```

Bridge availability is announced by `wingman-tower-transport-ready` after native
injection on page finish. Consumers restoring a saved preference should wait for
that event, then fail explicitly if unavailable. Do not interpret v2 as v1 or
fall back to public requests when FIPS is selected.

`endpoint` must be an exact canonical `http://<node npub>.fips:<port>` origin with
no trailing slash, path, query, fragment, userinfo or alternate authority. The
npub Bech32 checksum/padding is validated. `logicalTower` must equal WMapp's
configured public HTTPS Tower origin. Current support is **one configured logical
Tower**; multiple workspaces on that Tower are supported. Other Tower selections
fail explicitly. Both producer and Flight Deck must retain the public logical
Tower identity, page origin and existing Dexie/workspace keys.

The page signs the actual mesh endpoint + path + query. Pass that exact mesh URL
to `bridge.fetch`; Authorization and request bytes are carried unchanged. No
proxyBaseUrl is returned in v2. The native bridge neither obtains keys nor signs
requests. Existing signer approvals and Tower auth/ACL checks remain separate.

`Response` carries HTTP status, statusText, content headers and a pull-driven
ReadableStream. Binary uploads are sent in at most 64 KiB chunks; downloads/SSE
are pulled in at most 64 KiB chunks. Content compression is decoded like browser
fetch, removing stale compressed length/encoding headers. Redirect responses are
rejected as sanitized 502, never followed. Network errors have no token-bearing
URLs. AbortSignal (including TimeoutError reason) and reader cancellation close
the native request/upstream connection, including idle SSE and pre-header waits.

`attachWorker(worker)` transfers a MessagePort in
`{type:'wingman-tower-transport-port', port}`. Worker sends:

- `{type:'request', id, url, method, headers:[...new Headers(...)], bodyBase64:null|string}`
- `{type:'pull', id}` (one outstanding pull)
- `{type:'cancel', id}`

Page replies:

- `{type:'headers', id, status, headers:[...new Headers(...)]}`
- `{type:'chunk', id, bodyBase64}` (at most 64 KiB decoded)
- `{type:'end', id}` or `{type:'error', id}` (sanitized)

Flight Deck owns the worker SSE parser, cursor/reconnect/recovery and sync state.
Attaching the same worker again cancels and replaces its old port. Call synchronous
`detachWorker(worker)` before every Worker termination/replacement; it aborts all
old native requests/SSE and closes/removes the worker port. Disconnect
cancels active operations but preserves the port for a later manual reconnect.
Worker request bodies currently use one base64 message capped at 16 MiB decoded;
larger bodies are rejected. Page fetch uploads stream without that cap.
Larger worker-originated uploads require a future upload-chunk port extension;
ordinary sync writes and SSE are supported without whole-response buffering.

## Pairing and security boundaries

Only configured first-party Flight Deck and bundled local Flight Deck origins
receive the bridge. A native dialog displays page origin, logical Tower and
manually entered endpoint before existing FIPS readiness/install/VPN handling.
It explicitly remembers a grant scoped to `(page origin, logical Tower, endpoint,
active public identity)`. Reload restores that grant with a fresh document nonce
and fresh native route; capabilities and active streams do not survive navigation.

`disconnect()` revokes the active pairing grant. Clear Browser Data, logout,
identity changes and Tower/Flight Deck configuration changes revoke grants and
active capabilities. Tab close and navigation revoke the document capability and
streams. Late approval/readiness results cannot recreate a revoked document.
Pairing grants contain public identifiers only, never keys or route capabilities.

WKWebView checks actual native main-frame/current-frame origin metadata for the
WingmanTower channel. A secret in the injected top-document closure protects
channel messages on all platforms; cross-origin frames cannot mint requests by
claiming a tab origin. Native responses and revocation are document-token-bound.
The existing signer remains the only signing implementation. Its HTTP mesh
NIP98 entry points (including `signEvent` kind 27235) now require the active exact
pairing and the top document's nonce for Flight Deck. A remembered kind grant alone
cannot sign another mesh target. Identity/document/pairing are rechecked after
policy/dialog awaits and before delivery of the signature. WKWebView also rejects
iframe calls to WingmanSigner. Existing directly loaded FIPS WApps retain signing
for their own page origin; public HTTPS signing behavior remains unchanged.

The internal proxy binds IPv4 `127.0.0.1` on an ephemeral port with a 256-bit route.
It requires exact route, approved Origin and local Host; rejects other methods,
retargeting, unknown routes and redirects; supplies exact-origin CORS/preflight
including Private Network Access and content-header exposure. No wildcard CORS.
It strips hop-by-hop/nominated, forwarded-host/proto, Origin, Referer and cookie
headers before Tower and drops Set-Cookie/Location on responses. Fixed mesh Host
preserves NIP98 target semantics. It ignores system HTTP proxies and dials only
the FIPS v0.5 address derived from the paired public npub:
`fd || SHA256(x-only public bytes)[0:15]`, at the pinned port. There is no DNS
rebinding, arbitrary IP target, discovery, cookie propagation or public fallback.
Native cancellation explicitly closes its upstream client; it does not depend on
Dart HttpServer detecting an idle browser-side TCP disconnect.

## Setup and activation

1. For bundled Flight Deck, after the primary finishes and verifies its new dist,
   refresh only from that local dist (coordinate with the concurrent iOS worker):
   `FLIGHT_DECK_DIR=/Users/mini/code/wm/flightdeck ./tools/update_flightdeck_bundle.sh --use-existing-dist`.
   This avoids fetching an older remote snapshot or rebuilding another worker's
   checkout. Then build WMapp: `cd app && flutter build macos --debug --no-pub`.
   Output: `app/build/macos/Build/Products/Debug/wingman_app.app`.
   Launch/install this built app in the normal user session when coordinated;
   this task does not replace or restart an already-running WMapp instance.
2. Configure the public Tower as `https://sb4.otherstuff.studio` and open Flight
   Deck at its existing configured HTTPS origin (or bundled local origin).
3. Manager verifies/maintains Tower's activated dedicated ingress and native host gateway using
   `/Users/mini/code/wm/tower/docs/fips-ingress.md`; do not restart Autopilot.
4. In Flight Deck choose FIPS and enter:
   `http://npub109684nue495hq240u3dqzyf2kltk23u3mqkk9l44ga6szed4jcysramf74.fips:43100`
   Approve the native pairing dialog and existing FIPS readiness/consent flow.
   That public node pins to `[fd87:f2eb:de48:6212:be46:3c95:4494:49ec]:43100`.
5. Sign/fetch e.g. `<endpoint>/api/...?...` through v2; preserve
   `https://sb4.otherstuff.studio` as logical identity. Reload should restore the
   pairing without another dialog. HTTPS mode remains independently available.

## Validation

- `cd app && flutter analyze --no-pub`.
- `cd app && flutter test --no-pub`: entire app suite, including real sockets,
  pairing isolation/checksum/address vectors, readiness failure and revoke races.
- `python3 tools/test_tower_bridge_wkwebview.py`: stock HTTPS WKWebView, production
  native main-frame policy, production bridge JS/Dart, real HTTP sockets, 180 KB
  binary/auth/status/headers, forbidden targets/redirects, pre-header abort, split
  UTF-8 SSE before EOF, actual Worker port streaming and cancellation. The fixture
  uses a public HTTPS page and a test-only approved loopback upstream, not live
  Tower credentials or shared service activation.
- `dart run tools/export_tower_bridge.dart [test-token] [page-origin]` emits the
  exact production JS for Flight Deck producer/consumer tests. Defaults are a
  test-only document token and `https://example.com`.
- `flutter build macos --debug --no-pub` validates the native plugin/app build.
- `dart --packages=app/.dart_tool/package_config.json tools/tower_bridge/live_health.dart <endpoint>`:
  read-only live health through the production pinned IPv6/native proxy path.
  Passed against the activated node/port above: HTTP 200 JSON. No broker signing
  or live workspace writes are performed by this smoke.

Remaining live pass: run the newly built WMapp with the new Flight Deck source,
verify manager-owned Tower ingress/gateway, then verify paired health, real
signed workspace reads/writes/ACL failures, live SSE recovery after mesh loss,
storage upload/download, reload pairing, browser data/origin continuity and
explicit failure with FIPS unavailable. No live source activation is implied by
fixture/build success. Android native bridge device smoke remains; Linux depends
on the existing supported WebView plugin/runtime. This change does not advertise
Tower bridge v2 on iOS; the concurrent iOS FIPS runtime worker owns that separate
platform work. Existing iPhone HTTPS behavior is retained.
