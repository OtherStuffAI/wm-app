import 'dart:convert';
import 'dart:async';

import '../../core/tower_fips_proxy.dart';
import '../../core/tower_fips_native_request.dart';
import 'tower_fips_bridge_script.dart';

/// One document, one explicit pairing. Destroy on navigation, identity change,
/// logout or tab close; no durable capabilities or signing material.
class TowerFipsBrowserBridge {
  TowerFipsBrowserBridge(
      {required this.pageOrigin,
      required this.logicalTower,
      required this.approve,
      required this.prepare,
      required this.reply,
      this.bindProxy,
      this.unpair});
  final Future<TowerFipsProxy> Function(String endpoint, String pageOrigin)?
      bindProxy;
  final Future<void> Function(String endpoint)? unpair;
  final String pageOrigin;
  final String logicalTower;
  final Future<bool> Function(String endpoint) approve;
  final Future<String?> Function(String endpoint) prepare;
  final Future<void> Function(String script) reply;
  final String _token = TowerFipsProxy.capability();
  TowerFipsProxy? _proxy;
  final Map<String, TowerFipsNativeRequest> _requests = {};
  bool _closed = false;
  bool _connecting = false;
  int _epoch = 0;
  int _openingRequests = 0;
  String get signingDocumentToken => _token;
  bool permitsMeshSigning(String? documentToken, String targetUrl) {
    final endpoint = _proxy?.endpoint;
    if (_closed || documentToken != _token || endpoint == null) return false;
    final uri = Uri.tryParse(targetUrl);
    return uri != null &&
        !uri.hasFragment &&
        uri.userInfo.isEmpty &&
        uri.origin == Uri.parse(endpoint).origin &&
        targetUrl.startsWith('$endpoint/');
  }

  String get script => towerFipsBridgeScript(_token, pageOrigin);

  Future<void> receive(String message) async {
    String? id;
    try {
      if (_closed || message.length > 100000) return;
      final value = jsonDecode(message) as Map<String, dynamic>;
      if (value['token'] != _token) return;
      id = value['id'] as String;
      final method = value['method'] as String;
      final params = (value['params'] as Map?)?.cast<String, dynamic>() ?? {};
      final result = await _call(method, params);
      if (!_closed) {
        await reply('window.__wingmanTowerReply?.('
            '${jsonEncode(_token)},${jsonEncode(id)},${jsonEncode(result)},null)');
      }
    } catch (_) {
      if (!_closed && id != null) {
        await reply('window.__wingmanTowerReply?.('
            '${jsonEncode(_token)},${jsonEncode(id)},null,'
            '"Tower FIPS request failed or pairing was denied. No public fallback.")');
      }
    }
  }

  Future<dynamic> _call(String method, Map<String, dynamic> p) async {
    if (method == 'connect') {
      if (_connecting) throw StateError('Pairing already in progress.');
      final endpoint = p['endpoint'] as String;
      TowerFipsProxy.validateEndpoint(endpoint);
      final logical = Uri.parse(logicalTower);
      if (logical.scheme != 'https' ||
          logical.origin != logicalTower ||
          p['logicalTower'] != logicalTower) {
        throw StateError('Logical Tower does not match current configuration.');
      }
      if (_proxy?.endpoint == endpoint) return _connection();
      _connecting = true;
      final epoch = ++_epoch;
      try {
        if (!await approve(endpoint) || _closed || epoch != _epoch) {
          throw StateError('Pairing denied.');
        }
        final failure = await prepare('$endpoint/');
        if (failure != null || _closed || epoch != _epoch) {
          throw StateError('FIPS not ready.');
        }
        await _disconnect();
        final proxy = await (bindProxy?.call(endpoint, pageOrigin) ??
            TowerFipsProxy.bind(endpoint: endpoint, pageOrigin: pageOrigin));
        if (_closed || epoch != _epoch) {
          await proxy.close();
          throw StateError('Document closed.');
        }
        _proxy = proxy;
        return _connection();
      } finally {
        _connecting = false;
      }
    }
    if (method == 'disconnect') {
      ++_epoch;
      final endpoint = _proxy?.endpoint;
      try {
        if (endpoint != null) await unpair?.call(endpoint);
      } finally {
        await _disconnect();
      }
      return null;
    }
    final proxy = _proxy;
    if (proxy == null) throw StateError('Connect first.');
    if (method == 'open') {
      if (_requests.length + _openingRequests >= 64) {
        throw StateError('Too many active requests.');
      }
      ++_openingRequests;
      late final TowerFipsNativeRequest request;
      try {
        request = await TowerFipsNativeRequest.open(
            proxy,
            p['url'] as String,
            p['method'] as String,
            (p['headers'] as Map).cast<String, dynamic>());
      } finally {
        --_openingRequests;
      }
      if (_closed || _proxy != proxy) {
        request.close();
        throw StateError('Pairing closed.');
      }
      final id = TowerFipsProxy.capability();
      _requests[id] = request;
      return id;
    }
    final id = p['requestId'] as String;
    final request = _requests[id];
    if (method == 'cancel') {
      _requests.remove(id)?.close();
      return null;
    }
    if (request == null) throw StateError('Request is closed.');
    try {
      switch (method) {
        case 'write':
          await request.write(p['chunk'] as String);
          return null;
        case 'finish':
          return await request.finish();
        case 'pull':
          final value = await request.pull();
          if (value['done'] == true) _requests.remove(id);
          return value;
        default:
          throw StateError('Unsupported transport operation.');
      }
    } catch (_) {
      _requests.remove(id)?.close();
      rethrow;
    }
  }

  Map<String, dynamic> _connection() => {
        'version': 2,
        'endpoint': _proxy!.endpoint,
        'logicalTower': logicalTower,
        'transport': 'native'
      };

  Future<void> _disconnect() async {
    for (final request in _requests.values) {
      request.close();
    }
    _requests.clear();
    final proxy = _proxy;
    _proxy = null;
    await proxy?.close();
  }

  void close() {
    if (_closed) return;
    unawaited(reply('window.__wingmanTowerRevoke?.(${jsonEncode(_token)})')
        .catchError((Object _) {}));
    ++_epoch;
    _closed = true;
    unawaited(_disconnect());
  }
}
