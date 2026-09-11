import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_config.dart';
import '../../core/nostr_crypto.dart';
import '../../core/tower_fips_proxy.dart';
import '../../core/fips_runtime_service.dart';
import 'drive_protocol.dart';

/// Desktop host. Keeps filesystem roots and OS grants exclusively on this machine.
class DriveHost extends ChangeNotifier {
  DriveHost(
      {this.identityLoader,
      this.endpointLoader,
      this.towerRequest,
      this.helperPath,
      this.listenAddress,
      this.listenPort = 7345,
      this.now = DateTime.now});
  final Future<NostrIdentity> Function()? identityLoader;
  final Future<String> Function()? endpointLoader;
  final Future<Map<String, dynamic>> Function(
      String, String, String, Map<String, dynamic>?)? towerRequest;
  final String? helperPath;
  final InternetAddress? listenAddress;
  final int listenPort;
  final DateTime Function() now;
  int? get listeningPort => _server?.port;

  static const channel = MethodChannel('au.com.otherstuff.wingman/drive');
  static const storageKey = 'wingman.drive.shares.v1';
  final List<Map<String, dynamic>> shares = [];
  final Map<String, DrivePolicy> _policies = {};
  final Map<String, Set<HttpResponse>> _active = {};
  final DriveRequestVerifier _verifier = DriveRequestVerifier();
  HttpServer? _server;
  Timer? _timer;
  AppConfig? _config;
  NostrIdentity? _hostIdentity;
  String message = 'Choose a folder to share from this desktop.';
  String? endpoint;
  bool _refreshing = false;
  int _generation = 0;
  bool get supported => !kIsWeb && (Platform.isMacOS || Platform.isLinux);

