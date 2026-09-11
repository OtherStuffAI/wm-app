import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../../core/grasp_fips_transport.dart';
import '../../core/tower_fips_proxy.dart';
import 'grasp_fips_bridge_script.dart';
import 'mesh_auth_request.dart';
import '../drive/drive_native_save.dart';

/// Ephemeral transport grant for one native-verified top-level document.
class GraspFipsBrowserBridge {
  GraspFipsBrowserBridge(
      {required this.pageOrigin,
      required this.approve,
      required this.prepare,
      required this.reply,
      this.transportFactory});
  final String pageOrigin;
  final Future<bool> Function(String endpoint) approve;
  final Future<String?> Function(String endpoint) prepare;
  final Future<void> Function(String script) reply;
  final GraspFipsTransport Function(String endpoint)? transportFactory;
  final String _token = TowerFipsProxy.capability();
  final Map<String, GraspHttpRequest> _requests = {};
  final Map<String, GraspSocket> _sockets = {};
  final Set<String> _denied = {};
  final Map<String, GraspFipsTransport> _drive = {};
  final Map<String, DriveNativeSave> _saves = {};
  bool get hasDrive => _drive.isNotEmpty;
  GraspFipsTransport? _transport;
  bool _closed = false, _connecting = false;
  int _epoch = 0, _opening = 0;
  String get script => graspFipsBridgeScript(_token, pageOrigin);
  int get grantEpoch => _epoch;
  String? get endpoint => _transport?.endpoint;

