import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wingman_app/src/core/app_config.dart';
import 'package:wingman_app/src/core/nostr_crypto.dart';
import 'package:wingman_app/src/features/drive/drive_host.dart';

void main() {
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
