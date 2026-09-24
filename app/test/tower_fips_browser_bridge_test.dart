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
const installation =
    'npub1xs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6rgdp5xs6qqcvexj';
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
      'v2 binds transport without root health and permits the advertised owner health route',
      () async {
    const healthPath = '/api/owners/npub1owner/control-plane/v1/health';
    var approved = false, revocations = 0;
    final requestedPaths = <String>[];
    final events = <Map<String, Object?>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      requestedPaths.add(r.uri.path);
      expect(r.uri.path, healthPath);
      expect(r.headers.value(HttpHeaders.authorizationHeader), 'Nostr signed');
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode({'installation_npub': installation}));
      await r.response.close();
    });
    final replies = <String>[];
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (e, s) async {
          expect(s, tower);
          return approved;
        },
        unpair: (e, s) async {
          expect(s, tower);
          revocations++;
        },
        diagnostic: events.add,
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
          'params': {
            'endpoint': endpoint,
            'serviceNpub': tower,
            'installationNpub': installation,
          }
        }));
    try {
      await connect();
      expect(requestedPaths, isEmpty,
          reason: 'No network or signing before approval');
      expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), false);
      approved = true;
      await connect();
      expect(requestedPaths, isEmpty,
          reason: 'Agent Connect v2 must not probe an invented root /health');
      expect(revocations, 0);
      expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), true);
      expect(replies.last, contains('"serviceNpub":"$tower"'));
      expect(replies.last, isNot(contains(installation)));
      expect(
          events,
          contains(predicate<Map<String, Object?>>((event) =>
              event['stage'] == 'transport_identity_compared' &&
              event['matches'] == true)));
      expect(
          events,
          contains(predicate<Map<String, Object?>>((event) =>
              event['stage'] == 'installation_identity_validated' &&
              event['contract'] == 'v2' &&
              event['differsFromTransport'] == true)));
      expect(
          events,
          contains(predicate<Map<String, Object?>>((event) =>
              event['stage'] == 'authenticated_health_delegated' &&
              event['owner'] == 'flight_deck' &&
              event['contract'] == 'v2')));
      await bridge.receive(jsonEncode({
        'token': token,
        'id': 'open-health',
        'method': 'open',
        'params': {
          'url': '$endpoint$healthPath',
          'method': 'GET',
          'headers': {'Authorization': 'Nostr signed'},
        },
      }));
      final requestId = jsonDecode(
              RegExp(r',("[^"]+"),null\)$').firstMatch(replies.last)!.group(1)!)
          as String;
      await bridge.receive(jsonEncode({
        'token': token,
        'id': 'finish-health',
        'method': 'finish',
        'params': {'requestId': requestId},
      }));
      expect(requestedPaths, [healthPath]);
      expect(requestedPaths, isNot(contains('/health')));
      expect(bridge.permitsMeshSigning(token, 'https://tower.example/api/read'),
          false);
      await bridge.receive(
          jsonEncode({'token': token, 'id': 'off', 'method': 'disconnect'}));
      expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), false);
      await connect();
      expect(requestedPaths, [healthPath],
          reason: 'Reconnect still must not invent a root health request');
      expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), true);
    } finally {
      bridge.close();
      await server.close(force: true);
    }
  });

  test('legacy v1 without installationNpub verifies service_npub', () async {
    var healthReads = 0;
    final replies = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      healthReads++;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode({'service_npub': tower}));
      await r.response.close();
    });
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (_, identity) async => identity == tower,
        prepare: (_) async => null,
        bindProxy: (e, p) => TowerFipsProxy.bind(
            endpoint: e,
            pageOrigin: p,
            clientFactory: () => HttpClient()
              ..connectionFactory = (url, host, port) => Socket.startConnect(
                  InternetAddress.loopbackIPv4, server.port)),
        reply: (value) async => replies.add(value));
    try {
      await bridge.receive(jsonEncode({
        'token': bridge.signingDocumentToken,
        'id': 'legacy',
        'method': 'connect',
        'params': {'endpoint': endpoint, 'serviceNpub': tower},
      }));
      expect(healthReads, 1);
      expect(replies.single, contains('"serviceNpub":"$tower"'));
      expect(
          bridge.permitsMeshSigning(
              bridge.signingDocumentToken, '$endpoint/api/read'),
          true);
    } finally {
      bridge.close();
      await server.close(force: true);
    }
  });

  test('v2 transport binding does not duplicate installation validation',
      () async {
    var requests = 0;
    final replies = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      requests++;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode({
        'installation_npub': tower,
        'service_npub': installation,
      }));
      await r.response.close();
    });
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (_, __) async => true,
        prepare: (_) async => null,
        bindProxy: (e, p) => TowerFipsProxy.bind(
            endpoint: e,
            pageOrigin: p,
            clientFactory: () => HttpClient()
              ..connectionFactory = (url, host, port) => Socket.startConnect(
                  InternetAddress.loopbackIPv4, server.port)),
        reply: (value) async => replies.add(value));
    try {
      await bridge.receive(jsonEncode({
        'token': bridge.signingDocumentToken,
        'id': 'v2-mismatch',
        'method': 'connect',
        'params': {
          'endpoint': endpoint,
          'serviceNpub': tower,
          'installationNpub': installation,
        },
      }));
      expect(requests, 0);
      expect(replies.single, contains('"serviceNpub":"$tower"'));
      expect(
          bridge.permitsMeshSigning(
              bridge.signingDocumentToken, '$endpoint/api/read'),
          true);
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
    await bridge.receive(jsonEncode({
      'token': token,
      'id': '3',
      'method': 'connect',
      'params': {'endpoint': endpoint, 'serviceNpub': installation}
    }));
    expect(approvals, 0);
    expect(readiness, 0);
    expect(replies, hasLength(2));
    expect(replies.first, contains('failed'));
    expect(replies.last, contains('transport_identity_mismatch'));
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
    expect(replies.single, contains('fips_not_ready'));
    bridge.close();
  });
  test('stalled readiness returns a bounded actionable pairing error',
      () async {
    final readiness = Completer<String?>();
    var binds = 0;
    final replies = <String>[];
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (_, __) async => true,
        prepare: (_) => readiness.future,
        connectPhaseTimeout: const Duration(milliseconds: 20),
        bindProxy: (e, p) async {
          binds++;
          return TowerFipsProxy.bind(endpoint: e, pageOrigin: p);
        },
        reply: (s) async {
          replies.add(s);
        });
    final token = bridge.signingDocumentToken;
    await bridge
        .receive(jsonEncode({
          'token': token,
          'id': 'stalled-readiness',
          'method': 'connect',
          'params': {'endpoint': endpoint, 'serviceNpub': tower}
        }))
        .timeout(const Duration(seconds: 1));
    expect(binds, 0);
    expect(replies.single, contains('fips_readiness_timeout'));
    expect(bridge.permitsMeshSigning(token, '$endpoint/api/read'), false);
    bridge.close();
  });

  test('page bridge bounds connect if the native callback is lost', () {
    final bridge = TowerFipsBrowserBridge(
        pageOrigin: page,
        approve: (_, __) async => true,
        prepare: (_) async => null,
        reply: (_) async {});
    expect(bridge.script, contains("method === 'connect' ? 120000 : 30000"));
    expect(bridge.script, contains('Tower pairing timed out. Check FIPS'));
    bridge.close();
  });

  test('connection diagnostics correlate safe stages without response bodies',
      () async {
    final events = <Map<String, Object?>>[];
    final replies = <String>[];
    final bridge = TowerFipsBrowserBridge(
      pageOrigin: page,
      approve: (_, __) async => true,
      prepare: (_) async => 'not ready',
      diagnostic: events.add,
      reply: (value) async => replies.add(value),
    );
    await bridge.receive(jsonEncode({
      'token': bridge.signingDocumentToken,
      'id': 'request',
      'method': 'connect',
      'params': {
        'endpoint': endpoint,
        'serviceNpub': tower,
        'correlationId': 'connect-test-1',
      },
    }));
    expect(
        events.map((event) => event['stage']),
        containsAllInOrder([
          'native_bridge_received',
          'endpoint_validated',
          'approval_resolved',
          'fips_readiness_started',
          'native_reply_delivered',
        ]));
    expect(events.every((event) => event['correlationId'] == 'connect-test-1'),
        true);
    expect(jsonEncode(events), isNot(contains('not ready')));
    expect(replies.single, contains('fips_not_ready'));
    bridge.close();
  });
}
