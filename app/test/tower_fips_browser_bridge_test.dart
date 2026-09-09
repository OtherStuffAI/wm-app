import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wingman_app/src/features/browser/tower_fips_browser_bridge.dart';
import 'package:wingman_app/src/features/browser/tower_pairing_store.dart';
import 'package:wingman_app/src/core/tower_fips_proxy.dart';

const endpoint =
    'http://npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98.fips:8787';
const page = 'https://flightdeck.example',
    tower = 'npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98';
void main() {
  test(
      'manual grants are scoped to page, Tower, endpoint and identity, and revoked',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = TowerPairingStore();
    await store.grant(page, tower, endpoint, 'identity-a');
    expect(await store.contains(page, tower, endpoint, 'identity-a'), true);
    expect(await store.contains('$page.evil', tower, endpoint, 'identity-a'),
        false);
    expect(
        await store.contains(
            page, 'https://other.example', endpoint, 'identity-a'),
        false);
    expect(
        await store.contains(page, tower, '$endpoint/x', 'identity-a'), false);
    expect(await store.contains(page, tower, endpoint, 'identity-b'), false);
    await store.remove(page, tower, endpoint, 'identity-a');
    expect(await store.contains(page, tower, endpoint, 'identity-a'), false);
  });
  test(
      'mesh identity probe gates signing, mismatch revokes and reconnect verifies again',
      () async {
    const service =
        'npub1xs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6qqcvexj';
    var healthIdentity = tower,
        healthReads = 0,
        approved = false,
        revocations = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      expect(r.uri.path, '/health');
      healthReads++;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode({'service_npub': healthIdentity}));
      await r.response.close();
    });
    final replies = <String>[];
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (e, s) async {
          expect(s, service);
          return approved;
        },
        unpair: (e, s) async {
          revocations++;
        },
        prepare: (_) async => null,
        bindProxy: (e, p) => TowerFipsProxy.bind(
            endpoint: e,
            pageOrigin: p,
            clientFactory: () => HttpClient()
              ..connectionFactory = (url, host, port) {
                if (!url.host.endsWith('.fips')) {
                  throw StateError('HTTPS unavailable');
                }
                return Socket.startConnect(
                    InternetAddress.loopbackIPv4, server.port);
              }),
        reply: (s) async {
          replies.add(s);
        });
    final token = bridge.signingDocumentToken;
    Future<void> connect() => bridge.receive(jsonEncode({
          'token': token,
          'id': 'pair',
          'method': 'connect',
          'params': {'endpoint': endpoint, 'serviceNpub': service}
        }));
    try {
      await connect();
      expect(healthReads, 0, reason: 'No network or signing before approval');
      expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), false);
      approved = true;
      await connect();
      expect(healthReads, 1);
      expect(revocations, 1);
      expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), false);
      healthIdentity = service;
      await connect();
      expect(healthReads, 2);
      expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), true);
      expect(bridge.permitsMeshSigning(token, 'https://tower.example/api/read'),
          false);
      await bridge.receive(
          jsonEncode({'token': token, 'id': 'off', 'method': 'disconnect'}));
      expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), false);
      await connect();
      expect(healthReads, 3, reason: 'Reconnect revalidates identity on mesh');
      expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), true);
    } finally {
      bridge.close();
      await server.close(force: true);
    }
  });

  test(
      'mesh npub checksum and deterministic address pin match FIPS public node',
      () {
    expect(
        TowerFipsProxy.meshAddress(
                'http://npub109684nue495hq240u3dqzyf2kltk23u3mqkk9l44ga6szed4jcysramf74.fips:43100')
            .address,
        'fd87:f2eb:de48:6212:be46:3c95:4494:49ec');
    expect(
        () => TowerFipsProxy.validateEndpoint(
            endpoint.replaceFirst('zel98', 'zel99')),
        throwsFormatException);
  });
  test(
      'closing during mesh health cancels the pending probe before its timeout',
      () async {
    final received = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) {
      received.complete();
    });
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (_, __) async => true,
        prepare: (_) async => null,
        bindProxy: (e, p) => TowerFipsProxy.bind(
            endpoint: e,
            pageOrigin: p,
            clientFactory: () => HttpClient()
              ..connectionFactory = (u, h, p) => Socket.startConnect(
                  InternetAddress.loopbackIPv4, server.port)),
        reply: (_) async {});
    try {
      final connecting = bridge.receive(jsonEncode({
        'token': bridge.signingDocumentToken,
        'id': 'pair',
        'method': 'connect',
        'params': {'endpoint': endpoint, 'serviceNpub': tower}
      }));
      await received.future.timeout(const Duration(seconds: 2));
      bridge.close();
      await connecting.timeout(const Duration(seconds: 2));
      expect(
          bridge.permitsMeshSigning(
              bridge.signingDocumentToken, '$endpoint/api/read'),
          false);
    } finally {
      bridge.close();
      await server.close(force: true);
    }
  });

  test(
      'forged document token and invalid service identity never prompt or prepare',
      () async {
    var approvals = 0, readiness = 0;
    final replies = <String>[];
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (_, __) async {
          approvals++;
          return true;
        },
        prepare: (_) async {
          readiness++;
          return null;
        },
        reply: (value) async {
          replies.add(value);
        });
    final token = jsonDecode(
        RegExp(r'const token = (.*);').firstMatch(bridge.script)!.group(1)!);
    await bridge.receive(jsonEncode({
      'token': 'forged',
      'id': '1',
      'method': 'connect',
      'params': {'endpoint': endpoint, 'serviceNpub': tower}
    }));
    expect(replies, isEmpty);
    await bridge.receive(jsonEncode({
      'token': token,
      'id': '2',
      'method': 'connect',
      'params': {'endpoint': endpoint, 'serviceNpub': 'https://evil.example'}
    }));
    expect(approvals, 0);
    expect(readiness, 0);
    expect(replies.single, contains('failed'));
    bridge.close();
  });
  test('close during pending approval cannot resurrect a proxy', () async {
    final approval = Completer<bool>();
    var readiness = 0, binds = 0;
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (_, __) => approval.future,
        prepare: (_) async {
          readiness++;
          return null;
        },
        bindProxy: (e, p) async {
          binds++;
          return TowerFipsProxy.bind(endpoint: e, pageOrigin: p);
        },
        reply: (_) async {});
    final token = jsonDecode(
        RegExp(r'const token = (.*);').firstMatch(bridge.script)!.group(1)!);
    final result = bridge.receive(jsonEncode({
      'token': token,
      'id': '1',
      'method': 'connect',
      'params': {'endpoint': endpoint, 'serviceNpub': tower}
    }));
    bridge.close();
    approval.complete(true);
    await result;
    expect(readiness, 0);
    expect(binds, 0);
  });
  test('readiness failure never creates a route or falls back', () async {
    var binds = 0;
    final replies = <String>[];
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (_, __) async => true,
        prepare: (_) async => 'Mesh unavailable',
        bindProxy: (e, p) async {
          binds++;
          return TowerFipsProxy.bind(endpoint: e, pageOrigin: p);
        },
        reply: (s) async {
          replies.add(s);
        });
    final token = jsonDecode(
        RegExp(r'const token = (.*);').firstMatch(bridge.script)!.group(1)!);
    await bridge.receive(jsonEncode({
      'token': token,
      'id': '1',
      'method': 'connect',
      'params': {'endpoint': endpoint, 'serviceNpub': tower}
    }));
    expect(binds, 0);
    expect(replies.single, contains('No public fallback'));
    bridge.close();
  });
}
