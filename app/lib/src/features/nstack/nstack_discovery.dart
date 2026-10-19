import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/nostr_crypto.dart';
import 'nstack_models.dart';
import 'nstack_store.dart';

const nstackWorkspaceResponseMaxBytes = 256 * 1024;
const nstackWorkspaceDiscoveryTimeout = Duration(seconds: 10);

class NStackDiscoveryException implements Exception {
  const NStackDiscoveryException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

abstract class NStackWorkspaceDiscovery {
  Future<List<NStackWorkspace>> discover({
    required String address,
    required String identityNpub,
    required String secret,
  });
}

class TowerNStackWorkspaceDiscovery implements NStackWorkspaceDiscovery {
  TowerNStackWorkspaceDiscovery({
    http.Client? client,
    this.timeout = nstackWorkspaceDiscoveryTimeout,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  @override
  Future<List<NStackWorkspace>> discover({
    required String address,
    required String identityNpub,
    required String secret,
  }) async {
    final root = canonicalNStackUrl(address);
    if (root == null) {
      throw const NStackDiscoveryException(
          'invalid_address', 'Enter a valid HTTPS NStack address.');
    }
    NostrIdentity signer;
    try {
      signer = NostrCrypto.importIdentity(secret);
    } catch (_) {
      throw const NStackDiscoveryException(
          'locked', 'Unlock the active Nostr identity first.');
    }
    if (signer.npub != identityNpub) {
      throw const NStackDiscoveryException('identity_changed',
          'The unlocked identity changed before discovery.');
    }

    final rootUri = Uri.parse(root);
    final basePath = rootUri.path.replaceFirst(RegExp(r'/+$'), '');
    final url = rootUri.replace(
      path: '$basePath/api/v4/workspaces',
      queryParameters: {'member_npub': identityNpub},
    );
    final authorization = NostrCrypto.signNip98(
      secret: secret,
      method: 'GET',
      url: url.toString(),
    ).authorization;
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: abort.future,
    )
      ..followRedirects = false
      ..headers['accept'] = 'application/json'
      ..headers['authorization'] = authorization;
    try {
      final bytes = await _read(request).timeout(timeout, onTimeout: () {
        abort.complete();
        throw TimeoutException('Workspace discovery timed out.');
      });
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw const NStackDiscoveryException(
            'invalid_response', 'NStack returned malformed workspace data.');
      }
      return validateWorkspaceDiscoveryResponse(decoded);
    } on NStackDiscoveryException {
      rethrow;
    } on TimeoutException {
      throw const NStackDiscoveryException(
          'timeout', 'Workspace discovery timed out.');
    } catch (_) {
      throw const NStackDiscoveryException(
          'network_error', 'NStack workspace discovery failed.');
    }
  }

  Future<List<int>> _read(http.BaseRequest request) async {
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw NStackDiscoveryException('http_error',
          'NStack returned HTTP ${response.statusCode} during discovery.');
    }
    if (response.contentLength case final length?
        when length > nstackWorkspaceResponseMaxBytes) {
      throw const NStackDiscoveryException(
          'invalid_response', 'Workspace response is too large.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length > nstackWorkspaceResponseMaxBytes) {
        throw const NStackDiscoveryException(
            'invalid_response', 'Workspace response is too large.');
      }
    }
    return bytes;
  }
}

List<NStackWorkspace> validateWorkspaceDiscoveryResponse(Object? value) {
  if (value is! Map<String, dynamic> || value['workspaces'] is! List) {
    throw const NStackDiscoveryException(
        'invalid_response', 'NStack workspace response has an invalid shape.');
  }
  final rawWorkspaces = value['workspaces'] as List;
  if (rawWorkspaces.length > 1000) {
    throw const NStackDiscoveryException(
        'invalid_response', 'NStack returned too many workspaces.');
  }
  final result = <NStackWorkspace>[];
  final stableIds = <String>{};
  for (final raw in rawWorkspaces) {
    if (raw is! Map<String, dynamic>) {
      throw const NStackDiscoveryException(
          'invalid_response', 'NStack returned an invalid workspace.');
    }
    final workspaceId = _safeText(raw['workspace_id'], 128);
    final name = _safeText(raw['name'], 256);
    final owner = _validNpub(raw['workspace_owner_npub']);
    final workspaceService =
        _validNpub(raw['workspace_service_npub'] ?? raw['workspace_npub']);
    final directUrl = raw['direct_https_url'] == null
        ? null
        : canonicalNStackUrl(raw['direct_https_url'].toString());
    final service =
        raw['service_npub'] == null ? null : _validNpub(raw['service_npub']);
    if (workspaceId == null ||
        name == null ||
        owner == null ||
        workspaceService == null ||
        (raw['direct_https_url'] != null && directUrl == null) ||
        (raw['service_npub'] != null && service == null) ||
        !stableIds.add(workspaceId)) {
      throw const NStackDiscoveryException('invalid_response',
          'NStack returned incomplete, invalid, or duplicate workspace identity.');
    }
    result.add(NStackWorkspace(
      id: '',
      name: name,
      remoteId: workspaceId,
      workspaceOwnerNpub: owner,
      workspaceServiceNpub: workspaceService,
      directHttpsUrl: directUrl,
      serviceNpub: service,
    ));
  }
  return List.unmodifiable(result);
}