  Future<void> configure(AppConfig config) async {
    if (!supported) return;
    if (_server != null &&
        _config?.deviceNpub == config.deviceNpub &&
        _config?.deviceSecret == config.deviceSecret &&
        _config?.towerUrl == config.towerUrl &&
        _config?.workspaceId == config.workspaceId) {
      return;
    }
    final generation = ++_generation;
    await stop();
    _config = config;
    if (config.deviceSecret.isEmpty) {
      message = 'Unlock your identity to host folders.';
      notifyListeners();
      return;
    }
    try {
      if (identityLoader != null) {
        _hostIdentity = await identityLoader!();
      } else {
        const secure = FlutterSecureStorage();
        var secret = await secure.read(key: 'wingman.drive.host-key.v1');
        if (generation != _generation) return;
        secret ??= NostrCrypto.generateIdentity().nsec;
        await secure.write(key: 'wingman.drive.host-key.v1', value: secret);
        if (generation != _generation) return;
        _hostIdentity = NostrCrypto.importIdentity(secret);
      }
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(storageKey) ?? '[]') as List;
      if (generation != _generation) return;
      shares
        ..clear()
        ..addAll(saved.map((e) => (e as Map).cast<String, dynamic>()));
      for (final s in shares) {
        if (s['policy'] is Map && s['fetched_at'] is String) {
          _policies[s['id']] = DrivePolicy(
              (s['policy'] as Map).cast<String, dynamic>(),
              DateTime.parse(s['fetched_at']));
        }
        if (Platform.isMacOS && s['bookmark'] != null) {
          try {
            s['root'] =
                await channel.invokeMethod<String>('restore', s['bookmark']);
          } catch (_) {
            s['enabled'] = false;
          }
        }
      }
      if (endpointLoader != null) {
        endpoint = await endpointLoader!();
      } else {
        final status = await FipsRuntimeService().inspect();
        if (status.nodeNpub == null) {
          throw StateError('FIPS identity unavailable');
        }
        endpoint = 'http://${status.nodeNpub}.fips:7345';
      }
      if (generation != _generation) return;
      _server = await HttpServer.bind(
          listenAddress ?? TowerFipsProxy.meshAddress(endpoint!), listenPort);
      if (generation != _generation) {
        await stop();
        return;
      }
      _server!.idleTimeout = const Duration(seconds: 30);
      _server!.listen(_serve);
      _timer = Timer.periodic(
          const Duration(seconds: 30), (_) => unawaited(refreshPolicies()));
      await refreshPolicies();
      message =
          'Hosting selected folders while WM App is running and unlocked.';
    } catch (_) {
      message =
          'Hosting unavailable. Check FIPS and folder access, then retry.';
    }
    notifyListeners();
  }

  bool _owns(Map s) =>
      s['owner_npub'] == _config?.deviceNpub &&
      s['tower'] == _config?.towerUrl &&
      s['workspace_id'] == _config?.workspaceId;
  List<Map<String, dynamic>> get visible => shares.where(_owns).toList();
  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(storageKey, jsonEncode(shares));
  }

  Future<void> add(String name, String audience, String hostName) async {
    if (endpoint == null ||
        _server == null ||
        _config?.deviceSecret.isEmpty != false) {
      throw StateError('Host unavailable');
    }
    final generation = _generation;
    String? root;
    String? bookmark;
    if (Platform.isMacOS) {
      final picked = await channel.invokeMapMethod<String, dynamic>('pick');
      root = picked?['path'];
      bookmark = picked?['bookmark'];
    } else {
      root = await getDirectoryPath(confirmButtonText: 'Share folder');
    }
    if (root == null || generation != _generation) return;
    final bytes = NostrCrypto.generateIdentity().publicKeyHex.substring(0, 32);
    final id =
        '${bytes.substring(0, 8)}-${bytes.substring(8, 12)}-${bytes.substring(12, 16)}-${bytes.substring(16, 20)}-${bytes.substring(20)}';
    final s = <String, dynamic>{
      'id': id,
      'root': root,
      'bookmark': bookmark,
      'tower': _config!.towerUrl,
      'workspace_id': _config!.workspaceId,
      'owner_npub': _config!.deviceNpub,
      'name': name,
      'host_name': hostName,
      'audience': audience,
      'enabled': true,
      'revision': 0
    };
    shares.add(s);
    await _persist();
    notifyListeners();
    await publish(s);
    await refreshPolicies();
  }

  Future<Map<String, dynamic>> _tower(String url, String method, String secret,
      [Map<String, dynamic>? payload]) async {
    if (towerRequest != null) {
      return towerRequest!(url, method, secret, payload);
    }
    final body = payload == null ? null : jsonEncode(payload);
    final auth = NostrCrypto.signNip98(
        secret: secret, method: method, url: url, body: body);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    client.findProxy = (_) => 'DIRECT';
    final uri = Uri.parse(url);
    if (uri.host.endsWith('.fips')) {
      client.connectionFactory = (u, h, p) =>
          Socket.startConnect(TowerFipsProxy.meshAddress(uri.origin), u.port);
    }
    try {
      final req = await client.openUrl(method, uri);
      req.followRedirects = false;
      req.headers.set('authorization', auth.authorization);
      req.headers.set('content-type', 'application/json');
      if (body != null) req.write(body);
      final response = await req.close().timeout(const Duration(seconds: 10));
      if ({401, 403, 404}.contains(response.statusCode)) {
        throw const DrivePolicyDenied();
      }
      if (response.statusCode != 200) {
        throw StateError('tower_unavailable');
      }
      final data = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        data.addAll(chunk);
        if (data.length > 1024 * 1024) throw StateError('policy_too_large');
      }
      return (jsonDecode(utf8.decode(data)) as Map).cast<String, dynamic>();
    } finally {
      client.close(force: true);
    }
  }

  String _url(Map s) =>
      '${s['tower']}/api/v4/flightdeck-pg/workspaces/${s['workspace_id']}/drive/shares/${s['id']}';
  Future<void> publish(Map<String, dynamic> s) async {
    if (!_owns(s) || _hostIdentity == null || endpoint == null) {
      throw StateError('owner_required');
    }
    final data = <String, dynamic>{
      'name': s['name'],
      'host_name': s['host_name'],
      'host_npub': _hostIdentity!.npub,
      'endpoint': endpoint,
      'audience': s['audience'],
      'enabled': s['enabled'],
      'previous_revision': s['revision']
    };
    final proof = NostrCrypto.signEvent(secret: _hostIdentity!.nsec, event: {
      'kind': 27235,
      'content': '',
      'tags': [
        ['protocol', 'fips-drive-register-v1'],
        ['u', _url(s)],
        ['owner', s['owner_npub']],
        ['payload', sha256.convert(utf8.encode(jsonEncode(data))).toString()]
      ]
    });
    final result = await _tower(
        _url(s), 'PUT', _config!.deviceSecret, {...data, 'host_proof': proof});
    s['revision'] = int.parse(result['share']['revision'].toString());
    await _persist();
    notifyListeners();
  }

  Future<void> updateShare(
      Map<String, dynamic> share, String name, String audience) async {
    if (!_owns(share)) throw StateError('owner_required');
    _policies.remove(share['id']);
    share.remove('policy');
    share.remove('fetched_at');
    share['name'] = name;
    share['audience'] = audience;
    share['enabled'] = true;
    await _persist();
    notifyListeners();
    await publish(share);
    await refreshPolicies();
  }

  Future<void> disable(Map<String, dynamic> s) async {
    s['enabled'] = false;
    _policies.remove(s['id']);
    s.remove('policy');
    s.remove('fetched_at');
    for (final response in _active[s['id']] ?? <HttpResponse>{}) {
      unawaited(response.close());
    }
    await _persist();
    notifyListeners();
    try {
      await publish(s);
    } catch (_) {
      message = 'Stopped locally. Retry registration when Tower returns.';
      notifyListeners();
    }
  }

  Future<void> refreshPolicies() async {
    if (_refreshing || _hostIdentity == null) return;
    _refreshing = true;
    final generation = _generation;
    try {
      for (final s in visible.where((s) => s['enabled'] == true)) {
        try {
          final value =
              await _tower('${_url(s)}/policy', 'GET', _hostIdentity!.nsec);
          if (generation != _generation) return;
          if (value['workspace_id'] != s['workspace_id'] ||
              value['share']['id'] != s['id'] ||
              value['share']['host_npub'] != _hostIdentity!.npub ||
              value['share']['endpoint'] != endpoint) {
            throw const DrivePolicyDenied();
          }
          final fetched = now();
          _policies[s['id']] = DrivePolicy(value, fetched);
          s['policy'] = value;
          s['fetched_at'] = fetched.toIso8601String();
          await _persist();
        } on DrivePolicyDenied {
          _policies.remove(s['id']);
          s.remove('policy');
          s.remove('fetched_at');
          await _persist();
        } catch (_) {/* Outage never renews cached authorization. */}
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<Map<String, dynamic>> _fs(
      Map s, String operation, String path, int offset, String revision) async {
    final bundled = File(
        '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/wmapp-drive-fs');
    final explicit = Platform.environment['WMAPP_DRIVE_FS'];
    final linux = File(
        '${File(Platform.resolvedExecutable).parent.path}/lib/wmapp-drive-fs');
    final binary = helperPath ??
        explicit ??
        (linux.existsSync()
            ? linux.path
            : bundled.existsSync()
                ? bundled.path
                : '${Directory.current.parent.path}/target/debug/wmapp-drive-fs');
    final process = await Process.start(binary, []);
    process.stdin.write(jsonEncode({
      'root': s['root'],
      'path': path,
      'operation': operation,
      'offset': offset,
      'revision': revision
    }));
    await process.stdin.close();
    final out = process.stdout.transform(utf8.decoder).join();
    unawaited(process.stderr.drain());
    final raw = await out.timeout(const Duration(seconds: 15), onTimeout: () {
      process.kill();
      throw StateError('filesystem_timeout');
    });
    if (await process.exitCode != 0 || raw.length > 1024 * 1024) {
      throw StateError('filesystem_unavailable');
    }
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  Future<void> _replayTail = Future.value();
  Future<void> _consumeReplay(String replayId) {
    final next = _replayTail.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final replay =
          (jsonDecode(prefs.getString('wingman.drive.replay.v1') ?? '{}')
                  as Map)
              .cast<String, dynamic>();
      final currentTime = now().millisecondsSinceEpoch;
      replay.removeWhere((_, expiry) => (expiry as int) < currentTime);
      if (replay.length >= 8192 || replay.containsKey(replayId)) {
        throw StateError('replayed_request');
      }
      replay[replayId] = currentTime + 121000;
      if (!await prefs.setString(
          'wingman.drive.replay.v1', jsonEncode(replay))) {
        throw StateError('replay_unavailable');
      }
    });
    _replayTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _serve(HttpRequest req) async {
    Map<String, dynamic>? s;
    final response = req.response;
    try {
      final parts = req.uri.pathSegments;
      if (req.method != 'GET' ||
          parts.length != 4 ||
          parts[0] != 'drive' ||
          parts[1] != 'v1' ||
          !['list', 'read', 'status'].contains(parts[3])) {
        throw StateError('unsupported_request');
      }
      s = shares
          .where((s) => s['id'] == parts[2] && _owns(s) && s['enabled'] == true)
          .first;
      response.statusCode = 401;
      final identity = _verifier.verify(req.headers.value('authorization'),
          '$endpoint${req.uri}', s['workspace_id'], s['id'], now(),
          consume: false);
      response.statusCode = 200;
      bool allowed() =>
          s!['enabled'] == true &&
          _owns(s) &&
          _policies[s['id']]?.allows(identity, now()) == true;
      if (!allowed()) {
        response.statusCode = 403;
        throw StateError('denied_or_policy_expired');
      }
      if (_active.values.fold<int>(0, (n, x) => n + x.length) >= 8) {
        response.statusCode = 429;
        throw StateError('busy');
      }
      response.statusCode = 401;
      // Persist replay consumption before any bytes leave the host, surviving restart.
      final replayId = (jsonDecode(utf8.decode(
              base64Decode(req.headers.value('authorization')!.substring(6))))
          as Map)['id'] as String;
      await _consumeReplay(replayId);
      response.statusCode = 200;
      final active = _active.putIfAbsent(s['id'], () => {});
      active.add(response);
      response.headers.set('cache-control', 'no-store');
      final path = req.uri.queryParameters['path'] ?? '';
      final revision = req.uri.queryParameters['revision'] ?? '';
      if (parts[3] == 'status') {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'available': true}));
      } else if (parts[3] == 'list') {
        final result = await _fs(
            s,
            'list',
            path,
            int.tryParse(req.uri.queryParameters['offset'] ?? '0') ?? 0,
            revision);
        if (!allowed()) {
          response.statusCode = 403;
          throw StateError('revoked');
        }
        if (result['error'] != null) {
          response.statusCode = result['error'] == 'changed' ? 409 : 404;
        }
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(result));
      } else {
        var offset = 0;
        while (true) {
          if (!allowed()) throw StateError('revoked');
          final result = await _fs(s, 'read', path, offset, revision);
          if (!allowed()) throw StateError('revoked');
          if (result['error'] != null) {
            if (offset == 0) {
              response.statusCode = result['error'] == 'changed' ? 409 : 404;
              response.write(jsonEncode(result));
            }
            break;
          }
          if (offset == 0) {
            response.contentLength = result['size'] as int;
            response.headers.contentType = ContentType.binary;
          }
          final bytes = base64Decode(result['chunk']);
          response.add(bytes);
          await response.flush().timeout(const Duration(seconds: 30));
          offset += bytes.length;
          if (result['done'] == true) break;
        }
      }
    } catch (_) {
      try {
        if (response.statusCode == 200) response.statusCode = 404;
      } catch (_) {}
    } finally {
      if (s != null) _active[s['id']]?.remove(response);
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _server?.close(force: true);
    _server = null;
    endpoint = null;
    _policies.clear();
    _active.clear();
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(stop());
    super.dispose();
  }
}
