# Isolated native GRASP probe

This tool runs the production Dart bridge/transport through a separate stock macOS
WKWebView and its production native frame policy. The WebView uses nonpersistent
storage and no signer. The test harness approves only its command-line endpoint;
it does not exercise the product's native consent dialog or establish member UX.
It never connects to the running WMapp profile or keychain.

From the repository root, resolve dependencies in `app/`, then:

```sh
# Choose a Git-ignored evidence directory according to AGENTS.md.
swiftc tools/grasp_bridge/main.swift \
  packages/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview/WingmanScriptMessagePolicy.swift \
  -o "$evidence_dir/grasp-wk-probe"
dart --packages=app/.dart_tool/package_config.json \
  tools/grasp_bridge/native_server.dart https://example.com \
  'http://npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98.fips:8787' --fixture
```

The server prints a private random loopback RPC route for the native test process.
Do not expose it to web content or publish it. The production app has no such listener.
Create a test JavaScript file by prepending this configuration to `probe.js`:

```js
globalThis.graspProbe = {
  endpoint: 'http://npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98.fips:8787',
  fixture: true
};
```

Run the compiled probe with arguments: printed RPC route, `https://example.com`,
test JavaScript file, optional screenshot output. Stop only the test server you
started after completion. Fixture checks cover native binary HTTP, text/binary WS,
redirect rejection, pending-header abort, iframe-channel denial and disconnect.

For an authorized live private service, omit `--fixture`, use its exact HTTPS
frontend origin and exact FIPS endpoint, set `fixture:false`, and supply
`repositoryRoot`. Live probe expects the frontend CSP to block ordinary HTTP/WS,
then verifies the native bridge still obtains GRASP08 NIP11 and a NIP42 challenge.
It verifies anonymous root/refs remain denied. It performs no signing or publication.
A live pass explicitly reports `memberUX:false`.
