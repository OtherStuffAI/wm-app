import 'dart:async';
import 'dart:convert';

import '../../core/grasp_fips_transport.dart';
import '../../core/tower_fips_proxy.dart';
import 'grasp_fips_bridge_script.dart';
import 'mesh_auth_request.dart';

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
  GraspFipsTransport? _transport;
  bool _closed = false, _connecting = false;
  int _epoch = 0, _opening = 0;
  String get script => graspFipsBridgeScript(_token, pageOrigin);
  int get grantEpoch => _epoch;
  String? get endpoint => _transport?.endpoint;

  bool permitsAuthentication(String method, Map<String, dynamic> params) {
    final transport = _transport;
    if (_closed || transport == null || method != 'signEvent') return false;
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

  Future<void> receive(String message) async {
    String? id;
    final epoch = _epoch;
    try {
      if (_closed || message.length > 1500000) return;
      final value = jsonDecode(message) as Map<String, dynamic>;
      if (value['token'] != _token) return;
      id = value['id'] as String;
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
    } catch (_) {
      if (!_closed && id != null) {
        await reply(
            'window.__wingmanGraspReply?.(${jsonEncode(_token)},${jsonEncode(id)},null,"GRASP transport denied, revoked, or failed. No public fallback.")');
      }
    }
  }

  Future<dynamic> _call(String method, Map<String, dynamic> p) async {
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
    final transport = _transport;
    if (transport == null) throw StateError('Connect first.');
    final epoch = _epoch;
    if (method == 'open' || method == 'wsOpen') {
      if (_opening + _requests.length + _sockets.length >= 32) {
        throw StateError('Too many requests.');
      }
      _opening++;
      try {
        final id = TowerFipsProxy.capability();
        if (method == 'open') {
          final request = await transport.open(
              p['url'] as String,
              p['method'] as String,
              (p['headers'] as Map).cast<String, dynamic>());
          if (_closed || epoch != _epoch) {
            request.close();
            throw StateError('Revoked.');
          }
          _requests[id] = request;
        } else {
          final socket = await transport.socket(p['url'] as String);
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
