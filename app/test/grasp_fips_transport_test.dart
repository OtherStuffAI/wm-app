import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_app/src/core/grasp_fips_transport.dart';
import 'package:wingman_app/src/features/browser/grasp_fips_browser_bridge.dart';

const node = 'npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98';
const endpoint = 'http://$node.fips:8787';
void main() {
  late HttpServer server;
  late GraspFipsTransport transport;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    transport = GraspFipsTransport(endpoint,
        clientFactory: () => HttpClient()
          ..connectionFactory = (_, __, ___) =>
              Socket.startConnect(InternetAddress.loopbackIPv4, server.port));
  });
  tearDown(() async {
    transport.close();
    await server.close(force: true);
  });
  test('binary HTTP and challenge headers; no cookies or host spoofing',
      () async {
    final bytes = List.generate(180000, (i) => i % 256);
    server.listen((r) async {
      expect(r.headers.value('host'), '$node.fips:8787');
      expect(r.headers.value('cookie'), isNull);
      expect(r.headers.value('origin'), isNull);
      expect(r.headers.value('git-protocol'), 'version=2');
      expect(r.headers.value('authorization'), 'Nostr test');
      final body = await r.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(body, bytes);
      r.response.statusCode = 401;
      r.response.headers.set('www-authenticate', 'Nostr method="GET"');
      r.response.headers.set('set-cookie', 'secret=1');
      r.response.add(body);
      await r.response.close();
    });
    final r = await transport
        .open('$endpoint/owner/repo.git/git-upload-pack', 'POST', {
      'host': 'other',
      'cookie': 'bad',
      'origin': 'bad',
      'authorization': 'Nostr test',
      'git-protocol': 'version=2'
    });
    for (var i = 0; i < bytes.length; i += 60000) {
      await r.write(
          base64Encode(bytes.sublist(i, (i + 60000).clamp(0, bytes.length))));
    }
    final meta = await r.finish();
    expect(meta['status'], 401);
    expect(meta['headers']['www-authenticate'], 'Nostr method="GET"');
    expect(meta['headers']['set-cookie'], isNull);
    final received = <int>[];
    while (true) {
      final next = await r.pull();
      if (next['done'] == true) break;
      received.addAll(base64Decode(next['chunk']));
    }
    expect(received, bytes);
  });
  test('other service/port/userinfo/fragment and redirects rejected', () async {
    for (final target in [
      '$endpoint.evil/x',
      'http://$node.fips:8788/x',
      '$endpoint/x#bad',
      'http://user@$node.fips:8787/x',
      'https://example.com/x'
    ]) {
      expect(() => transport.open(target, 'GET', {}), throwsFormatException);
    }
    server.listen((r) async {
      r.response.statusCode = 302;
      r.response.headers.set('location', 'http://127.0.0.1/secret');
      await r.response.close();
    });
    final r = await transport.open('$endpoint/redirect', 'GET', {});
    await expectLater(r.finish(), throwsStateError);
  });
  test('real WebSocket handshake, challenge, binary and revoke', () async {
    server.listen((r) async {
      final ws = await WebSocketTransformer.upgrade(r);
      ws.add('["AUTH","fixture-challenge"]');
      ws.listen(ws.add);
    });
    final ws =
        await transport.socket('${endpoint.replaceFirst('http:', 'ws:')}/');
    expect((await ws.next())['data'], '["AUTH","fixture-challenge"]');
    expect(transport.hasChallenge(ws.url, 'fixture-challenge'), isTrue);
    await ws.send(base64Encode([0, 255, 12]), false);
    expect((await ws.next())['data'], base64Encode([0, 255, 12]));
    final pending = ws.next();
    transport.close();
    await pending.catchError((_) => <String, dynamic>{});
    expect(transport.hasChallenge(ws.url, 'fixture-challenge'), isFalse);
    await expectLater(ws.send('no', true), throwsStateError);
  });
  test('revocation safely destroys socket during queued and active sends',
      () async {
    server.listen((r) async {
      final ws = await WebSocketTransformer.upgrade(r);
      ws.listen((_) {}).pause();
    });
    final ws =
        await transport.socket('${endpoint.replaceFirst('http:', 'ws:')}/');
    final data = base64Encode(List.filled(1024 * 1024, 7));
    final pending =
        List.generate(4, (_) => ws.send(data, false).catchError((Object _) {}));
    await Future<void>.delayed(Duration.zero);
    expect(transport.close, returnsNormally);
    await Future.wait(pending).timeout(const Duration(seconds: 2));
    expect(ws.closed, isTrue);
  });
  test('cancellation interrupts pending HTTP headers', () async {
    server.listen((r) {});
    final r = await transport.open('$endpoint/hang', 'GET', {});
    final check = expectLater(r.finish(), throwsA(anything));
    r.close();
    await check.timeout(const Duration(seconds: 2));
  });
  test('auth is root GET only and relay challenge belongs to active grant',
      () async {
    server.listen((r) async {
      final ws = await WebSocketTransformer.upgrade(r);
      ws.add('["AUTH","current-challenge"]');
      ws.listen((_) {});
    });
    dynamic result;
    final bridge = GraspFipsBrowserBridge(
        pageOrigin: 'https://app.example',
        approve: (_) async => true,
        prepare: (_) async => null,
        transportFactory: (_) => transport,
        reply: (s) async {
          if (s.contains('Reply')) {
            result = (jsonDecode(
                    '[${s.substring(s.indexOf('(') + 1, s.length - 1)}]')
                as List)[2];
          }
        });
    final token =
        RegExp(r'const token = "([^"]+)"').firstMatch(bridge.script)!.group(1);
    Future<void> rpc(String method, Map<String, dynamic> params) =>
        bridge.receive(jsonEncode({
          'token': token,
          'id': method,
          'method': method,
          'params': params
        }));
    Map<String, dynamic> event(int kind, List<List<String>> tags) => {
          'kind': kind,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'content': '',
          'tags': tags
        };
    final http = event(27235, [
      ['u', '$endpoint/owner/repo.git'],
      ['method', 'GET']
    ]);
    expect(bridge.permitsAuthentication('signEvent', http), isFalse);
    await rpc('connect', {'endpoint': endpoint});
    final epoch = bridge.grantEpoch;
    expect(bridge.permitsAuthentication('signEvent', http), isTrue);
    expect(
        bridge.permitsAuthentication(
            'signEvent',
            event(27235, [
              ['u', '$endpoint/owner/repo.git'],
              ['method', 'POST']
            ])),
        isFalse);
    final url = '${endpoint.replaceFirst('http:', 'ws:')}/';
    final auth = event(22242, [
      ['relay', url],
      ['challenge', 'current-challenge']
    ]);
    expect(bridge.permitsAuthentication('signEvent', auth), isFalse);
    await rpc('wsOpen', {'url': url});
    final id = result;
    await rpc('wsNext', {'requestId': id});
    expect(bridge.permitsAuthentication('signEvent', auth), isTrue);
    expect(
        bridge.permitsAuthentication(
            'signEvent',
            event(22242, [
              ['relay', url],
              ['challenge', 'wrong']
            ])),
        isFalse);
    await rpc('disconnect', {});
    expect(bridge.grantEpoch, greaterThan(epoch));
    expect(bridge.permitsAuthentication('signEvent', auth), isFalse);
    expect(bridge.permitsAuthentication('signEvent', http), isFalse);
    bridge.close();
  });
  test('denial not reprompted and stale consent cannot activate', () async {
    var prompts = 0;
    final gate = Completer<bool>();
    final bridge = GraspFipsBrowserBridge(
        pageOrigin: 'https://app.example',
        approve: (_) {
          prompts++;
          return gate.future;
        },
        prepare: (_) async => null,
        reply: (_) async {});
    final token =
        RegExp(r'const token = "([^"]+)"').firstMatch(bridge.script)!.group(1);
    final call = bridge.receive(jsonEncode({
      'token': token,
      'id': '1',
      'method': 'connect',
      'params': {'endpoint': endpoint}
    }));
    bridge.close();
    gate.complete(true);
    await call;
    expect(bridge.endpoint, isNull);
    expect(prompts, 1);
    final denied = GraspFipsBrowserBridge(
        pageOrigin: 'https://app.example',
        approve: (_) async {
          prompts++;
          return false;
        },
        prepare: (_) async => null,
        reply: (_) async {});
    final dt =
        RegExp(r'const token = "([^"]+)"').firstMatch(denied.script)!.group(1);
    for (var i = 0; i < 2; i++) {
      await denied.receive(jsonEncode({
        'token': dt,
        'id': '$i',
        'method': 'connect',
        'params': {'endpoint': endpoint}
      }));
    }
    expect(prompts, 2);
    denied.close();
  });
}