class NStackWorkspaceDiscoveryService {
  NStackWorkspaceDiscoveryService({
    required this.registryStore,
    NStackWorkspaceDiscovery? discovery,
    DateTime Function()? clock,
  })  : discovery = discovery ?? TowerNStackWorkspaceDiscovery(),
        _clock = clock ?? DateTime.now;

  final NStackRegistryStore registryStore;
  final NStackWorkspaceDiscovery discovery;
  final DateTime Function() _clock;

  Future<NStackEntry> add({
    required String identityNpub,
    required String secret,
    required String address,
  }) async {
    final canonical = canonicalNStackUrl(address);
    if (canonical == null) {
      throw const NStackDiscoveryException(
          'invalid_address', 'Enter a valid HTTPS NStack address.');
    }
    final registry = await registryStore.load(identityNpub);
    final existing =
        registry.stacks.where((stack) => stack.url == canonical).firstOrNull;
    if (existing != null) {
      return refresh(
        identityNpub: identityNpub,
        secret: secret,
        stackId: existing.id,
      );
    }
    final discovered = await discovery.discover(
      address: canonical,
      identityNpub: identityNpub,
      secret: secret,
    );
    final candidate = NStackEntry(
      id: newNStackOpaqueId(),
      name: Uri.parse(canonical).host,
      url: canonical,
    );
    return registryStore.applyWorkspaceDiscovery(
      identityNpub,
      candidate: candidate,
      discovered: discovered,
      refreshedAt: _clock().toUtc(),
    );
  }

  Future<NStackEntry> changeAddress({
    required String identityNpub,
    required String secret,
    required String stackId,
    required String address,
  }) async {
    final canonical = canonicalNStackUrl(address);
    if (canonical == null) {
      throw const NStackDiscoveryException(
          'invalid_address', 'Enter a valid HTTPS NStack address.');
    }
    final registry = await registryStore.load(identityNpub);
    final current =
        registry.stacks.where((stack) => stack.id == stackId).firstOrNull;
    if (current == null) throw StateError('NStack no longer exists.');
    if (registry.stacks
        .any((stack) => stack.id != stackId && stack.url == canonical)) {
      throw const NStackDiscoveryException(
          'duplicate_address', 'That NStack address is already saved.');
    }
    final discovered = await discovery.discover(
      address: canonical,
      identityNpub: identityNpub,
      secret: secret,
    );
    return registryStore.applyWorkspaceDiscovery(
      identityNpub,
      candidate: current.copyWith(url: canonical),
      expectedPreviousUrl: current.url,
      discovered: discovered,
      refreshedAt: _clock().toUtc(),
    );
  }

  Future<NStackEntry> refresh({
    required String identityNpub,
    required String secret,
    required String stackId,
  }) async {
    final registry = await registryStore.load(identityNpub);
    final stack =
        registry.stacks.where((item) => item.id == stackId).firstOrNull;
    if (stack == null) throw StateError('NStack no longer exists.');
    final attemptedAt = _clock().toUtc();
    try {
      final discovered = await discovery.discover(
        address: stack.url,
        identityNpub: identityNpub,
        secret: secret,
      );
      return registryStore.applyWorkspaceDiscovery(
        identityNpub,
        candidate: stack,
        discovered: discovered,
        refreshedAt: attemptedAt,
      );
    } on NStackDiscoveryException catch (error) {
      await registryStore.markWorkspaceDiscoveryFailure(
        identityNpub,
        stackId: stack.id,
        expectedUrl: stack.url,
        attemptedAt: attemptedAt,
        errorCode: error.code,
        errorMessage: error.message,
      );
      rethrow;
    }
  }
}

String? _safeText(Object? value, int maximum) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximum ||
      value.trim() != value ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return null;
  }
  return value;
}

String? _validNpub(Object? value) {
  final text = _safeText(value, 128);
  if (text == null) return null;
  try {
    NostrCrypto.publicKeyHexFromNpub(text);
    return text;
  } catch (_) {
    return null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
