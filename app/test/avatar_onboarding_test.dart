import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wingman_app/src/app.dart';
import 'package:wingman_app/src/core/app_config.dart';
import 'package:wingman_app/src/core/native_core_bridge.dart';
import 'package:wingman_app/src/core/nostr_crypto.dart';
import 'package:wingman_app/src/core/signer_vault.dart';
import 'package:wingman_app/src/features/browser/browser_screen.dart';
import 'package:wingman_app/src/features/browser/nostr_profile_relay_client.dart';
import 'package:wingman_app/src/features/browser/nostr_profile_store.dart';
import 'package:wingman_app/src/features/browser/signer_store.dart';

import 'fake_webview_platform.dart';

class ObservedVault extends SignerVault {
  ObservedVault()
      : super(
            localStore: MemorySignerVaultLocalStore(),
            secretStore: MemorySignerVaultSecretStore());
  Future<SignerVaultUnlock>? pending;
  @override
  Future<SignerVaultUnlock> create(
          {required String nsec, required String pin}) =>
      pending = super.create(nsec: nsec, pin: pin);
  @override
  Future<SignerVaultUnlock> unlock({required String pin}) =>
      pending = super.unlock(pin: pin);
}

class FakeProfileRelays extends NostrProfileRelayClient {
  FakeProfileRelays() : super(relays: []);
  final refresh = Completer<NostrProfile?>();
  final events = <Map<String, dynamic>>[];
  bool accept = false;
  @override
  Future<NostrProfile?> fetchProfile(String publicKeyHex) => refresh.future;
  @override
  Future<ProfilePublishResult> publish(Map<String, dynamic> event) async {
    events.add(event);
    return ProfilePublishResult(
        acceptedRelays: accept ? ['ws://fake.test'] : [], totalRelays: 1);
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    installFakeWebViewPlatform();
  });
  Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label);
  Future<void> openAvatar(WidgetTester tester, String action) async {
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  Future<void> submit(
      WidgetTester tester, String label, ObservedVault vault) async {
    await tester.scrollUntilVisible(find.text(label), 150,
        scrollable: find.byType(Scrollable).last);
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await vault.pending;
    });
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets(
        'avatar create, cancel, profile setup and vault unlock at $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final vault = ObservedVault();
      final relays = FakeProfileRelays();
      await tester.pumpWidget(
          WingmanApp(signerVault: vault, profileRelayClient: relays));
      await tester.pumpAndSettle();
      await openAvatar(tester, 'Create identity / Import key');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(await vault.loadRecord(), isNull);
      await openAvatar(tester, 'Create identity / Import key');
      await tester.enterText(field('PIN'), '1234');
      await tester.enterText(field('Confirm PIN'), '1234');
      await submit(tester, 'Create and encrypt identity', vault);
      final record = await vault.loadRecord();
      expect(record, isNotNull);
      expect(find.text('Edit profile'), findsOneWidget);
      await tester.enterText(field('Display name'), 'New User');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect((await NostrProfileStore().load(record!.npub)).displayName,
          'New User');
      expect(relays.events, isEmpty);
      await openAvatar(tester, 'Log out');
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();
      await openAvatar(tester, 'Unlock identity');
      expect(find.text('Create identity'), findsNothing);
      await tester.tap(find.text('Reset local signer vault'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await vault.loadRecord())!.npub, record.npub);
      await tester.enterText(field('PIN'), '1234');
      await submit(tester, 'Unlock', vault);
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('New User'), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('import remains usable and invalid private input is never echoed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vault = ObservedVault();
    await tester.pumpWidget(WingmanApp(
        signerVault: vault, profileRelayClient: FakeProfileRelays()));
    await tester.pumpAndSettle();
    await openAvatar(tester, 'Create identity / Import key');
    await tester.tap(find.text('Import key'));
    await tester.pumpAndSettle();
    await tester.enterText(
        field('Nostr private key'), 'nsec-private-invalid-input');
    await tester.enterText(field('PIN'), '1234');
    await tester.enterText(field('Confirm PIN'), '1234');
    // The error is handled by the screen; consume the same failing future here.
    await tester.runAsync(() async {
      await tester.tap(find.text('Encrypt and Continue'));
      try {
        await vault.pending;
      } catch (_) {}
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to open the signer'), findsOneWidget);
    expect(await vault.loadRecord(), isNull);
    final identity = NostrCrypto.importIdentity('3'.padLeft(64, '0'));
    await tester.enterText(field('Nostr private key'), identity.nsec);
    await submit(tester, 'Encrypt and Continue', vault);
    expect((await vault.loadRecord())!.npub, identity.npub);
    expect(find.text('Edit profile'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'publication failure retains draft, retries, and delayed refresh cannot clobber edit',
      (tester) async {
    final identity = NostrCrypto.importIdentity('1'.padLeft(64, '0'));
    final relays = FakeProfileRelays();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BrowserScreen(
      config: AppConfig.defaults().copyWith(
          deviceNpub: identity.npub,
          devicePublicKeyHex: identity.publicKeyHex,
          deviceSecret: identity.nsec),
      bridge: NativeCoreBridge(),
      signerStore: SignerStore(),
      profileRelayClient: relays,
      onOpenDrawer: () {},
      onOpenSetup: () {},
      onOpenSigner: () {},
      onOpenStatus: () {},
    ))));
    await tester.pumpAndSettle();
    await openAvatar(tester, 'Edit profile');
    await tester.enterText(field('Display name'), 'Local draft');
    relays.refresh.complete(const NostrProfile(displayName: 'Stale remote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign and publish'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('No relay confirmed publication'), findsOneWidget);
    expect((await NostrProfileStore().load(identity.npub)).displayName,
        'Local draft');
    expect(relays.events.single['pubkey'], identity.publicKeyHex);
    relays.accept = true;
    await tester.tap(find.text('Retry publication'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Published: 1/1'), findsOneWidget);
    expect(relays.events, hasLength(2));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await openAvatar(tester, 'Edit profile');
    expect(tester.widget<TextField>(field('Display name')).controller!.text,
        'Local draft');
    await tester.enterText(field('Display name'), 'Cancelled edit');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await NostrProfileStore().load(identity.npub)).displayName,
        'Local draft');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
      'late refresh from another identity changes neither UI nor its stored draft',
      (tester) async {
    final first = NostrCrypto.importIdentity('1'.padLeft(64, '0'));
    final second = NostrCrypto.importIdentity('2'.padLeft(64, '0'));
    final relays = FakeProfileRelays();
    final store = NostrProfileStore();
    await store.save(
        first.npub, const NostrProfile(displayName: 'First draft'));
    await store.save(
        second.npub, const NostrProfile(displayName: 'Second draft'));
    Widget browser(NostrIdentity identity) => MaterialApp(
            home: Scaffold(
                body: BrowserScreen(
          config: AppConfig.defaults().copyWith(
              deviceNpub: identity.npub,
              devicePublicKeyHex: identity.publicKeyHex,
              deviceSecret: identity.nsec),
          bridge: NativeCoreBridge(),
          signerStore: SignerStore(),
          profileRelayClient: relays,
          onOpenDrawer: () {},
          onOpenSetup: () {},
          onOpenSigner: () {},
          onOpenStatus: () {},
        )));
    await tester.pumpWidget(browser(first));
    await tester.pumpAndSettle();
    await tester.pumpWidget(browser(second));
    await tester.pumpAndSettle();
    relays.refresh.complete(const NostrProfile(displayName: 'Late result'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Second draft'), findsOneWidget);
    expect(find.text('First draft'), findsNothing);
    expect(find.text('Late result'), findsNothing);
    expect((await store.load(first.npub)).displayName, 'First draft');
    expect((await store.load(second.npub)).displayName, 'Second draft');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
