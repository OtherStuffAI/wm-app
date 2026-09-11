// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wingman_app/src/core/app_config.dart';
import 'package:wingman_app/src/core/fips_runtime_service.dart';
import 'package:wingman_app/src/core/native_core_bridge.dart';
import 'package:wingman_app/src/core/nostr_crypto.dart';
import 'package:wingman_app/src/features/drive/drive_host.dart';
import 'package:wingman_app/src/features/drive/drive_protocol.dart';
import 'package:wingman_app/src/features/drive/drive_screen.dart';

void main() {
  test('default host identity storage uses non-data-protection macOS keychain',
      () async {
    SharedPreferences.setMockInitialValues({DriveHost.storageKey: '[]'});
    final previousStoragePlatform = FlutterSecureStoragePlatform.instance;
    final previousTargetPlatform = debugDefaultTargetPlatformOverride;
    final storage = _RecordingSecureStoragePlatform({});
    FlutterSecureStoragePlatform.instance = storage;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final owner = NostrCrypto.generateIdentity();
    final service = NostrCrypto.generateIdentity();
    final host = DriveHost(
      endpointLoader: () async => 'http://${service.npub}.fips:7345',
      listenAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
    );
    final config = AppConfig.defaults().copyWith(
      deviceNpub: owner.npub,
      deviceSecret: owner.nsec,
      towerUrl: 'https://tower.example',
      workspaceId: 'workspace',
    );

    try {
      await host.configure(config);

      expect(host.listeningPort, isNotNull, reason: host.message);
      expect(storage.reads, hasLength(1));
      expect(storage.reads.single.key, DriveHost.hostIdentityStorageKey);
      expect(
          storage.reads.single.options['usesDataProtectionKeychain'], 'false');
      expect(storage.writes, hasLength(1));
      expect(storage.writes.single.key, DriveHost.hostIdentityStorageKey);
      expect(
          storage.writes.single.options['usesDataProtectionKeychain'], 'false');
      expect(storage.data[DriveHost.hostIdentityStorageKey], isNotNull);
    } finally {
      await host.stop();
      host.dispose();
      debugDefaultTargetPlatformOverride = previousTargetPlatform;
      FlutterSecureStoragePlatform.instance = previousStoragePlatform;
    }
  });

  test('default host identity storage preserves an existing host key',
      () async {
    SharedPreferences.setMockInitialValues({DriveHost.storageKey: '[]'});
    final previousStoragePlatform = FlutterSecureStoragePlatform.instance;
    final previousTargetPlatform = debugDefaultTargetPlatformOverride;
    final existing = NostrCrypto.generateIdentity();
    final storage = _RecordingSecureStoragePlatform({
      DriveHost.hostIdentityStorageKey: existing.nsec,
    });
    FlutterSecureStoragePlatform.instance = storage;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final owner = NostrCrypto.generateIdentity();
    final service = NostrCrypto.generateIdentity();
    final host = DriveHost(
      endpointLoader: () async => 'http://${service.npub}.fips:7345',
      listenAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
    );
    final config = AppConfig.defaults().copyWith(
      deviceNpub: owner.npub,
      deviceSecret: owner.nsec,
      towerUrl: 'https://tower.example',
      workspaceId: 'workspace',
    );

    try {
      await host.configure(config);

      expect(host.listeningPort, isNotNull, reason: host.message);
      expect(storage.writes, isEmpty);
      expect(storage.data[DriveHost.hostIdentityStorageKey], existing.nsec);
    } finally {
      await host.stop();
      host.dispose();
      debugDefaultTargetPlatformOverride = previousTargetPlatform;
      FlutterSecureStoragePlatform.instance = previousStoragePlatform;
    }
  });

  test('publish signs the normalized Tower registration contract', () async {
    SharedPreferences.setMockInitialValues({DriveHost.storageKey: '[]'});
    final owner = NostrCrypto.generateIdentity();
    final service = NostrCrypto.generateIdentity();
    Map<String, dynamic>? capturedPayload;
    String? capturedUrl;
    String? capturedMethod;
    String? capturedSecret;
    final host = DriveHost(
      identityLoader: () async => service,
      endpointLoader: () async => 'http://${service.npub}.fips:7345',
      listenAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      towerRequest: (url, method, secret, payload) async {
        capturedUrl = url;
        capturedMethod = method;
        capturedSecret = secret;
        capturedPayload = payload;
        return {
          'share': {'revision': 1}
        };
      },
    );
    final config = AppConfig.defaults().copyWith(
      deviceNpub: owner.npub,
      deviceSecret: owner.nsec,
      towerUrl: 'https://tower.example',
      workspaceId: 'workspace',
    );
    final share = <String, dynamic>{
      'id': '00000000-0000-4000-8000-000000000001',
      'root': '/tmp/root',
      'tower': config.towerUrl,
      'workspace_id': config.workspaceId,
      'owner_npub': owner.npub,
      'name': '  Folder  ',
      'host_name': '  Desktop  ',
      'audience': 'private',
      'enabled': true,
      'published': false,
      'revision': 0,
    };

    try {
      await host.configure(config);
      await host.publish(share);

      final payload = capturedPayload!;
      final registration = Map<String, dynamic>.from(payload)
        ..remove('host_proof');
      expect(capturedUrl,
          'https://tower.example/api/v4/flightdeck-pg/workspaces/workspace/drive/shares/${share['id']}');
      expect(capturedMethod, 'PUT');
      expect(capturedSecret, owner.nsec);
      expect(registration, {
        'name': 'Folder',
        'host_name': 'Desktop',
        'host_npub': service.npub,
        'endpoint': 'http://${service.npub}.fips:7345',
        'audience': 'private',
        'enabled': true,
        'previous_revision': 0,
      });
      final proof = payload['host_proof'] as Map<String, dynamic>;
      expect(proof['kind'], 27235);
      expect(proof['content'], '');
      expect(proof['pubkey'], service.publicKeyHex);
      expect(proof['tags'], [
        ['protocol', 'fips-drive-register-v1'],
        ['u', capturedUrl],
        ['owner', owner.npub],
        [
          'payload',
          sha256.convert(utf8.encode(jsonEncode(registration))).toString()
        ],
      ]);
      expect(share['name'], 'Folder');
      expect(share['host_name'], 'Desktop');
      expect(share['published'], isTrue);
      expect(host.registrationStatus(share), 'Sharing');
    } finally {
      await host.stop();
      host.dispose();
    }
  });

  test('publish preserves selected share and surfaces Tower status code',
      () async {
    SharedPreferences.setMockInitialValues({DriveHost.storageKey: '[]'});
    final owner = NostrCrypto.generateIdentity();
    final service = NostrCrypto.generateIdentity();
    final host = DriveHost(
      identityLoader: () async => service,
      endpointLoader: () async => 'http://${service.npub}.fips:7345',
      listenAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      towerRequest: (url, method, secret, payload) async {
        throw const DriveTowerException(
            400, {'code': 'invalid_host_proof'}, '');
      },
    );
    final config = AppConfig.defaults().copyWith(
      deviceNpub: owner.npub,
      deviceSecret: owner.nsec,
      towerUrl: 'https://tower.example',
      workspaceId: 'workspace',
    );
    final share = <String, dynamic>{
      'id': '00000000-0000-4000-8000-000000000002',
      'root': '/tmp/root',
      'tower': config.towerUrl,
      'workspace_id': config.workspaceId,
      'owner_npub': owner.npub,
      'name': 'Folder',
      'host_name': 'Desktop',
      'audience': 'private',
      'enabled': true,
      'published': false,
      'revision': 0,
    };

    try {
      await host.configure(config);

      await expectLater(
          host.publish(share),
          throwsA(isA<DriveTowerException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.safeMessage, 'safeMessage',
                  'Tower returned HTTP 400 (invalid_host_proof)')));
      expect(share['published'], isFalse);
      expect(share['last_registration_error'],
          'Tower returned HTTP 400 (invalid_host_proof)');
      expect(host.registrationStatus(share),
          'Registration failed: Tower returned HTTP 400 (invalid_host_proof)');
    } finally {
      await host.stop();
      host.dispose();
    }
  });

  test('publish requires the direct owner identity before Tower mutation',
      () async {
    SharedPreferences.setMockInitialValues({DriveHost.storageKey: '[]'});
    final owner = NostrCrypto.generateIdentity();
    final other = NostrCrypto.generateIdentity();
    final service = NostrCrypto.generateIdentity();
    var towerCalls = 0;
    final host = DriveHost(
      identityLoader: () async => service,
      endpointLoader: () async => 'http://${service.npub}.fips:7345',
      listenAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      towerRequest: (url, method, secret, payload) async {
        towerCalls += 1;
        return {
          'share': {'revision': 1}
        };
      },
    );
    final config = AppConfig.defaults().copyWith(
      deviceNpub: owner.npub,
      deviceSecret: other.nsec,
      towerUrl: 'https://tower.example',
      workspaceId: 'workspace',
    );
    final share = <String, dynamic>{
      'id': '00000000-0000-4000-8000-000000000003',
      'root': '/tmp/root',
      'tower': config.towerUrl,
      'workspace_id': config.workspaceId,
      'owner_npub': owner.npub,
      'name': 'Folder',
      'host_name': 'Desktop',
      'audience': 'private',
      'enabled': true,
      'published': false,
      'revision': 0,
    };

    try {
      await host.configure(config);

      await expectLater(
          host.publish(share),
          throwsA(isA<DriveRegistrationException>().having(
              (e) => e.message,
              'message',
              'Drive registration requires the unlocked owner identity for this workspace.')));
      expect(towerCalls, 0);
      expect(share['published'], isFalse);
      expect(share['last_registration_error'],
          'Drive registration requires the unlocked owner identity for this workspace.');
      expect(host.registrationStatus(share),
          'Registration failed: Drive registration requires the unlocked owner identity for this workspace.');
    } finally {
      await host.stop();
      host.dispose();
    }
  });

  test('startup passively reports missing FIPS identity and retry recovers',
      () async {
    SharedPreferences.setMockInitialValues({DriveHost.storageKey: '[]'});
    final owner = NostrCrypto.generateIdentity();
    final service = NostrCrypto.generateIdentity();
    final statuses = <FipsRuntimeStatus>[
      const FipsRuntimeStatus(
        state: FipsRuntimeState.controlAccessPending,
        detail: 'control permission pending',
      ),
      FipsRuntimeStatus(
        state: FipsRuntimeState.running,
        detail: 'FIPS is running.',
        nodeNpub: service.npub,
      ),
    ];
    final host = DriveHost(
      fipsRuntime: _FakeFipsRuntimeService(statuses),
      identityLoader: () async => service,
      listenAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
    );
    final config = AppConfig.defaults().copyWith(
      deviceNpub: owner.npub,
      deviceSecret: owner.nsec,
      towerUrl: 'https://tower.example',
      workspaceId: 'workspace',
    );

    try {
      await host.configure(config);
      expect(host.listeningPort, isNull);
      expect(host.endpoint, isNull);
      expect(host.message, contains('cannot read this machine FIPS identity'));
      expect(host.message, contains('Log out and back in, then retry'));
      expect(host.message, isNot(contains('authorization')));

      await host.configure(config, repair: true);
      expect(host.endpoint, 'http://${service.npub}.fips:7345');
      expect(host.listeningPort, isNotNull);
      expect(host.message,
          'Hosting selected folders while WM App is running and unlocked.');
    } finally {
      await host.stop();
      host.dispose();
    }
  });

  testWidgets('Drive screen disposal stops its owned host', (tester) async {
    final host = _CountingDriveHost();

    await tester.pumpWidget(MaterialApp(
      home: DriveScreen(
        config: AppConfig.defaults(),
        bridge: NativeCoreBridge(),
        host: host,
      ),
    ));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(host.configureCount, 1);
    expect(host.disposed, isTrue);
  });

  test('initial configure is passive; explicit retry uses readiness repair',
      () async {
    SharedPreferences.setMockInitialValues({DriveHost.storageKey: '[]'});
    final owner = NostrCrypto.generateIdentity();
    final service = NostrCrypto.generateIdentity();
    final runtime = _FakeFipsRuntimeService([
      const FipsRuntimeStatus(
        state: FipsRuntimeState.installRequired,
        detail: 'mesh setup is missing or outdated',
      ),
      FipsRuntimeStatus(
        state: FipsRuntimeState.running,
        detail: 'FIPS is running.',
        nodeNpub: service.npub,
      ),
    ]);
    final host = DriveHost(
      fipsRuntime: runtime,
      identityLoader: () async => service,
      listenAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
    );
    final config = AppConfig.defaults().copyWith(
      deviceNpub: owner.npub,
      deviceSecret: owner.nsec,
      towerUrl: 'https://tower.example',
      workspaceId: 'workspace',
    );

    try {
      await host.configure(config);
      expect(runtime.inspectCount, 1);
      expect(runtime.ensureReadyCount, 0);
      expect(host.listeningPort, isNull);
      expect(host.message, contains('FIPS is not ready'));

      await host.configure(config, repair: true);
      expect(runtime.ensureReadyCount, 1);
      expect(host.listeningPort, isNotNull);
      expect(host.message,
          'Hosting selected folders while WM App is running and unlocked.');
    } finally {
      await host.stop();
      host.dispose();
    }
  });

  test('stale failed configure does not stop a newer active host', () async {
    SharedPreferences.setMockInitialValues({DriveHost.storageKey: '[]'});
    final owner = NostrCrypto.generateIdentity();
    final service = NostrCrypto.generateIdentity();
    final firstEndpoint = Completer<String>();
    var endpointCalls = 0;
    final host = DriveHost(
      identityLoader: () async => service,
      endpointLoader: () {
        endpointCalls += 1;
        if (endpointCalls == 1) return firstEndpoint.future;
        return Future.value('http://${service.npub}.fips:7345');
      },
      listenAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
    );
    final config = AppConfig.defaults().copyWith(
      deviceNpub: owner.npub,
      deviceSecret: owner.nsec,
      towerUrl: 'https://tower.example',
      workspaceId: 'workspace',
    );

    try {
      final stale = host.configure(config);
      await Future<void>.delayed(Duration.zero);
      await host.configure(config.copyWith(workspaceId: 'workspace-new'));
      final activePort = host.listeningPort;
      expect(activePort, isNotNull);

      firstEndpoint.completeError(const SocketException('stale bind failure'));
      await stale;

      expect(host.listeningPort, activePort);
      expect(host.message,
          'Hosting selected folders while WM App is running and unlocked.');
    } finally {
      await host.stop();
      host.dispose();
    }
  });

  test(
      'live loopback host reads selected files; denies private members, replay/restart, stale policy and local disable',
      () async {
    final root = await Directory.systemTemp.createTemp('drive-host-');
    final realRoot = await root.resolveSymbolicLinks();
    final bytes = List.generate(160000, (i) => i % 251);
    await File('$realRoot/file.bin').writeAsBytes(bytes);
    final owner = NostrCrypto.generateIdentity(),
        member = NostrCrypto.generateIdentity(),
        service = NostrCrypto.generateIdentity();
    final endpoint = 'http://${service.npub}.fips:7345';
    var now = DateTime.now();
    var unavailable = false, mismatch = false;
    var endpointReady = false;
    final share = <String, dynamic>{
      'id': 'share',
      'root': realRoot,
      'tower': 'https://tower.example',
      'workspace_id': 'workspace',
      'owner_npub': owner.npub,
      'name': 'Folder',
      'host_name': 'Desktop',
      'audience': 'private',
      'enabled': true,
      'revision': 1
    };
    SharedPreferences.setMockInitialValues({
      DriveHost.storageKey: jsonEncode([share])
    });
    final config = AppConfig.defaults().copyWith(
        deviceNpub: owner.npub,
        deviceSecret: owner.nsec,
        towerUrl: 'https://tower.example',
        workspaceId: 'workspace');
    DriveHost create() => DriveHost(
        identityLoader: () async => service,
        endpointLoader: () async {
          if (!endpointReady) throw StateError('starting');
          return endpoint;
        },
        listenAddress: InternetAddress.loopbackIPv4,
        listenPort: 0,
        helperPath:
            '${Directory.current.parent.path}/target/release/wmapp-drive-fs',
        now: () => now,
        towerRequest: (url, method, secret, payload) async {
          if (unavailable) throw const SocketException('offline');
          if (method == 'PUT') {
            return {
              'share': {'revision': 2}
            };
          }
          return {
            'workspace_id': 'workspace',
            'share': {
              'id': 'share',
              'host_npub': service.npub,
              'endpoint': mismatch ? 'http://different.fips:7345' : endpoint,
              'enabled': true
            },
            'allowed_npubs': [owner.npub],
            'policy_revision': 'one',
            'max_age_seconds': 900
          };
        });
    var host = create();
    await host.configure(config);
    expect(host.listeningPort, isNull);
    endpointReady = true;
    await host.configure(config);
    expect(host.listeningPort, isNotNull, reason: host.message);
    var sequence = 0;
    String auth(String path, NostrIdentity user) {
      final event = NostrCrypto.signEvent(secret: user.nsec, event: {
        'kind': 27235,
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'content': '',
        'tags': [
          ['u', '$endpoint$path'],
          ['method', 'GET'],
          ['workspace', 'workspace'],
          ['share', 'share'],
          ['nonce', '${sequence++}'.padLeft(32, 'a')]
        ]
      });
      return 'Nostr ${base64Encode(utf8.encode(jsonEncode(event)))}';
    }

    final client = HttpClient();
    Future<(int, List<int>)> get(String path, String authorization) async {
      final r = await client
          .getUrl(Uri.parse('http://127.0.0.1:${host.listeningPort}$path'));
      r.headers.set('authorization', authorization);
      final response = await r.close();
      final data = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      return (response.statusCode, data);
    }

    try {
      const path = '/drive/v1/share/list?path=';
      final signed = auth(path, owner);
      final listing = await get(path, signed);
      expect(listing.$1, 200);
      final value = jsonDecode(utf8.decode(listing.$2));
      expect(value['entries'][0]['name'], 'file.bin');
      expect((await get(path, auth(path, member))).$1, 403);
      final replayBefore = (await SharedPreferences.getInstance())
          .getString('wingman.drive.replay.v1');
      // More distinct valid-but-unauthorized signatures than the replay capacity
      // must not reserve memory/disk entries or deny a subsequent owner request.
      for (var attempt = 0; attempt < 8193; attempt++) {
        expect((await get(path, auth(path, member))).$1, 403);
      }
      expect(
          (await SharedPreferences.getInstance())
              .getString('wingman.drive.replay.v1'),
          replayBefore);
      expect((await get(path, auth(path, owner))).$1, 200);

      expect((await get(path, signed)).$1, 401);
      final read =
          '/drive/v1/share/read?path=file.bin&revision=${value['entries'][0]['revision']}';
      expect((await get(read, auth(read, owner))).$2, bytes);
      await File('$realRoot/file.bin').writeAsString('changed');
      expect((await get(read, auth(read, owner))).$1, 409);
      await host.stop();
      host.dispose();
      host = create();
      await host.configure(config);
      expect((await get(path, signed)).$1, 401);
      unavailable = true;
      now = now.add(const Duration(minutes: 15));
      await host.refreshPolicies();
      expect((await get(path, auth(path, owner))).$1, 403);
      unavailable = false;
      await host.refreshPolicies();
      expect((await get(path, auth(path, owner))).$1, 200);
      mismatch = true;
      await host.refreshPolicies();
      expect((await get(path, auth(path, owner))).$1, 403);
      final prefs = await SharedPreferences.getInstance();
      expect(
          (jsonDecode(prefs.getString(DriveHost.storageKey)!)[0] as Map)
              .containsKey('policy'),
          false);
      await host.stop();
      host.dispose();
      unavailable = true;
      host = create();
      await host.configure(config);
      expect((await get(path, auth(path, owner))).$1, 403);
      mismatch = false;
      unavailable = false;
      await host.refreshPolicies();
      expect((await get(path, auth(path, owner))).$1, 200);
      await host.disable(host.visible.first);
      expect((await get(path, auth(path, owner))).$1, 404);
    } finally {
      client.close(force: true);
      await host.stop();
      host.dispose();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class _SecureStorageCall {
  const _SecureStorageCall(this.key, this.options);

  final String key;
  final Map<String, String> options;

  @override
  String toString() => '_SecureStorageCall($key, $options)';
}

class _RecordingSecureStoragePlatform extends TestFlutterSecureStoragePlatform {
  _RecordingSecureStoragePlatform(super.data);

  final reads = <_SecureStorageCall>[];
  final writes = <_SecureStorageCall>[];

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) {
    reads.add(_SecureStorageCall(key, Map<String, String>.from(options)));
    return super.read(key: key, options: options);
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) {
    writes.add(_SecureStorageCall(key, Map<String, String>.from(options)));
    return super.write(key: key, value: value, options: options);
  }
}

class _CountingDriveHost extends DriveHost {
  var configureCount = 0;
  var disposed = false;

  @override
  Future<void> configure(AppConfig config, {bool repair = false}) async {
    configureCount += 1;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _FakeFipsRuntimeService extends FipsRuntimeService {
  _FakeFipsRuntimeService(this.statuses)
      : super(
          isMacOS: true,
          fileExists: (_) async => true,
        );

  final List<FipsRuntimeStatus> statuses;
  var inspectCount = 0;
  var ensureReadyCount = 0;

  FipsRuntimeStatus _nextStatus() {
    if (statuses.length > 1) return statuses.removeAt(0);
    return statuses.single;
  }

  @override
  Future<FipsRuntimeStatus> inspect() async {
    inspectCount += 1;
    return _nextStatus();
  }

  @override
  Future<FipsRuntimeStatus> ensureReadyForAppAccess() async {
    ensureReadyCount += 1;
    return _nextStatus();
  }
}
