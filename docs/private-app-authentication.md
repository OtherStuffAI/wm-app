# Private app authentication in WMapp

Open a private app using its link in Flight Deck or Autopilot, then choose the
app's connect/sign-in action. For a directly loaded FIPS app, WMapp derives the
HTTP or relay authentication address from the actual signing request. No FIPS
address needs to be entered in Setup or a Tower pairing dialog.

The native **Approve private app authentication?** dialog shows the requesting
website, full exact target (including scheme, port and path), operation and active
signing identity. Choose **Approve signature** only for the intended target, or
**Deny**. Website titles and links in chat are not authenticated app identity.
App-list visibility does not grant signing permission.

Each approval signs one request. HTTP and WebSocket relay authentication are
separate, and repeated Git reads or relay reconnects can prompt again. No wildcard
port, matching-host exception, saved target grant or public fallback is created.
Existing signer deny rules still apply; remembered allows do not bypass this
native confirmation. Closing the tab, navigating, locking/changing identity or
clearing browser data invalidates pending approval. If a same-document navigation
leaves the signer unavailable, reload the page and reconnect.

This direct-app path supports strict FIPS HTTP authentication (kind 27235 or
`signNip98`) and FIPS WebSocket relay authentication (kind 22242). It rejects
ambiguous target tags, URL credentials/fragments, malformed authentication and
non-FIPS destinations. Authentication does not grant repository membership or
change the server's read/write rules.

Flight Deck's Tower transport remains separate: it requires its exact verified
Tower service pairing and document token. Configured Flight Deck pages cannot
use the direct-app approval as a substitute, including after disconnect. GRASP
must not be entered as a Tower endpoint; it is a different service.

The existing personal-WApp signer metadata contract describes future native
identity/discovery integration. The browser does not currently consume those
records as native signing grants. This request-only flow requires no shared
metadata or server change.

Validation:

```sh
cd app
flutter test test/mesh_auth_request_test.dart test/mesh_auth_signing_test.dart test/tower_mesh_signing_test.dart
flutter analyze
```

The widget tests exercise native approval and rejection gates with a fake
WebView and counting signer. A separate case uses the real native signer with
an ephemeral test identity and verifies both HTTP and relay signatures. These
tests do not prove real WebView frame isolation, server authentication or
live-device success. For device acceptance,
install the signed release using the [iPhone build procedure](deploy/iphone.md),
open the private app's existing link, approve its intended HTTP and relay targets,
and verify repository files/history. Repeat with denial and a fresh navigation.
