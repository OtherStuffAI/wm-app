import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_webview_platform.dart';
import 'grasp_browser_consent_test.dart' show start, connect, rpc;
import 'mesh_auth_signing_test.dart' show Harness;
import 'grasp_fips_transport_test.dart' show endpoint;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets('suspension revokes grants and signer; resume mints fresh scopes',
      (tester) async {
    final h = Harness();
    final oldTransport = await start(h, tester);
    await connect(oldTransport, tester);
    final oldSigner = h.token;
    final oldSignerScript = fakeExecutedJavaScripts
        .lastWhere((s) => s.contains('const signerDocumentToken ='));
    final loads = fakeLoadedRequestUrls.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(
        fakeExecutedJavaScripts.any((s) =>
            s == 'window.__wingmanSignerRevoke?.(${jsonEncode(oldSigner)})'),
        isTrue);
    expect(
        fakeExecutedJavaScripts
            .any((s) => s.contains('__wingmanGraspRevoke?.("$oldTransport")')),
        isTrue);
    h.sign('suspended',
        method: 'signNip98',
        event: {'url': '$endpoint/api/info', 'httpMethod': 'GET'});
    rpc(oldTransport, 'connect');
    await tester.pumpAndSettle();
    expect(h.signer.events, isEmpty);
    expect(find.text('Connect to private FIPS service?'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final script =
        fakeExecutedJavaScripts.lastWhere((s) => s.contains("'fipsTransport'"));
    final freshTransport =
        RegExp(r'const token = "([^"]+)"').firstMatch(script)!.group(1)!;
    expect(freshTransport, isNot(oldTransport));
    final signer = fakeExecutedJavaScripts
        .lastWhere((s) => s.contains('const signerDocumentToken ='));
    final freshSigner = jsonDecode(RegExp(r'const signerDocumentToken = (.*);')
        .firstMatch(signer)!
        .group(1)!);
    expect(freshSigner, isNot(oldSigner));
    // Execute the production JS in a real VM: a delayed old native revoke must
    // not reject requests made using the freshly injected signer document.
    final result = Process.runSync('node', [
      '-e',
      r"""
const vm = require('node:vm');
const assert = require('node:assert/strict');
const data = JSON.parse(process.argv[1]);
const messages = [];
const window = {}; window.top = window;
const sandbox = vm.createContext({window, location:{origin:data.origin},
  setTimeout, clearTimeout, WingmanSigner:{postMessage:m=>messages.push(JSON.parse(m))}});
(async () => {
  vm.runInContext(data.old, sandbox);
  const oldRequest = window.nostr.getPublicKey();
  window.__wingmanSignerRevoke(data.oldToken);
  await assert.rejects(oldRequest, /revoked/);
  vm.runInContext(data.fresh, sandbox);
  const request = window.nostr.getPublicKey();
  window.__wingmanSignerRevoke(data.oldToken);
  window.__wingmanResolve(messages.at(-1).id, {result:'fresh-public-key'});
  assert.equal(await request, 'fresh-public-key');
  const revoked = window.nostr.getPublicKey();
  window.__wingmanSignerRevoke(data.freshToken);
  await assert.rejects(revoked, /revoked/);
  await assert.rejects(window.nostr.getPublicKey(), /revoked/);
})().catch(error => { console.error(error); process.exitCode = 1; });
""",
      jsonEncode({
        'old': oldSignerScript,
        'fresh': signer,
        'oldToken': oldSigner,
        'freshToken': freshSigner,
        'origin': 'https://gitworkshop.example'
      })
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    expect(signer, contains('Native request expired or revoked.'));
    expect(fakeLoadedRequestUrls.length, loads,
        reason: 'Resume preserves the page and local draft storage');
    h.sign('stale',
        proof: oldSigner,
        method: 'signNip98',
        event: {'url': '$endpoint/api/info', 'httpMethod': 'GET'});
    await tester.pumpAndSettle();
    expect(h.signer.events, isEmpty);
    await connect(freshTransport, tester);
    await tester.pumpWidget(const SizedBox());
  });
}
