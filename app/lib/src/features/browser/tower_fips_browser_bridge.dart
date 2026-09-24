import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;

import '../../core/tower_fips_proxy.dart';
import '../../core/tower_fips_native_request.dart';
import 'tower_fips_bridge_script.dart';

/// One document, one explicit pairing. Destroy on navigation, identity change,
/// logout or tab close; no durable capabilities or signing material.
class TowerFipsBrowserBridge {
  TowerFipsBrowserBridge(
      {required this.pageOrigin,
      required this.approve,
      required this.prepare,
      required this.reply,
      this.bindProxy,
      this.unpair,
      this.diagnostic,
      this.connectPhaseTimeout = const Duration(seconds: 30)});
  final Future<TowerFipsProxy> Function(String endpoint, String pageOrigin)?
      bindProxy;
  final Future<void> Function(String endpoint, String serviceNpub)? unpair;
  final Duration connectPhaseTimeout;
  final void Function(Map<String, Object?> event)? diagnostic;
  final String pageOrigin;
  String? _serviceNpub;
  final Future<bool> Function(String endpoint, String serviceNpub) approve;
  final Future<String?> Function(String endpoint) prepare;
  final Future<void> Function(String script) reply;
  final String _token = TowerFipsProxy.capability();
  TowerFipsProxy? _proxy;
  TowerFipsProxy? _pendingProxy;
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
    String? correlationId;
    try {
      if (_closed || message.length > 100000) return;
      final value = jsonDecode(message) as Map<String, dynamic>;
      if (value['token'] != _token) return;
      id = value['id'] as String;
      final method = value['method'] as String;
      final params = (value['params'] as Map?)?.cast<String, dynamic>() ?? {};
      correlationId = _safeCorrelationId(params['correlationId']);
      _log('native_bridge_received', correlationId, {'method': method});
      final result = await _call(method, params);
      if (!_closed) {
        await reply('window.__wingmanTowerReply?.('
            '${jsonEncode(_token)},${jsonEncode(id)},${jsonEncode(result)},null)');
        _log('native_reply_delivered', correlationId,
            {'method': method, 'outcome': 'success'});
      }
    } catch (error) {
      if (!_closed && id != null) {
        final publicError = _publicError(error);
        await reply('window.__wingmanTowerReply?.('
            '${jsonEncode(_token)},${jsonEncode(id)},null,'
            '${jsonEncode(publicError)})');
        _log('native_reply_delivered', correlationId, {
          'outcome': 'error',
          'code': _publicCode(error),
        });
      }
    }
  }

  Future<dynamic> _call(String method, Map<String, dynamic> p) async {
    if (method == 'connect') {
      if (_connecting) throw StateError('Pairing already in progress.');
      final endpoint = p['endpoint'] as String;
      TowerFipsProxy.validateEndpoint(endpoint);
      final serviceNpub = p['serviceNpub'] as String;
      final correlationId = _safeCorrelationId(p['correlationId']);
      // Validate a service npub independently of the mesh node's identity.
      TowerFipsProxy.meshAddress('http://$serviceNpub.fips:1');
      final target = Uri.parse(endpoint);
      _log('endpoint_validated', correlationId, {
        'host': target.host,
        'port': target.port,
        'serviceNpub': serviceNpub,
      });
      if (_proxy?.endpoint == endpoint && _serviceNpub == serviceNpub) {
        return _connection();
      }
      _connecting = true;
      final epoch = ++_epoch;
      try {
        await _disconnect();
        final approved = await approve(endpoint, serviceNpub);
        _log('approval_resolved', correlationId, {'approved': approved});
        if (!approved || _closed || epoch != _epoch) {
          throw StateError('Pairing denied.');
        }
        _log('fips_readiness_started', correlationId);
        final failure = await prepare('$endpoint/').timeout(
          connectPhaseTimeout,
          onTimeout: () => throw TimeoutException(
            'FIPS readiness timed out. Open Setup, check the mesh status, then retry.',
          ),
        );
        if (failure != null || _closed || epoch != _epoch) {
          throw const TowerFipsPublicError('fips_not_ready',
              'FIPS is not ready. Open Setup, verify the mesh is connected, then retry.');
        }
        _log('fips_readiness_succeeded', correlationId);
        await _disconnect();
        _log('proxy_bind_started', correlationId);
        final proxy = await (bindProxy?.call(endpoint, pageOrigin) ??
            TowerFipsProxy.bind(endpoint: endpoint, pageOrigin: pageOrigin));
        _log('proxy_bind_succeeded', correlationId,
            {'proxyPort': Uri.parse(proxy.proxyBaseUrl).port});
        if (_closed || epoch != _epoch) {
          await proxy.close();
          throw StateError('Document closed.');
        }
        _pendingProxy = proxy;
        try {
          await _verifyService(proxy, serviceNpub, correlationId)
              .timeout(const Duration(seconds: 15), onTimeout: () {
            throw const TowerFipsPublicError('health_timeout',
                'FIPS connected, but the endpoint health check timed out. Verify the advertised FIPS service is reachable.');
          });
          if (_closed || epoch != _epoch) throw StateError('Document closed.');
        } catch (_) {
          await proxy.close();
          await unpair?.call(endpoint, serviceNpub);
          rethrow;
        } finally {
          if (identical(_pendingProxy, proxy)) _pendingProxy = null;
        }
        _serviceNpub = serviceNpub;
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
        if (endpoint != null) await unpair?.call(endpoint, _serviceNpub!);
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
        'serviceNpub': _serviceNpub,
        'transport': 'native'
      };

  String _publicError(Object error) {
    if (error is TowerFipsPublicError) return '${error.code}: ${error.message}';
    if (error is TimeoutException && error.message != null) {
      return 'fips_readiness_timeout: ${error.message!}';
    }
    return 'fips_connection_failed: Tower FIPS request failed or pairing was denied. No public fallback.';
  }

  String _publicCode(Object error) => error is TowerFipsPublicError
      ? error.code
      : error is TimeoutException
          ? 'fips_readiness_timeout'
          : 'fips_connection_failed';

  // Only this unsigned identity probe is allowed before activating the route.
  // It uses the same pinned transport and redirect policy as signed requests.
  Future<void> _verifyService(
      TowerFipsProxy proxy, String expected, String? correlationId) async {
    _log('health_request_started', correlationId, {'path': '/health'});
    final request = await TowerFipsNativeRequest.open(
        proxy, '${proxy.endpoint}/health', 'GET', {});
    try {
      final response = await request.finish();
      final status = response['status'] as int?;
      _log('health_response_received', correlationId, {
        'statusClass': status == null ? 'unknown' : '${status ~/ 100}xx',
      });
      if (status != 200) {
        throw TowerFipsPublicError('health_http_status',
            'FIPS endpoint health returned HTTP ${status ?? 'unknown'}. Check the advertised service and port.');
      }
      final bytes = <int>[];
      while (true) {
        final part = await request.pull();
        if (part['done'] == true) break;
        bytes.addAll(base64Decode(part['chunk'] as String));
        if (bytes.length > 65536) throw StateError('Tower health too large.');
      }
      final health = jsonDecode(utf8.decode(bytes)) as Map;
      if (health['service_npub'] != expected) {
        _log('health_identity_compared', correlationId, {'matches': false});
        throw const TowerFipsPublicError('health_identity_mismatch',
            'FIPS endpoint identity did not match the signed transport identity. Regenerate the connect package from this Autopilot installation.');
      }
      _log('health_identity_compared', correlationId, {'matches': true});
    } finally {
      request.close();
    }
  }

  void _log(String stage, String? correlationId,
      [Map<String, Object?> fields = const {}]) {
    final event = <String, Object?>{
      'component': 'wmapp_tower_fips',
      'stage': stage,
      if (correlationId != null && correlationId.isNotEmpty)
        'correlationId': correlationId,
      ...fields,
    };
    diagnostic?.call(event);
    if (diagnostic == null) {
      developer.log(jsonEncode(event), name: 'wingman.tower_fips');
    }
  }

  static String? _safeCorrelationId(Object? value) {
    final candidate = value is String ? value : null;
    return candidate != null &&
            RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(candidate)
        ? candidate
        : null;
  }

  Future<void> _disconnect() async {
    for (final request in _requests.values) {
      request.close();
    }
    _requests.clear();
    final pending = _pendingProxy;
    _pendingProxy = null;
    final proxy = _proxy;
    _proxy = null;
    _serviceNpub = null;
    await pending?.close();
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

class TowerFipsPublicError implements Exception {
  const TowerFipsPublicError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}
