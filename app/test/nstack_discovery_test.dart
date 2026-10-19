import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wingman_app/src/core/nostr_crypto.dart';
import 'package:wingman_app/src/features/browser/browser_bookmark_store.dart';
import 'package:wingman_app/src/features/nstack/nstack_discovery.dart';
import 'package:wingman_app/src/features/nstack/nstack_models.dart';
import 'package:wingman_app/src/features/nstack/nstack_store.dart';

void main() {
  const secret =
      '0000000000000000000000000000000000000000000000000000000000000001';
  final identity = NostrCrypto.importIdentity(secret);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('discovers multiple workspaces with exact fresh NIP-98 GET binding',
      () async {
    final other = NostrCrypto.importIdentity(
        '0000000000000000000000000000000000000000000000000000000000000002');
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      final event = _authorizationEvent(request);
      expect(NostrCrypto.verifyEvent(event), isTrue);
      expect(_tag(event, 'u'), request.url.toString());
      expect(_tag(event, 'method'), 'GET');
      expect(request.url.toString(),
          'https://stack.example/base/api/v4/workspaces?member_npub=${Uri.encodeQueryComponent(identity.npub)}');
      return http.Response(
          jsonEncode({
            'workspaces': [
              _workspace('workspace-a', 'Alpha', identity.npub,
                  extra: {'wrapped_workspace_nsec': 'must-not-persist'}),
              _workspace('workspace-b', 'Beta', other.npub),
            ],
          }),
          200);
    });
    final discovery = TowerNStackWorkspaceDiscovery(client: client);
    final result = await discovery.discover(
      address: 'https://STACK.example/base/',
      identityNpub: identity.npub,
      secret: secret,
    );
    expect(result.map((workspace) => workspace.name), ['Alpha', 'Beta']);
    expect(result.first.toJson().toString(), isNot(contains('wrapped')));
    expect(requests, hasLength(1));
  });

  test('accepts an authenticated empty workspace list', () async {
    final discovery = TowerNStackWorkspaceDiscovery(
      client: MockClient(
          (_) async => http.Response(jsonEncode({'workspaces': []}), 200)),
    );
    expect(
      await discovery.discover(
        address: 'https://stack.example',
        identityNpub: identity.npub,
        secret: secret,
      ),
      isEmpty,
    );
  });

  test('invalid response and active identity mismatch fail closed', () async {
    var calls = 0;
    final discovery = TowerNStackWorkspaceDiscovery(
      client: MockClient((_) async {
        calls++;
        return http.Response(
            jsonEncode({
              'workspaces': [
                {'workspace_id': 'workspace-a', 'name': 'Incomplete'}
              ],
            }),
            200);
      }),
    );
    await expectLater(
      discovery.discover(
        address: 'https://stack.example',
        identityNpub: identity.npub,
        secret: secret,
      ),
      throwsA(isA<NStackDiscoveryException>()
          .having((error) => error.code, 'code', 'invalid_response')),
    );
    await expectLater(
      discovery.discover(
        address: 'https://stack.example',
        identityNpub: NostrCrypto.importIdentity(
                '0000000000000000000000000000000000000000000000000000000000000003')
            .npub,
        secret: secret,
      ),
      throwsA(isA<NStackDiscoveryException>()
          .having((error) => error.code, 'code', 'identity_changed')),
    );
    expect(calls, 1, reason: 'identity mismatch must fail before networking');
  });

  test(
      'first failure saves nothing; refresh preserves last-known-good as stale',
      () async {
    final store = NStackRegistryStore();
    final fake = _SequenceDiscovery([
      const NStackDiscoveryException('network_error', 'offline'),
      [_discovered('workspace-a', 'Alpha', identity.npub)],
      const NStackDiscoveryException('timeout', 'too slow'),
    ]);
    final service = NStackWorkspaceDiscoveryService(
      registryStore: store,
      discovery: fake,
      clock: () => DateTime.utc(2026, 10, 19, 12),
    );
    await expectLater(
      service.add(
          identityNpub: identity.npub,
          secret: secret,
          address: 'https://stack.example'),
      throwsA(isA<NStackDiscoveryException>()),
    );
    expect((await store.load(identity.npub)).stacks, isEmpty);

    final added = await service.add(
        identityNpub: identity.npub,
        secret: secret,
        address: 'https://stack.example');
    await expectLater(
      service.refresh(
          identityNpub: identity.npub, secret: secret, stackId: added.id),
      throwsA(isA<NStackDiscoveryException>()),
    );
    final stale = (await store.load(identity.npub)).stacks.single;
    expect(stale.workspaces.single.remoteId, 'workspace-a');
    expect(stale.workspaceDiscovery?.stale, isTrue);
    expect(stale.workspaceDiscovery?.errorCode, 'timeout');
  });

  test('refresh merges stable aliases, removes lost access, and keeps settings',
      () async {
    final store = NStackRegistryStore();
    await store.addOrUpdate(
      identity.npub,
      const NStackEntry(
        id: 'stack-internal',
        name: 'Manual label',
        url: 'https://stack.example',
        workspaces: [
          NStackWorkspace(
              id: 'legacy-alias',
              name: 'Typed by hand',
              remoteId: 'workspace-a'),
          NStackWorkspace(
              id: 'removed-alias', name: 'Old', remoteId: 'workspace-old'),
        ],
        settings: NStackBrowserSettings(bookmarks: [
          BrowserBookmark(title: 'Canopy', url: 'https://canopy.example')
        ]),
      ),
      makeActive: true,
    );
    final service = NStackWorkspaceDiscoveryService(
      registryStore: store,
      discovery: _SequenceDiscovery([
        [
          _discovered('workspace-a', 'Server Alpha', identity.npub),
          _discovered('workspace-b', 'Server Beta', identity.npub),
        ]
      ]),
    );
    final refreshed = await service.refresh(
        identityNpub: identity.npub, secret: secret, stackId: 'stack-internal');
    expect(refreshed.name, 'stack.example');
    expect(refreshed.workspaces.map((item) => item.remoteId),
        ['workspace-a', 'workspace-b']);
    expect(refreshed.workspaces.first.id, 'legacy-alias');
    expect(refreshed.settings.bookmarks.single.title, 'Canopy');

    final roundTrip = NStackRegistry.decode(
        jsonEncode((await store.load(identity.npub)).toJson()));
    expect(roundTrip?.stacks.single.workspaces.first.workspaceOwnerNpub,
        identity.npub);
    expect(roundTrip?.stacks.single.workspaceDiscovery?.stale, isFalse);
  });
}

