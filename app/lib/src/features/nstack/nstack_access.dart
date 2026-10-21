import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nstack_models.dart';
import 'nstack_store.dart';

class NStackException implements Exception {
  const NStackException(this.code, this.message);
  final String code;
  final String message;

  Map<String, String> toJson() => {'code': code, 'message': message};
  @override
  String toString() => '$code: $message';
}

class NStackDiscoveryGrant {
  const NStackDiscoveryGrant({
    required this.origin,
    required this.stackIds,
    required this.workspaceIds,
    required this.updatedAt,
  });

  final String origin;
  final Map<String, String> stackIds;
  final Map<String, String> workspaceIds;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'origin': origin,
        'stack_ids': stackIds,
        'workspace_ids': workspaceIds,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  static NStackDiscoveryGrant? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final origin = normalizeNStackOrigin(value['origin']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(value['updated_at']?.toString() ?? '');
    if (origin.isEmpty || updatedAt == null) return null;
    Map<String, String>? map(Object? raw) {
      if (raw is! Map) return null;
      final result = <String, String>{};
      for (final entry in raw.entries) {
        final key = entry.key.toString().trim();
        final id = entry.value.toString().trim();
        if (key.isEmpty || id.isEmpty || result.containsValue(id)) return null;
        result[key] = id;
      }
      return result;
    }

    final stackIds = map(value['stack_ids']);
    final workspaceIds = map(value['workspace_ids']);
    if (stackIds == null || workspaceIds == null) return null;
    return NStackDiscoveryGrant(
      origin: origin,
      stackIds: Map.unmodifiable(stackIds),
      workspaceIds: Map.unmodifiable(workspaceIds),
      updatedAt: updatedAt.toUtc(),
    );
  }
}

class NStackGrantStore extends ChangeNotifier {
  NStackGrantStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const keyPrefix = 'wingman.nstack.discovery-grants.v1.';
  final SharedPreferencesAsync _preferences;
  final Map<String, Map<String, NStackDiscoveryGrant>> _cache = {};

  Future<List<NStackDiscoveryGrant>> list(String signerNpub) async {
    final grants = await _load(signerNpub);
    return List.unmodifiable(grants.values);
  }

  Future<NStackDiscoveryGrant?> find(String signerNpub, String origin) async {
    return (await _load(signerNpub))[normalizeNStackOrigin(origin)];
  }

  Future<void> put(String signerNpub, NStackDiscoveryGrant grant) async {
    final identity = signerNpub.trim();
    if (identity.isEmpty || grant.origin.isEmpty) {
      throw const NStackException('locked', 'Unlock a Nostr identity first.');
    }
    final grants =
        Map<String, NStackDiscoveryGrant>.from(await _load(identity));
    grants[grant.origin] = grant;
    await _save(identity, grants);
  }

  Future<void> revokeOrigin(String signerNpub, String origin) async {
    final identity = signerNpub.trim();
    final grants =
        Map<String, NStackDiscoveryGrant>.from(await _load(identity));
    grants.remove(normalizeNStackOrigin(origin));
    await _save(identity, grants);
  }

  Future<Map<String, NStackDiscoveryGrant>> _load(String signerNpub) async {
    final identity = signerNpub.trim();
    if (identity.isEmpty) return const {};
    final cached = _cache[identity];
    if (cached != null) return cached;
    final result = <String, NStackDiscoveryGrant>{};
    final raw = await _preferences.getString('$keyPrefix$identity');
    try {
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['version'] == 1 &&
          decoded['grants'] is List) {
        for (final item in decoded['grants'] as List) {
          final grant = NStackDiscoveryGrant.tryParse(item);
          if (grant != null) result[grant.origin] = grant;
        }
      }
    } catch (_) {/* Corrupt grants fail closed. */}
    _cache[identity] = result;
    return result;
  }

  Future<void> _save(
      String identity, Map<String, NStackDiscoveryGrant> grants) async {
    await _preferences.setString(
      '$keyPrefix$identity',
      jsonEncode({
        'version': 1,
        'grants': [for (final grant in grants.values) grant.toJson()],
      }),
    );
    _cache[identity] = grants;
    notifyListeners();
  }
}

