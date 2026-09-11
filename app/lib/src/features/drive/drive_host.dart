import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_config.dart';
import '../../core/nostr_crypto.dart';
import '../../core/signer_vault.dart';
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
      this.beforeReplay,
      FipsRuntimeService? fipsRuntime,
      SignerVaultSecretStore? hostSecretStore,
      this.listenAddress,
      this.listenPort = 7345,
      this.now = DateTime.now})
      : _fipsRuntime = fipsRuntime ?? FipsRuntimeService(),
        _hostSecretStore =
            hostSecretStore ?? SecureStorageSignerVaultSecretStore();
  final Future<NostrIdentity> Function()? identityLoader;
  final Future<String> Function()? endpointLoader;
  final Future<Map<String, dynamic>> Function(
      String, String, String, Map<String, dynamic>?)? towerRequest;
  final String? helperPath;
  final Future<void> Function()? beforeReplay;
  final FipsRuntimeService _fipsRuntime;
  final SignerVaultSecretStore _hostSecretStore;
  int get activeRequests => _active.values.fold<int>(0, (n, x) => n + x.length);
  final InternetAddress? listenAddress;
  final int listenPort;
  final DateTime Function() now;
  int? get listeningPort => _server?.port;

  static const channel = MethodChannel('au.com.otherstuff.wingman/drive');
  static const storageKey = 'wingman.drive.shares.v1';
  static const hostIdentityStorageKey = 'wingman.drive.host-key.v1';
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

  Future<void> configure(AppConfig config, {bool repair = false}) async {
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
        var secret = await _hostSecretStore.read(hostIdentityStorageKey);
        if (generation != _generation) return;
        if (secret == null) {
          secret = NostrCrypto.generateIdentity().nsec;
          await _hostSecretStore.write(hostIdentityStorageKey, secret);
        }
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
      endpoint = endpointLoader != null
          ? await endpointLoader!()
          : await _resolveLocalFipsEndpoint(repair: repair);
      if (generation != _generation) return;
      final server = await HttpServer.bind(
          listenAddress ?? TowerFipsProxy.meshAddress(endpoint!), listenPort);
      if (generation != _generation) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.idleTimeout = const Duration(seconds: 30);
      server.listen(_serve);
      _timer = Timer.periodic(
          const Duration(seconds: 30), (_) => unawaited(refreshPolicies()));
      await refreshPolicies();
      message =
          'Hosting selected folders while WM App is running and unlocked.';
    } on DriveHostStartupException catch (error) {
      if (generation != _generation) return;
      await stop();
      message = error.message;
    } on SocketException catch (error) {
      if (generation != _generation) return;
      await stop();
      message =
          'Drive hosting could not bind to this machine FIPS address: ${error.osError?.message ?? error.message}. Check FIPS is running for this login session, then retry.';
    } on FormatException catch (error) {
      if (generation != _generation) return;
      await stop();
      message =
          'Drive hosting found an invalid FIPS identity: ${error.message}. Repair FIPS, then retry.';
    } catch (error) {
      if (generation != _generation) return;
      await stop();
      message =
          'Drive hosting failed during startup: ${FipsRuntimeService.redactSecrets(error.toString())}. Retry after checking FIPS and folder access.';
    }
    notifyListeners();
  }

  Future<String> _resolveLocalFipsEndpoint({required bool repair}) async {
    final status = repair
        ? await _fipsRuntime.ensureReadyForAppAccess()
        : await _fipsRuntime.inspect();
    if (!status.canAttemptAppAccess) {
      throw DriveHostStartupException(
          'Drive hosting cannot start because FIPS is not ready: ${status.detail}');
    }
    final nodeNpub = status.nodeNpub?.trim();
    if (nodeNpub == null || nodeNpub.isEmpty) {
      if (status.state == FipsRuntimeState.controlAccessPending) {
        throw const DriveHostStartupException(
            'FIPS is running, but Drive hosting cannot read this machine FIPS identity from this login session yet. Log out and back in, then retry.');
      }
      throw DriveHostStartupException(
          'Drive hosting cannot start because FIPS did not report this machine identity (${status.detail})');
    }
    return 'http://$nodeNpub.fips:7345';
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
      'published': false,
      'revision': 0
    };
    shares.add(s);
    await _persist();
    notifyListeners();
    try {
      await publish(s);
      await refreshPolicies();
    } catch (error) {
      s['last_registration_error'] = safeRegistrationError(error);
      await _persist();
      notifyListeners();
      rethrow;
    }
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
      final data = <int>[];
      final response = await req.close().timeout(const Duration(seconds: 10));
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        data.addAll(chunk);
        if (data.length > 1024 * 1024) throw StateError('policy_too_large');
      }
      final text = utf8.decode(data);
      Map<String, dynamic>? decoded;
      if (text.trim().isNotEmpty) {
        final value = jsonDecode(text);
        if (value is Map) decoded = value.cast<String, dynamic>();
      }
      if ({401, 403, 404}.contains(response.statusCode)) {
        throw DrivePolicyDenied(statusCode: response.statusCode, body: decoded);
      }
      if (response.statusCode != 200) {
        throw DriveTowerException(response.statusCode, decoded, text);
      }
      return decoded ?? <String, dynamic>{};
    } finally {
      client.close(force: true);
    }
  }

  String _url(Map s) =>
      '${s['tower']}/api/v4/flightdeck-pg/workspaces/${s['workspace_id']}/drive/shares/${s['id']}';
  Map<String, dynamic> _registrationData(Map<String, dynamic> s) =>
      <String, dynamic>{
        'name': (s['name'] ?? '').toString().trim(),
        'host_name': (s['host_name'] ?? '').toString().trim(),
        'host_npub': _hostIdentity!.npub,
        'endpoint': endpoint,
        'audience': s['audience'],
        'enabled': s['enabled'],
        'previous_revision': s['revision']
      };

  Future<void> publish(Map<String, dynamic> s) async {
    if (!_owns(s) || _hostIdentity == null || endpoint == null) {
      throw StateError('owner_required');
    }
    final owner = NostrCrypto.importIdentity(_config!.deviceSecret);
    if (owner.npub != _config!.deviceNpub || owner.npub != s['owner_npub']) {
      throw const DriveRegistrationException(
          'Drive registration requires the unlocked owner identity for this workspace.');
    }
    final data = _registrationData(s);
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
    Map<String, dynamic> result;
    try {
      result = await _tower(_url(s), 'PUT', _config!.deviceSecret,
          {...data, 'host_proof': proof});
    } catch (error) {
      s['published'] = false;
      s['last_registration_error'] = safeRegistrationError(error);
      await _persist();
      notifyListeners();
      rethrow;
    }
    s['revision'] = int.parse(result['share']['revision'].toString());
    s['name'] = data['name'];
    s['host_name'] = data['host_name'];
    s['published'] = true;
    s.remove('last_registration_error');
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
    share['published'] = false;
    share.remove('last_registration_error');
    await _persist();
    notifyListeners();
    try {
      await publish(share);
      await refreshPolicies();
    } catch (error) {
      share['last_registration_error'] = safeRegistrationError(error);
      await _persist();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disable(Map<String, dynamic> s) async {
    s['enabled'] = false;
    s['published'] = false;
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

  String registrationStatus(Map<String, dynamic> s) {
    if (s['enabled'] != true) return 'Stopped';
    if (s['published'] == true && s['revision'] is int && s['revision'] > 0) {
      return 'Sharing';
    }
    final error = s['last_registration_error'];
    if (error is String && error.isNotEmpty) {
      return 'Registration failed: $error';
    }
    return 'Registration pending';
  }

  String safeRegistrationError(Object error) {
    if (error is DriveRegistrationException) return error.message;
    if (error is DriveTowerException) return error.safeMessage;
    if (error is DrivePolicyDenied) return error.safeMessage;
    if (error is SocketException) {
      return 'Network error reaching Tower (${error.osError?.message ?? error.message})';
    }
    if (error is TimeoutException) return 'Timed out waiting for Tower';
    if (error is FormatException) return 'Invalid Tower response';
    return FipsRuntimeService.redactSecrets(error.toString());
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
    final serving = _server;
    final generation = _generation;
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
          serving != null &&
          identical(serving, _server) &&
          generation == _generation &&
          s!['enabled'] == true &&
          _owns(s) &&
          _policies[s['id']]?.allows(identity, now()) == true;
      if (!allowed()) {
        response.statusCode = 403;
        throw StateError('denied_or_policy_expired');
      }
      if (activeRequests >= 8) {
        response.statusCode = 429;
        throw StateError('busy');
      }
      // Reserve synchronously, before replay persistence can yield.
      _active.putIfAbsent(s['id'], () => {}).add(response);
      response.statusCode = 401;
      if (beforeReplay != null) await beforeReplay!();
      // Persist replay consumption before any bytes leave the host, surviving restart.
      final replayId = (jsonDecode(utf8.decode(
              base64Decode(req.headers.value('authorization')!.substring(6))))
          as Map)['id'] as String;
      await _consumeReplay(replayId);
      response.statusCode = 200;
      if (!allowed()) {
        response.statusCode = 403;
        throw StateError('revoked');
      }
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

class DriveHostStartupException implements Exception {
  const DriveHostStartupException(this.message);

  final String message;

  @override
  String toString() => message;
}