  bool permitsAuthentication(String method, Map<String, dynamic> params) {
    final transport = _transport;
    if (_closed || method != 'signEvent') return false;
    if (permitsDriveAuthentication(params)) return true;
    if (transport == null) return false;
    final auth = MeshAuthRequest.parse(method, params);
    if (auth == null ||
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 -
                    (params['created_at'] as int))
                .abs() >
            60) {
      return false;
    }
    if (params['kind'] == 27235) {
      final tags = params['tags'] as List;
      final uri = Uri.parse(auth.target);
      return auth.operation == 'GET' &&
          tags.length == 2 &&
          transport.accepts(auth.target) &&
          !uri.hasQuery &&
          RegExp(r'^/[^/]+/[^/]+\.git$').hasMatch(uri.path);
    }
    if (params['kind'] == 22242) {
      final tags = params['tags'] as List;
      final challenge =
          tags.firstWhere((t) => t[0] == 'challenge')[1] as String;
      return transport.hasChallenge(auth.target, challenge);
    }
    return false;
  }

  bool permitsDriveAuthentication(Map<String, dynamic> p) {
    try {
      final tags = p['tags'] as List;
      if (_closed ||
          p['kind'] != 27235 ||
          p['content'] != '' ||
          tags.length != 5 ||
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 -
                      (p['created_at'] as int))
                  .abs() >
              60) {
        return false;
      }
      if (tags[0][0] != 'u' ||
          tags[1][0] != 'method' ||
          tags[1][1] != 'GET' ||
          tags[2][0] != 'workspace' ||
          tags[3][0] != 'share' ||
          tags[4][0] != 'nonce') {
        return false;
      }
      if (tags.any((t) => t is! List || t.length != 2 || t[1] is! String)) {
        return false;
      }
      final url = tags[0][1] as String;
      final u = Uri.parse(url);
      return _drive[u.origin]?.accepts(url) == true &&
          u.path == '/drive/v1/${tags[3][1]}/${u.pathSegments.last}' &&
          ['list', 'read', 'status'].contains(u.pathSegments.last) &&
          RegExp(r'^[a-zA-Z0-9_-]{32,128}$').hasMatch(tags[4][1]);
    } catch (_) {
      return false;
    }
  }

  Future<void> receive(String message) async {
    String? id;
    String? operation;
    final epoch = _epoch;
    try {
      if (_closed || message.length > 1500000) return;
      final value = jsonDecode(message) as Map<String, dynamic>;
      if (value['token'] != _token) return;
      id = value['id'] as String;
      operation = value['method'] as String?;
      if (id.length > 128) return;
      final result = await _call(value['method'] as String,
          (value['params'] as Map).cast<String, dynamic>());
      if (!_closed &&
          (epoch == _epoch ||
              value['method'] == 'connect' ||
              value['method'] == 'disconnect')) {
        await reply(
            'window.__wingmanGraspReply?.(${jsonEncode(_token)},${jsonEncode(id)},${jsonEncode(result)},null)');
      }
    } catch (error) {
      if (!_closed && id != null) {
        final errorMessage = operation == 'connectDrive'
            ? (error is StateError && error.message == 'denied'
                ? 'consent-denied'
                : 'offline')
            : 'Transport failed or revoked.';
        await reply(
            'window.__wingmanGraspReply?.(${jsonEncode(_token)},${jsonEncode(id)},null,${jsonEncode(errorMessage)})');
      }
    }
  }

  Future<dynamic> _call(String method, Map<String, dynamic> p) async {
    if (method == 'connectDrive') {
      final endpoint = p['endpoint'] as String;
      TowerFipsProxy.validateEndpoint(endpoint);
      if (_drive.containsKey(endpoint)) {
        return {'version': 1, 'endpoint': endpoint};
      }
      if (_connecting || _drive.length >= 8 || _denied.contains(endpoint)) {
        throw StateError('denied');
      }
      _connecting = true;
      final epoch = _epoch;
      try {
        if (!await approve(endpoint)) {
          _denied.add(endpoint);
          throw StateError('denied');
        }
        if (_closed || epoch != _epoch) throw StateError('revoked');
        if (await prepare('$endpoint/') != null) throw StateError('offline');
        if (_closed || epoch != _epoch) throw StateError('revoked');
        _drive[endpoint] =
            transportFactory?.call(endpoint) ?? GraspFipsTransport(endpoint);
        return {'version': 1, 'endpoint': endpoint};
      } finally {
        _connecting = false;
      }
    }
    if (method == 'saveBegin') {
      if (_saves.length >= 4 || _drive.isEmpty) {
        throw StateError('save_unavailable');
      }
      final epoch = _epoch;
      final name =
          (p['name'] as String).replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
      if (name.isEmpty || name == '.' || name == '..' || name.length > 240) {
        throw StateError('invalid_filename');
      }
      String? target;
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        target = (await getSaveLocation(suggestedName: name))?.path;
      } else {
        final root = Platform.isAndroid
            ? await getApplicationSupportDirectory()
            : await getApplicationDocumentsDirectory();
        final directory =
            await Directory('${root.path}/drive/${TowerFipsProxy.capability()}')
                .create(recursive: true);
        target = '${directory.path}/$name';
      }
      if (target == null || _closed || epoch != _epoch) {
        throw StateError('cancelled');
      }
      final id = TowerFipsProxy.capability();
      final file = File('$target.$id.partial');
      _saves[id] = DriveNativeSave(file, target);
      return id;
    }
    if (method.startsWith('save')) {
      final id = p['saveId'] as String;
      final save = _saves[id];
      if (save == null) throw StateError('save_closed');
      if (method == 'saveWrite') {
        final chunk = p['chunk'] as String;
        if (chunk.length > 87384) throw StateError('chunk_too_large');
        final bytes = base64Decode(chunk);
        if (bytes.length > 65536) throw StateError('chunk_too_large');
        if (save.cancelled) throw StateError('cancelled');
        save.sink.add(bytes);
        await save.sink.flush();
        return null;
      }
      final epoch = _epoch;
      try {
        if (method == 'saveFinish') {
          await save.finish(
              revoked: () => _closed || epoch != _epoch,
              export: p['open'] == true || Platform.isIOS || Platform.isAndroid
                  ? () async {
                      await const MethodChannel(
                              'au.com.otherstuff.wingman/drive')
                          .invokeMethod('open', save.target);
                    }
                  : null);
          return {'saved': true, 'location': 'local'};
        }
        await save.cancel();
        return null;
      } finally {
        _saves.remove(id);
      }
    }
    if (method == 'connect') {
      final endpoint = p['endpoint'] as String;
      TowerFipsProxy.validateEndpoint(endpoint);
      if (_connecting || _denied.contains(endpoint)) {
        throw StateError('Connection denied.');
      }
      if (_transport?.endpoint == endpoint) {
        return {'version': 1, 'endpoint': endpoint};
      }
      // A different service requires a fresh document, avoiding replacement races.
      if (_transport != null) {
        throw StateError('Disconnect before changing service.');
      }
      _connecting = true;
      final epoch = _epoch;
      try {
        if (!await approve(endpoint)) {
          _denied.add(endpoint);
          throw StateError('Denied.');
        }
        if (_closed || epoch != _epoch) throw StateError('Revoked.');
        final failure = await prepare('$endpoint/');
        if (failure != null || _closed || epoch != _epoch) {
          throw StateError('FIPS unavailable.');
        }
        _transport =
            transportFactory?.call(endpoint) ?? GraspFipsTransport(endpoint);
        return {'version': 1, 'endpoint': endpoint};
      } finally {
        _connecting = false;
      }
    }
    if (method == 'disconnect') {
      _disconnect();
      return null;
    }
    final requestedUrl = p['url'] as String?;
    final driveTransport = requestedUrl == null || method != 'open'
        ? null
        : _drive[Uri.parse(requestedUrl).origin];
    final transport = driveTransport ?? _transport;
    if (driveTransport != null &&
        (method != 'open' ||
            p['method'] != 'GET' ||
            !RegExp(r'^/drive/v1/[^/]+/(list|read|status)$')
                .hasMatch(Uri.parse(requestedUrl!).path))) {
      throw StateError('Read-only Drive request required.');
    }
    if (transport == null &&
        !{'pull', 'finish', 'write', 'cancel', 'wsClose', 'wsNext', 'wsSend'}
            .contains(method)) {
      throw StateError('Connect first.');
    }
    final epoch = _epoch;
    if (method == 'open' || method == 'wsOpen') {
      if (_opening + _requests.length + _sockets.length >= 32) {
        throw StateError('Too many requests.');
      }
      _opening++;
      try {
        final id = TowerFipsProxy.capability();
        if (method == 'open') {
          final request = await transport!.open(
              p['url'] as String,
              p['method'] as String,
              (p['headers'] as Map).cast<String, dynamic>());
          if (_closed || epoch != _epoch) {
            request.close();
            throw StateError('Revoked.');
          }
          _requests[id] = request;
        } else {
          final socket = await transport!.socket(p['url'] as String);
          if (_closed || epoch != _epoch) {
            socket.close();
            throw StateError('Revoked.');
          }
          _sockets[id] = socket;
        }
        return id;
      } finally {
        _opening--;
      }
    }
    final id = p['requestId'] as String;
    if (method == 'cancel') {
      _requests.remove(id)?.close();
      return null;
    }
    if (method == 'wsClose') {
      final code = p['code'] as int? ?? 1000;
      final reason = p['reason'] as String? ?? '';
      if ((code != 1000 && (code < 3000 || code > 4999)) ||
          utf8.encode(reason).length > 123) {
        throw StateError('Invalid close.');
      }
      _sockets.remove(id)?.close(code, reason);
      return null;
    }
    if (method == 'wsNext' || method == 'wsSend') {
      final socket = _sockets[id];
      if (socket == null) throw StateError('Relay closed.');
      try {
        if (method == 'wsSend') {
          await socket.send(p['data'] as String, p['text'] as bool);
          return null;
        }
        final result = await socket.next();
        if (result['done'] == true) _sockets.remove(id);
        return result;
      } catch (_) {
        _sockets.remove(id)?.close();
        rethrow;
      }
    }
    final request = _requests[id];
    if (request == null) throw StateError('Request closed.');
    try {
      switch (method) {
        case 'write':
          await request.write(p['chunk'] as String);
          return null;
        case 'finish':
          return await request.finish();
        case 'pull':
          final result = await request.pull();
          if (result['done'] == true) _requests.remove(id);
          return result;
        default:
          throw StateError('Unknown operation.');
      }
    } catch (_) {
      _requests.remove(id)?.close();
      rethrow;
    }
  }

  void _disconnect() {
    _epoch++;
    _transport?.close();
    _transport = null;
    for (final t in _drive.values) {
      t.close();
    }
    _drive.clear();
    for (final s in _saves.values) {
      unawaited(s.cancel().catchError((Object _) {}));
    }
    _saves.clear();
    _requests.clear();
    _sockets.clear();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _disconnect();
    unawaited(reply('window.__wingmanGraspRevoke?.(${jsonEncode(_token)})')
        .catchError((Object _) {}));
  }
}