class NStackAccessService extends ChangeNotifier {
  NStackAccessService({
    required this.registryStore,
    required this.grantStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NStackRegistryStore registryStore;
  final NStackGrantStore grantStore;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> applyDiscoveryDecision({
    required String identity,
    required String origin,
    required Set<String>? approvedStackInternalIds,
    required bool includeWorkspaces,
  }) {
    if (approvedStackInternalIds == null) {
      throw const NStackException(
          'consent_denied', 'NStack discovery was denied.');
    }
    return disclose(
      identity: identity,
      origin: origin,
      stackInternalIds: approvedStackInternalIds.toList(),
      includeWorkspaces: includeWorkspaces,
    );
  }

  Future<Map<String, dynamic>> disclose({
    required String identity,
    required String origin,
    required List<String> stackInternalIds,
    required bool includeWorkspaces,
  }) async {
    _requireIdentity(identity);
    final normalizedOrigin = _requireOrigin(origin);
    final registry = await registryStore.load(identity);
    final requested = stackInternalIds.toSet();
    if (requested.isEmpty ||
        requested.any((id) => !registry.stacks.any((s) => s.id == id))) {
      throw const NStackException(
          'invalid_request', 'Select at least one available NStack.');
    }
    final old = await grantStore.find(identity, normalizedOrigin);
    final stackIds = <String, String>{};
    final workspaceIds = <String, String>{};
    for (final stack
        in registry.stacks.where((s) => requested.contains(s.id))) {
      stackIds[stack.id] = old?.stackIds[stack.id] ?? newNStackOpaqueId();
      if (includeWorkspaces) {
        for (final workspace
            in stack.workspaces.where((item) => item.isDiscovered)) {
          final key = '${stack.id}/${workspace.id}';
          workspaceIds[key] = old?.workspaceIds[key] ?? newNStackOpaqueId();
        }
      }
    }
    final grant = NStackDiscoveryGrant(
      origin: normalizedOrigin,
      stackIds: Map.unmodifiable(stackIds),
      workspaceIds: Map.unmodifiable(workspaceIds),
      updatedAt: _clock().toUtc(),
    );
    await grantStore.put(identity, grant);
    notifyListeners();
    return {'disclosed': stackIds.length, 'workspaces': includeWorkspaces};
  }

  Future<List<Map<String, dynamic>>> listNStacks(
      String identity, String origin) async {
    final state = await _state(identity, origin);
    final registry = state.$1;
    final grant = state.$2;
    return [
      for (final stack in registry.stacks)
        if (grant.stackIds[stack.id] case final opaque?)
          {
            'id': opaque,
            'name': stack.name,
            'url': stack.url,
            'host': registry.hostStackId == stack.id,
            'available': true,
            'stale': stack.workspaceDiscovery?.stale ?? true,
            'lastRefreshedAt':
                stack.workspaceDiscovery?.lastSuccessAt?.toIso8601String(),
          },
    ];
  }

  Future<List<Map<String, dynamic>>> listWorkspaces({
    required String identity,
    required String origin,
    required String stackId,
  }) async {
    final state = await _state(identity, origin);
    final internalStackId = _internalId(state.$2.stackIds, stackId);
    if (internalStackId == null) {
      throw const NStackException(
          'not_disclosed', 'The NStack was not disclosed to this origin.');
    }
    final stack =
        state.$1.stacks.where((s) => s.id == internalStackId).firstOrNull;
    if (stack == null) {
      throw const NStackException(
          'stack_unavailable', 'The disclosed NStack is no longer available.');
    }
    return [
      for (final workspace in stack.workspaces)
        if (workspace.isDiscovered)
          if (state.$2.workspaceIds['${stack.id}/${workspace.id}']
              case final opaque?)
            _workspaceDescriptor(stackId, opaque, stack, workspace),
    ];
  }

  Future<Map<String, dynamic>> getConnection({
    required String identity,
    required String origin,
    required String stackId,
    required String workspaceId,
  }) async {
    final state = await _state(identity, origin);
    final internalStackId = _internalId(state.$2.stackIds, stackId);
    if (internalStackId == null) {
      throw const NStackException(
          'not_disclosed', 'The NStack was not disclosed to this origin.');
    }
    final stack =
        state.$1.stacks.where((s) => s.id == internalStackId).firstOrNull;
    if (stack == null) {
      throw const NStackException(
          'stack_unavailable', 'The NStack is no longer available.');
    }
    final scoped = <String, String>{
      for (final entry in state.$2.workspaceIds.entries)
        if (entry.key.startsWith('$internalStackId/')) entry.key: entry.value,
    };
    final internalKey = _internalId(scoped, workspaceId);
    if (internalKey == null) {
      throw const NStackException(
          'not_disclosed', 'The workspace was not disclosed to this origin.');
    }
    final internalWorkspaceId =
        internalKey.substring(internalKey.indexOf('/') + 1);
    final workspace = stack.workspaces
        .where((item) => item.id == internalWorkspaceId && item.isDiscovered)
        .firstOrNull;
    if (workspace == null) {
      throw const NStackException('stack_unavailable',
          'The disclosed workspace is no longer available.');
    }
    return _workspaceDescriptor(stackId, workspaceId, stack, workspace);
  }

  Future<Map<String, dynamic>> getServiceCatalogue({
    required String identity,
    required String origin,
    required String stackId,
  }) async {
    final state = await _state(identity, origin);
    final internalStackId = _internalId(state.$2.stackIds, stackId);
    if (internalStackId == null) {
      throw const NStackException(
          'not_disclosed', 'The NStack was not disclosed to this origin.');
    }
    final stack =
        state.$1.stacks.where((s) => s.id == internalStackId).firstOrNull;
    if (stack == null) {
      throw const NStackException(
          'stack_unavailable', 'The disclosed NStack is no longer available.');
    }
    final status = stack.catalogueStatus;
    final catalogue = status?.catalogue;
    return {
      'stackId': stackId,
      'checkedAt': status?.checkedAt.toUtc().toIso8601String(),
      'fetchedAt': catalogue?.fetchedAt.toUtc().toIso8601String(),
      'stale': catalogue == null || catalogue.isStaleAt(_clock()),
      if (status?.errorCode != null)
        'error': {'code': status!.errorCode, 'message': status.errorMessage},
      'services': [
        for (final service in catalogue?.services ?? const <NStackService>[])
          {
            'id': service.id,
            'kind': service.kind,
            'endpoint': service.endpoint,
            'version': service.version,
            'protocols': service.protocols,
            'capabilities': service.capabilities,
            'features': {'nips': service.nips, 'buds': service.buds},
            'availability': {
              'status': service.availability.name,
              'checkedAt': service.checkedAt?.toUtc().toIso8601String(),
            },
            'actionable': service.actionable,
          },
      ],
    };
  }

  // Kept as no-ops while native callers migrate away from the earlier handle
  // model. Document/origin validation is enforced by the browser dispatcher.
  void revokeDocument(String documentId) {}

  Future<void> revokeOrigin(String identity, String origin) async {
    final normalized = normalizeNStackOrigin(origin);
    await grantStore.revokeOrigin(identity, normalized);
    notifyListeners();
  }

  void revokeIdentity(String identity) {}

  void revokeStack(String stackInternalId) {}

  Future<(NStackRegistry, NStackDiscoveryGrant)> _state(
      String identity, String origin) async {
    _requireIdentity(identity);
    final normalizedOrigin = _requireOrigin(origin);
    final grant = await grantStore.find(identity, normalizedOrigin);
    if (grant == null) {
      throw const NStackException(
          'not_disclosed', 'Request NStack discovery first.');
    }
    return (await registryStore.load(identity), grant);
  }

  void _requireIdentity(String identity) {
    if (identity.trim().isEmpty) {
      throw const NStackException('locked', 'Unlock a Nostr identity first.');
    }
  }

  String _requireOrigin(String origin) {
    final normalized = normalizeNStackOrigin(origin);
    if (normalized.isEmpty) {
      throw const NStackException(
          'invalid_request', 'A verified HTTPS or local origin is required.');
    }
    return normalized;
  }
}

Map<String, dynamic> _workspaceDescriptor(
  String stackAlias,
  String workspaceAlias,
  NStackEntry stack,
  NStackWorkspace workspace,
) =>
    {
      'id': workspaceAlias,
      'name': workspace.name,
      'workspaceId': workspace.remoteId,
      'workspaceOwnerNpub': workspace.workspaceOwnerNpub,
      'workspaceServiceNpub': workspace.workspaceServiceNpub,
      'directHttpsUrl': workspace.directHttpsUrl ?? stack.url,
      if (workspace.serviceNpub != null) 'serviceNpub': workspace.serviceNpub,
      'nstack': {
        'id': stackAlias,
        'name': stack.name,
        'url': stack.url,
      },
    };

String? _internalId(Map<String, String> ids, String opaque) {
  for (final entry in ids.entries) {
    if (entry.value == opaque) return entry.key;
  }
  return null;
}

String normalizeNStackOrigin(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return '';
  final scheme = uri.scheme.toLowerCase();
  final local = {'localhost', '127.0.0.1', '::1', 'wingman.local'}
      .contains(uri.host.toLowerCase());
  if (scheme != 'https' && !(scheme == 'http' && local)) return '';
  // Must equal the page's `location.origin`; the injected provider refuses to
  // install for any other value. `Uri.replace(query: '', fragment: '')` would
  // serialize an empty query and fragment as `?#`.
  return uri.origin;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