Map<String, dynamic> _authorizationEvent(http.Request request) =>
    jsonDecode(utf8.decode(base64Decode(
            request.headers['authorization']!.substring('Nostr '.length))))
        as Map<String, dynamic>;

String? _tag(Map<String, dynamic> event, String name) {
  for (final raw in event['tags'] as List) {
    final tag = raw as List;
    if (tag.length == 2 && tag[0] == name) return tag[1] as String;
  }
  return null;
}

Map<String, dynamic> _workspace(String id, String name, String npub,
        {Map<String, dynamic> extra = const {}}) =>
    {
      'workspace_id': id,
      'workspace_owner_npub': npub,
      'workspace_service_npub': npub,
      'name': name,
      'direct_https_url': 'https://tower.example',
      'service_npub': npub,
      ...extra,
    };

NStackWorkspace _discovered(String id, String name, String npub) =>
    NStackWorkspace(
      id: '',
      name: name,
      remoteId: id,
      workspaceOwnerNpub: npub,
      workspaceServiceNpub: npub,
      directHttpsUrl: 'https://tower.example',
      serviceNpub: npub,
    );

class _SequenceDiscovery implements NStackWorkspaceDiscovery {
  _SequenceDiscovery(this.results);
  final List<Object> results;

  @override
  Future<List<NStackWorkspace>> discover({
    required String address,
    required String identityNpub,
    required String secret,
  }) async {
    final result = results.removeAt(0);
    if (result is NStackDiscoveryException) throw result;
    return result as List<NStackWorkspace>;
  }
}
