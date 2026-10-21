import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wingman_app/src/core/app_config.dart';
import 'package:wingman_app/src/core/nostr_crypto.dart';
import 'package:wingman_app/src/features/nstack/nstack_access.dart';
import 'package:wingman_app/src/features/nstack/nstack_workspace_discovery.dart';
import 'package:wingman_app/src/features/nstack/nstack_models.dart';
import 'package:wingman_app/src/features/nstack/nstack_recovery.dart';
import 'package:wingman_app/src/features/nstack/nstack_screen.dart';
import 'package:wingman_app/src/features/nstack/nstack_store.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final width in [320.0, 375.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('readable NStack at $width with text scale $scale',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final evidence = Platform.environment['NSTACK_SCREENSHOTS'];
        if (evidence != null) {
          final fonts = Platform.environment['NSTACK_FONT_DIRECTORY']!;
          for (final entry in {
            'LayoutEvidence': 'Roboto-Regular.ttf',
            'MaterialIcons': 'MaterialIcons-Regular.otf',
          }.entries) {
            final font = FontLoader(entry.key)
              ..addFont(Future.value(ByteData.sublistView(
                  File('$fonts/${entry.value}').readAsBytesSync())));
            await font.load();
          }
        }
        final registry = NStackRegistryStore();
        final stack = _backupStackWithTwoWorkspaces.copyWith(
            name: 'Home NStack',
            towerNpub: _workspaceOwner,
            workspaces: [
              for (final workspace in _backupStackWithTwoWorkspaces.workspaces)
                NStackWorkspace.tryParse({
                  ...workspace.toJson(),
                  'name': workspace.id == 'workspace-b'
                      ? List.filled(12, 'Operations').join(' ')
                      : 'Home'
                })!
            ],
            workspaceDiscovery: NStackWorkspaceDiscoveryStatus(
                lastAttemptAt: DateTime.utc(2026, 10, 20), stale: false));
        await registry.addOrUpdate('npub-test', stack, makeActive: true);
        final grants = NStackGrantStore();
        final access =
            NStackAccessService(registryStore: registry, grantStore: grants);
        final capture = GlobalKey();
        final discovery = _PendingDiscovery();
        await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(fontFamily: evidence == null ? null : 'LayoutEvidence'),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: RepaintBoundary(
              key: capture,
              child: Scaffold(
                  body: NStackScreen(
                config: AppConfig.defaults().copyWith(
                    deviceNpub: 'npub-test', deviceSecret: 'secret-present'),
                registryStore: registry,
                grantStore: grants,
                accessService: access,
                discoveryService: NStackWorkspaceDiscoveryService(
                    registryStore: registry, discovery: discovery),
                recoveryService: NStackRecoveryService(
                    registryStore: registry,
                    storage: _NamespaceStorage(),
                    relay: _NoRelay()),
                onRegistryChanged: () {},
              ))),
        ));
        await tester.pumpAndSettle();
        final name = find.byKey(const ValueKey('nstack-name-stack-a'));
        await tester.scrollUntilVisible(name, 300);
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        expect(tester.getSize(name).width, greaterThan(180));
        expect(tester.getSize(name).height, lessThan(100));
        expect(tester.takeException(), isNull);
        if (evidence != null && width != 1200) {
          await tester.ensureVisible(find.byTooltip('NStack actions'));
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary = capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            File('$evidence/nstack-$width-$scale.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        final compact = width < 640 * scale + 80;
        Future<void> action(String label) async {
          await tester.scrollUntilVisible(name, -300);
          await tester.pumpAndSettle();
          if (compact) {
            await tester.ensureVisible(find.byTooltip('NStack actions'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('NStack actions'));
            await tester.pumpAndSettle();
            await tester.tap(find.text(label));
          } else {
            await tester.tap(find.byTooltip(label == 'Change address'
                ? 'Connection details and address'
                : label));
          }
          await tester.pumpAndSettle();
        }

        await action('Reveal connection details');
        expect(find.text('https://personal.example'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await action('Change address');
        expect(find.text('Change NStack address'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await action('Rename NStack');
        final longName = List.filled(12, 'Long name').join(' ');
        await tester.enterText(find.byType(TextFormField), longName);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect((await registry.load('npub-test')).activeStack!.name, longName);
        expect(tester.getSize(name).height, lessThan(100));
        expect(tester.takeException(), isNull);
        final workspace =
            find.byKey(const ValueKey('backup-workspace-stack-a-workspace-a'));
        await tester.ensureVisible(workspace);
        await tester.pumpAndSettle();
        await tester.tap(workspace);
        await tester.pumpAndSettle();
        final summary =
            find.byKey(const ValueKey('backup-destination-selected'));
        await tester.scrollUntilVisible(summary, 300);
        await tester.pumpAndSettle();
        expect(summary, findsOneWidget);
        expect(tester.takeException(), isNull);
        await action('Remove NStack');
        expect(find.text('Remove'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect((await registry.load('npub-test')).stacks, hasLength(1));
        await tester.scrollUntilVisible(name, -300);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Refresh workspaces'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Refresh workspaces'));
        await tester.pump();
        if (!compact) {
          expect(
              tester
                  .widget<IconButton>(find.widgetWithIcon(
                      IconButton, Icons.drive_file_rename_outline))
                  .onPressed,
              isNull);
        }
        if (compact) {
          expect(
              tester
                  .widget<PopupMenuButton<String>>(
                      find.byType(PopupMenuButton<String>))
                  .enabled,
              isFalse);
        }
        discovery.result.complete(const []);
        await tester.pumpAndSettle();
        expect((await registry.load('npub-test')).activeStack!.name, longName);
        expect((await registry.load('npub-test')).activeStack!.workspaces,
            isEmpty);
        expect(tester.takeException(), isNull);
        await action('Remove NStack');
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect((await registry.load('npub-test')).stacks, isEmpty);
      });
    }
  }

  testWidgets('management surface hides endpoints and revokes origin discovery',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(find.text('Identity unavailable'), findsOneWidget);
    expect(find.text('0 workspace(s)'), findsOneWidget);
    expect(find.textContaining('https://host.example'), findsNothing);
    await tester.tap(find.byTooltip('Reveal connection details'));
    await tester.pumpAndSettle();
    expect(find.text('https://host.example'), findsOneWidget);
    expect(find.byTooltip('Copy Connection address'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.textContaining('https://host.example'), findsNothing);
    await tester.tap(find.byTooltip('Rename NStack'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Home NStack');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Home NStack'), findsOneWidget);
    expect((await NStackRegistryStore().load(identity)).activeStack?.name,
        'Home NStack');

    await tester.scrollUntilVisible(find.text('Approved website'), 300);
    expect(find.textContaining('https://ambulando.example'), findsNothing);
    await access.disclose(
        identity: identity,
        origin: 'https://second.example',
        stackInternalIds: const ['stack-a'],
        includeWorkspaces: false);
    // Reopen the screen to reload both independently persisted grants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NStackScreen(
      config: AppConfig.defaults()
          .copyWith(deviceNpub: identity, deviceSecret: 'secret-present'),
      registryStore: registry,
      grantStore: grants,
      accessService: access,
      discoveryService: NStackWorkspaceDiscoveryService(
          registryStore: registry, discovery: _NoDiscovery()),
      recoveryService: NStackRecoveryService(
          registryStore: registry, storage: _NoStorage(), relay: _NoRelay()),
      onRegistryChanged: () {},
    ))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byTooltip('Reveal website origin').first, 300);
    expect(find.byTooltip('Reveal website origin'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Reveal website origin').first);
    await tester.pumpAndSettle();
    final revealed =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(['https://ambulando.example', 'https://second.example'],
        contains(revealed));
    await tester.tap(find.text('Revoke this website'));
    await tester.pumpAndSettle();
    final remaining = await grants.list(identity);
    expect(remaining, hasLength(1));
    expect(remaining.single.origin, isNot(revealed));
    expect(find.textContaining(revealed), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(await grants.list(identity), isEmpty);
    expect(find.text('No websites can discover saved connections.'),
        findsOneWidget);
  });

  testWidgets(
      'backup workspace is explicit, changeable and reports manager enablement',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final identity = NostrCrypto.importIdentity(_identitySecret);
    final registry = NStackRegistryStore();
    await registry.addOrUpdate(
      identity.npub,
      _backupStackWithTwoWorkspaces.copyWith(
        workspaceDiscovery: NStackWorkspaceDiscoveryStatus(
          lastAttemptAt: DateTime.utc(2026, 10, 20),
          lastSuccessAt: DateTime.utc(2026, 10, 20),
          stale: false,
        ),
      ),
      makeActive: true,
    );
    final grants = NStackGrantStore();
    final access =
        NStackAccessService(registryStore: registry, grantStore: grants);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NStackScreen(
          config: AppConfig.defaults().copyWith(
            deviceNpub: identity.npub,
            devicePublicKeyHex: identity.publicKeyHex,
            deviceSecret: _identitySecret,
          ),
          registryStore: registry,
          grantStore: grants,
          accessService: access,
          discoveryService: NStackWorkspaceDiscoveryService(
              registryStore: registry, discovery: _NoDiscovery()),
          recoveryService: NStackRecoveryService(
            registryStore: registry,
            storage: _NamespaceStorage(),
            relay: _NoRelay(),
          ),
          onRegistryChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final ordinaryText = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('\n');
    expect(ordinaryText, isNot(contains(identity.npub)));
    for (final workspace in _backupStackWithTwoWorkspaces.workspaces) {
      expect(ordinaryText, isNot(contains(workspace.remoteId)));
      expect(ordinaryText, isNot(contains(workspace.workspaceServiceNpub!)));
      expect(ordinaryText, isNot(contains(workspace.directHttpsUrl!)));
    }
    expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        isNull);
    expect((await registry.load(identity.npub)).backupDestination, isNull,
        reason: 'the first discovered workspace must never be implicit');

    final second =
        find.byKey(const ValueKey('backup-workspace-stack-a-workspace-b'));
    expect(second, findsOneWidget);
    await tester.scrollUntilVisible(second, 200);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(find.textContaining('Backup destination: Personal NStack ·'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('backup-namespace-manager-required')),
        findsOneWidget);
    expect((await registry.load(identity.npub)).backupDestination?.workspaceId,
        'workspace-b');

    final first =
        find.byKey(const ValueKey('backup-workspace-stack-a-workspace-a'));
    expect(first, findsOneWidget);
    await tester.scrollUntilVisible(first, 200);
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect((await registry.load(identity.npub)).backupDestination?.workspaceId,
        'workspace-a');
  });

  testWidgets('removed selected destination remains visible as unavailable',
      (tester) async {
    final identity = NostrCrypto.importIdentity(_identitySecret);
    final registry = NStackRegistryStore();
    await registry.addOrUpdate(identity.npub, _backupStackA, makeActive: true);
    await registry.selectBackupDestination(identity.npub,
        stackId: 'stack-a', workspaceId: 'workspace-a');
    await registry.remove(identity.npub, 'stack-a');
    final grants = NStackGrantStore();
    final access =
        NStackAccessService(registryStore: registry, grantStore: grants);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NStackScreen(
          config: AppConfig.defaults().copyWith(
            deviceNpub: identity.npub,
            devicePublicKeyHex: identity.publicKeyHex,
            deviceSecret: _identitySecret,
          ),
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
    expect(find.byKey(const ValueKey('backup-destination-unavailable')),
        findsOneWidget);
    expect((await registry.load(identity.npub)).backupDestination?.stackId,
        'stack-a');
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
    expect(find.text('NStack'), findsOneWidget);
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
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
              widget is IconButton && widget.tooltip == 'Refresh workspaces'))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byTooltip('NStack actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('NStack actions'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PopupMenuItem<String>>(
                find.widgetWithText(PopupMenuItem<String>, 'Change address'))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<PopupMenuItem<String>>(
                find.widgetWithText(PopupMenuItem<String>, 'Rename NStack'))
            .enabled,
        isTrue);
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

class _PendingDiscovery implements NStackWorkspaceDiscovery {
  final result = Completer<List<NStackWorkspace>>();
  @override
  Future<List<NStackWorkspace>> discover(
          {required String address,
          required String identityNpub,
          required String secret}) =>
      result.future;
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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NamespaceStorage implements NStackStorageClient {
  @override
  Future<NStackBackupNamespaceState> namespaceState(
          {required NStackBackupTarget target, required String secret}) async =>
      NStackBackupNamespaceState.managerRequired;

  @override
  Future<void> enableNamespace(
      {required NStackBackupTarget target, required String secret}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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

const _identitySecret =
    '0000000000000000000000000000000000000000000000000000000000000001';
const _workspaceOwner =
    'npub10xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqpkge6d';
const _backupStackA = NStackEntry(
  id: 'stack-a',
  name: 'Personal NStack',
  url: 'https://personal.example',
  workspaces: [
    NStackWorkspace(
      id: 'workspace-a',
      name: 'Home',
      remoteId: '11111111-1111-4111-8111-111111111111',
      stableRemoteId: '11111111-1111-4111-8111-111111111111',
      workspaceOwnerNpub: _workspaceOwner,
      workspaceServiceNpub: _workspaceOwner,
      directHttpsUrl: 'https://personal.example',
      serviceNpub: _workspaceOwner,
      membershipRole: 'owner',
    ),
  ],
);
const _backupStackWithTwoWorkspaces = NStackEntry(
  id: 'stack-a',
  name: 'Personal NStack',
  url: 'https://personal.example',
  workspaces: [
    NStackWorkspace(
      id: 'workspace-a',
      name: 'Home',
      remoteId: '11111111-1111-4111-8111-111111111111',
      stableRemoteId: '11111111-1111-4111-8111-111111111111',
      workspaceOwnerNpub: _workspaceOwner,
      workspaceServiceNpub: _workspaceOwner,
      directHttpsUrl: 'https://personal.example',
      serviceNpub: _workspaceOwner,
      membershipRole: 'owner',
    ),
    NStackWorkspace(
      id: 'workspace-b',
      name: 'Operations',
      remoteId: '22222222-2222-4222-8222-222222222222',
      stableRemoteId: '22222222-2222-4222-8222-222222222222',
      workspaceOwnerNpub: _workspaceOwner,
      workspaceServiceNpub: _workspaceOwner,
      directHttpsUrl: 'https://personal.example',
      serviceNpub: _workspaceOwner,
      membershipRole: 'manager',
    ),
  ],
);
