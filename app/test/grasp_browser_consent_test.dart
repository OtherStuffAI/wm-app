// Product wiring tests; these do not substitute for native WebView UX evidence.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_webview_platform.dart';
import 'mesh_auth_signing_test.dart' show Harness;
import 'grasp_fips_transport_test.dart' show endpoint;

const page = 'https://gitworkshop.example/repository';
Map<String, dynamic> auth([String target = '$endpoint/owner/repo.git']) => {
      'kind': 27235,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'content': '',
      'tags': [
        ['u', target],
        ['method', 'GET']
      ]
    };
Future<String> start(Harness h, WidgetTester tester) async {
  await h.start(tester);
  await submitFakeNavigationRequest(
      controllerIndex: 0, url: page, isMainFrame: true);
  submitFakePageFinished(controllerIndex: 0, url: page);
  await tester.pumpAndSettle();
  final signer = fakeExecutedJavaScripts
      .lastWhere((s) => s.contains('const signerDocumentToken ='));
  h.token = jsonDecode(RegExp(r'const signerDocumentToken = (.*);')
      .firstMatch(signer)!
      .group(1)!);
  final script = fakeExecutedJavaScripts
      .lastWhere((s) => s.contains("'wingmanGraspTransport'"));
  return RegExp(r'const token = "([^"]+)"').firstMatch(script)!.group(1)!;
}

void rpc(String token, String method) => submitFakeJavaScriptMessage(
    controllerIndex: 0,
    channel: 'WingmanGrasp',
    message: jsonEncode({
      'token': token,
      'id': method,
      'method': method,
      'params': {'endpoint': endpoint}
    }));
Future<void> connect(String token, WidgetTester tester) async {
  rpc(token, 'connect');
  await tester.pumpAndSettle();
  expect(find.text('Connect to private Git service?'), findsOneWidget);
  expect(find.byType(TextField), findsNothing);
  await tester.tap(find.text('Connect'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets(
      'native transport consent does not replace exact signature consent',
      (tester) async {
    final h = Harness();
    final token = await start(h, tester);
    h.sign('unapproved', event: auth());
    await tester.pumpAndSettle();
    expect(h.signer.events, isEmpty);
    await connect(token, tester);
    h.sign('other-port',
        event:
            auth('${endpoint.replaceFirst(':8787', ':8788')}/owner/repo.git'));
    await tester.pumpAndSettle();
    expect(h.signer.events, isEmpty);
    h.sign('approved', event: auth());
    await tester.pumpAndSettle();
    expect(find.text('Approve private app authentication?'), findsOneWidget);
    await tester.tap(find.text('Approve signature'));
    await tester.pumpAndSettle();
    expect(h.signer.events.length, 1);
    rpc(token, 'disconnect');
    await tester.pumpAndSettle();
    h.sign('revoked', event: auth());
    await tester.pumpAndSettle();
    expect(h.signer.events.length, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'public HTTPS auth still uses existing signer policy with GRASP injected',
      (tester) async {
    final h = Harness();
    await start(h, tester);
    h.sign('public', event: auth('https://public.example/repo.git'));
    await tester.pumpAndSettle();
    expect(h.signer.events.length, 1);
    expect(find.text('Approve private app authentication?'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final reason in [
    'navigation',
    'identity',
    'lock',
    'tab-close',
    'disconnect-reconnect'
  ]) {
    testWidgets('pending GRASP signature invalidated by $reason',
        (tester) async {
      final h = Harness();
      final token = await start(h, tester);
      await connect(token, tester);
      h.sign('pending', event: auth());
      await tester.pumpAndSettle();
      expect(find.text('Approve private app authentication?'), findsOneWidget);
      if (reason == 'navigation') {
        await submitFakeNavigationRequest(
            controllerIndex: 0, url: page, isMainFrame: true);
      } else if (reason == 'identity' || reason == 'lock') {
        h.config = reason == 'identity'
            ? h.config.copyWith(deviceNpub: 'other')
            : h.config.copyWith(deviceSecret: '');
        await tester.pumpWidget(h.widget());
      } else if (reason == 'tab-close') {
        await tester.pumpWidget(const SizedBox());
        return;
      } else {
        rpc(token, 'disconnect');
        await tester.pumpAndSettle();
        // Reconnect's native dialog stacks above the old signature dialog.
        await connect(token, tester);
      }
      await tester.tap(find.text('Approve signature'));
      await tester.pumpAndSettle();
      expect(h.signer.events, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
