import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wingman_app/src/core/app_config.dart';
import 'package:wingman_app/src/core/nostr_crypto.dart';
import 'package:wingman_app/src/features/nstack/nstack_access.dart';
import 'package:wingman_app/src/features/nstack/nstack_discovery.dart';
import 'package:wingman_app/src/features/nstack/nstack_models.dart';
import 'package:wingman_app/src/features/nstack/nstack_recovery.dart';
import 'package:wingman_app/src/features/nstack/nstack_screen.dart';
import 'package:wingman_app/src/features/nstack/nstack_store.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('management surface shows host and revokes origin discovery',
      (tester) async {
    const identity = 'npub-test';
    final registry = NStackRegistryStore();
    await registry.addOrUpdate(
      identity,
      const NStackEntry(
        id: 'stack-a',
        name: 'Personal NStack',
        url: 'https://host.example',
      ),
      makeActive: true,
      makeHost: true,
    );
    final grants = NStackGrantStore();
    final access =
        NStackAccessService(registryStore: registry, grantStore: grants);
    await access.disclose(
      identity: identity,
      origin: 'https://ambulando.example',
      stackInternalIds: const ['stack-a'],
      includeWorkspaces: false,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NStackScreen(
          config: AppConfig.defaults().copyWith(
            deviceNpub: identity,
            devicePublicKeyHex: '1'.padLeft(64, '0'),
            deviceSecret: 'secret-present',
          ),
          registryStore: registry,
          grantStore: grants,
          accessService: access,
          discoveryService: NStackWorkspaceDiscoveryService(
            registryStore: registry,
            discovery: _NoDiscovery(),
          ),
          recoveryService: NStackRecoveryService(
            registryStore: registry,
            storage: _NoStorage(),
            relay: _NoRelay(),
          ),
          onRegistryChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Personal NStack'), findsOneWidget);
    expect(find.text('https://host.example\n0 workspace(s)'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('https://ambulando.example'), 300);
    expect(find.textContaining('https://ambulando.example'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(await grants.list(identity), isEmpty);
    expect(find.text('No websites can discover saved connections.'),
        findsOneWidget);
  });

  testWidgets('add flow asks only for address and shows discovered empty state',
      (tester) async {
    const identity = 'npub-test';
    final registry = NStackRegistryStore();
    final grants = NStackGrantStore();
    final access =
        NStackAccessService(registryStore: registry, grantStore: grants);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NStackScreen(
          config: AppConfig.defaults().copyWith(
            deviceNpub: identity,
            devicePublicKeyHex: '1'.padLeft(64, '0'),
            deviceSecret: 'secret-present',
          ),
          registryStore: registry,
          grantStore: grants,
          accessService: access,
          discoveryService: NStackWorkspaceDiscoveryService(
            registryStore: registry,
            discovery: _EmptyDiscovery(),
            clock: () => DateTime.utc(2026, 10, 19),
          ),
          recoveryService: NStackRecoveryService(
            registryStore: registry,
            storage: _NoStorage(),
            relay: _NoRelay(),
          ),
          onRegistryChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-nstack')));
    await tester.pumpAndSettle();
    expect(find.text('NStack HTTPS address'), findsOneWidget);
    expect(find.text('Name'), findsNothing);
    expect(find.text('Workspaces'), findsNothing);
    expect(find.textContaining('FIPS endpoint'), findsNothing);
    await tester.enterText(find.byType(TextField), 'https://stack.example/');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('stack.example'), findsOneWidget);
    expect(find.text('No accessible workspaces'), findsOneWidget);
  });

  testWidgets(
      'first save accepts live-shaped proxy downgrade and lists every usable workspace',
      (tester) async {
    const secret =
        '0000000000000000000000000000000000000000000000000000000000000001';
    final identity = NostrCrypto.importIdentity(secret);
    final workspaceService = NostrCrypto.importIdentity(
        '0000000000000000000000000000000000000000000000000000000000000002');
    final towerService = NostrCrypto.importIdentity(
        '0000000000000000000000000000000000000000000000000000000000000003');
    final registry = NStackRegistryStore();
    final grants = NStackGrantStore();
    final access =
        NStackAccessService(registryStore: registry, grantStore: grants);
    final client = MockClient((request) async {
      if (request.url.path == '/api/v4/workspaces') {
        return http.Response(jsonEncode({'workspaces': []}), 200);
      }
      return http.Response(
          jsonEncode({
            'identity': {
              'tower_service_npub': null,
              'workspace_service_npub': null,
              'workspace_owner_npub': null,
              'workspace_id': null,
              'app_npub': towerService.npub,
            },
            'workspaces': [
              {
                'identity': {
                  'workspace_id': 'workspace-owner',
                  'workspace_owner_npub': identity.npub,
                  'workspace_service_npub': workspaceService.npub,
                  'tower_service_npub': towerService.npub,
                },
                'label': 'Owner workspace',
                'tower_base_url': 'http://stack.example',
                'v4_workspace_id': null,
                'membership': {'role': 'owner'},
              },
              {
                'identity': {
                  'workspace_id': 'workspace-member',
                  'workspace_owner_npub': towerService.npub,
                  'workspace_service_npub': workspaceService.npub,
                  'tower_service_npub': towerService.npub,
                },
                'label': 'Member workspace',
                'tower_base_url': 'http://stack.example',
                'v4_workspace_id': null,
                'membership': {'role': 'member'},
              },
            ],
            'next_cursor': null,
          }),
          200);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NStackScreen(
          config: AppConfig.defaults().copyWith(
            deviceNpub: identity.npub,
            devicePublicKeyHex: identity.publicKeyHex,
            deviceSecret: secret,
          ),
          registryStore: registry,
          grantStore: grants,
          accessService: access,
          discoveryService: NStackWorkspaceDiscoveryService(
            registryStore: registry,
            discovery: TowerNStackWorkspaceDiscovery(client: client),
          ),
          recoveryService: NStackRecoveryService(
            registryStore: registry,
            storage: _NoStorage(),
            relay: _NoRelay(),
          ),
          onRegistryChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-nstack')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://stack.example');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Owner workspace'), findsOneWidget);
    expect(find.text('Member workspace'), findsOneWidget);
    final saved = (await registry.load(identity.npub)).stacks.single;
    expect(saved.workspaces, hasLength(2));
    expect(
        saved.workspaces.map((workspace) => workspace.directHttpsUrl).toSet(),
        {'https://stack.example'});
    expect(saved.workspaceDiscovery?.stale, isFalse);
  });

  testWidgets('identity switch never presents the previous identity registry',
      (tester) async {
    const identityA = 'npub-a';
    const identityB = 'npub-b';
    final registry = NStackRegistryStore();
    await registry.addOrUpdate(
      identityA,
      const NStackEntry(
          id: 'stack-a', name: 'Identity A stack', url: 'https://a.example'),
    );
    await registry.addOrUpdate(
      identityB,
      const NStackEntry(
          id: 'stack-b', name: 'Identity B stack', url: 'https://b.example'),
    );
    final grants = NStackGrantStore();
    final access =
        NStackAccessService(registryStore: registry, grantStore: grants);
    late StateSetter updateHost;
    var activeIdentity = identityA;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        updateHost = setState;
        return Scaffold(
          body: NStackScreen(
            config: AppConfig.defaults().copyWith(
              deviceNpub: activeIdentity,
              devicePublicKeyHex: '1'.padLeft(64, '0'),
              deviceSecret: 'secret-present',
            ),
            registryStore: registry,
            grantStore: grants,
            accessService: access,
            discoveryService: NStackWorkspaceDiscoveryService(
              registryStore: registry,
              discovery: _NoDiscovery(),
            ),
            recoveryService: NStackRecoveryService(
              registryStore: registry,
              storage: _NoStorage(),
              relay: _NoRelay(),
            ),
            onRegistryChanged: () {},
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Identity A stack'), findsOneWidget);

    updateHost(() => activeIdentity = identityB);
    await tester.pump();
    expect(find.text('Identity A stack'), findsNothing,
        reason: 'the old registry must clear synchronously on identity change');
    await tester.pumpAndSettle();
    expect(find.text('Identity B stack'), findsOneWidget);
    expect(find.text('Identity A stack'), findsNothing);
  });

  testWidgets('locked native identity cannot add or refresh NStacks',
      (tester) async {
    const identity = 'npub-locked';
    final registry = NStackRegistryStore();
    await registry.addOrUpdate(
      identity,
      const NStackEntry(
          id: 'stack-a', name: 'Locked stack', url: 'https://a.example'),
    );
    final grants = NStackGrantStore();
    final access =
        NStackAccessService(registryStore: registry, grantStore: grants);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NStackScreen(
          config: AppConfig.defaults().copyWith(deviceNpub: identity),
          registryStore: registry,
          grantStore: grants,
          accessService: access,
          discoveryService: NStackWorkspaceDiscoveryService(
              registryStore: registry, discovery: _NoDiscovery()),
          recoveryService: NStackRecoveryService(
              registryStore: registry,
              storage: _NoStorage(),
              relay: _NoRelay()),
          onRegistryChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('website login inside a tab'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('add-nstack')))
            .onPressed,
        isNull);
    expect(
      tester
          .widget<IconButton>(find.byWidgetPredicate((widget) =>
              widget is IconButton &&
              widget.tooltip == 'Refresh Locked stack workspaces'))
          .onPressed,
      isNull,
    );
  });
}

class _NoDiscovery implements NStackWorkspaceDiscovery {
  @override
  Future<List<NStackWorkspace>> discover({
    required String address,
    required String identityNpub,
    required String secret,
  }) =>
      throw UnimplementedError();
}

class _EmptyDiscovery implements NStackWorkspaceDiscovery {
  @override
  Future<List<NStackWorkspace>> discover({
    required String address,
    required String identityNpub,
    required String secret,
  }) async =>
      const [];
}

class _NoStorage implements NStackStorageClient {
  @override
  Future<List<int>> fetch(
          {required String hostUrl,
          required String objectId,
          required String secret,
          required String expectedSha256}) =>
      throw UnimplementedError();

  @override
  Future<String> upload(
          {required String hostUrl,
          required String ownerNpub,
          required String secret,
          required List<int> bytes,
          required String sha256}) =>
      throw UnimplementedError();
}

class _NoRelay implements NStackRecoveryRelay {
  @override
  List<String> get relays => const ['wss://relay.example'];

  @override
  Future<List<Map<String, dynamic>>> fetchHints(String publicKeyHex) async =>
      const [];

  @override
  Future<NStackRelayPublishResult> publish(Map<String, dynamic> event) =>
      throw UnimplementedError();
}
