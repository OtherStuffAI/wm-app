import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wingman_app/src/app.dart';
import 'package:wingman_app/src/core/app_config.dart';
import 'package:wingman_app/src/core/native_core_bridge.dart';
import 'package:wingman_app/src/core/signer_vault.dart';
import 'package:wingman_app/src/features/browser/signer_store.dart';
import 'package:wingman_app/src/features/shell/shell_home.dart';

import 'fake_webview_platform.dart';

void main() {
  int activeBrowserStackIndex(WidgetTester tester) {
    return tester
            .widgetList<IndexedStack>(find.byType(IndexedStack))
            .last
            .index ??
        0;
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    installFakeWebViewPlatform();
  });

  testWidgets('Wingman shell renders browser-first navigation', (tester) async {
    await tester.pumpWidget(
      const WingmanApp(useSignerVault: false),
    );
    await tester.pump();

    expect(find.byTooltip('New tab'), findsOneWidget);
    expect(find.byTooltip('Profile'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('Flight Deck'), findsOneWidget);
    expect(
      fakeLoadedRequestUrls,
      contains('https://near-tea-crab.rick.runwingman.com'),
    );

    await tester.pump(const Duration(seconds: 6));
    expect(find.byTooltip('Back'), findsNothing);

    await tester.tap(find.text('Flight Deck'));
    await tester.pump();
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('Back'), findsNothing);

    await tester.tap(find.byTooltip('New tab'));
    await tester.pump();
    expect(find.text('Flight Deck'), findsOneWidget);
    expect(find.text('Wingman Home'), findsOneWidget);
    expect(fakeLoadedHtmlStrings.single, contains('Rick Autopilot'));
    expect(
      fakeLoadedHtmlStrings.single,
      contains('data-wingman-tab-url="https://rick.runwingman.com"'),
    );
    expect(fakeLoadedHtmlStrings.single, contains("method: 'openTab'"));

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signer').last);
    await tester.pumpAndSettle();
    expect(find.text('Signer'), findsAtLeastNWidgets(1));

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browser').last);
    await tester.pumpAndSettle();
    expect(find.text('Flight Deck'), findsOneWidget);
    expect(find.text('Wingman Home'), findsOneWidget);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();

    expect(find.text('Browser'), findsOneWidget);
    expect(find.text('Drive'), findsAtLeastNWidgets(1));
    expect(find.text('Signer'), findsAtLeastNWidgets(1));
    expect(find.text('Status'), findsAtLeastNWidgets(1));

    await tester.tapAt(const Offset(500, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Setup'), findsOneWidget);
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
    final resetBrowserDataButton =
        find.widgetWithText(OutlinedButton, 'Reset browser data');
    expect(resetBrowserDataButton, findsOneWidget);

    await tester.tap(resetBrowserDataButton);
    await tester.pumpAndSettle();
    expect(find.text('Reset browser data?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(fakeClearCookieCalls, 1);
  });

  testWidgets('Wingman shell clears browser web state when signer changes',
      (tester) async {
    const profileKey = 'wingman.browser.last_signer_npub.v1';
    final preferences = SharedPreferencesAsync();
    await preferences.setString(profileKey, 'npub-old');

    await tester.pumpWidget(
      MaterialApp(
        home: ShellHome(
          config: AppConfig.defaults().copyWith(
            deviceSecret: 'nsec-placeholder',
            deviceNpub: 'npub-new',
            devicePublicKeyHex: 'abcdef',
          ),
          bridge: NativeCoreBridge(),
          signerStore: SignerStore(),
          onConfigChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fakeClearCookieCalls, 1);
    expect(await preferences.getString(profileKey), 'npub-new');
  });

  testWidgets('Wingman shell restores browser tabs for the current signer',
      (tester) async {
    final config = AppConfig.defaults().copyWith(
      deviceSecret: 'nsec-placeholder',
      deviceNpub: 'npub-tabs',
      devicePublicKeyHex: 'abcdef',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ShellHome(
          config: config,
          bridge: NativeCoreBridge(),
          signerStore: SignerStore(),
          onConfigChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New tab'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byType(TextField),
      'https://rick.runwingman.com',
    );
    await tester.tap(find.byTooltip('Go'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('New tab'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Flight Deck'), findsOneWidget);
    expect(find.text('Wingman Home'), findsOneWidget);
    expect(find.text('rick.runwingman.com'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    installFakeWebViewPlatform();

    await tester.pumpWidget(
      MaterialApp(
        home: ShellHome(
          config: config,
          bridge: NativeCoreBridge(),
          signerStore: SignerStore(),
          onConfigChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Flight Deck'), findsOneWidget);
    expect(find.text('Wingman Home'), findsOneWidget);
    expect(find.text('rick.runwingman.com'), findsOneWidget);
    expect(fakeLoadedRequestUrls, contains('https://rick.runwingman.com'));
  });

  testWidgets('Wingman browser cycles tabs with Ctrl+Tab', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShellHome(
          config: AppConfig.defaults().copyWith(
            deviceSecret: 'nsec-placeholder',
            deviceNpub: 'npub-keyboard-tabs',
            devicePublicKeyHex: 'abcdef',
          ),
          bridge: NativeCoreBridge(),
          signerStore: SignerStore(),
          onConfigChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(activeBrowserStackIndex(tester), 0);

    await tester.tap(find.byTooltip('New tab'));
    await tester.pump();
    expect(activeBrowserStackIndex(tester), 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(activeBrowserStackIndex(tester), 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(activeBrowserStackIndex(tester), 1);
  });

  testWidgets('Focus Mode preserves the active browser tab and restores chrome',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final config = AppConfig.defaults().copyWith(
      deviceSecret: 'nsec-placeholder',
      deviceNpub: 'npub-focus-mode',
      devicePublicKeyHex: 'abcdef',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.dark,
        home: ShellHome(
          config: config,
          bridge: NativeCoreBridge(),
          signerStore: SignerStore(),
          onConfigChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New tab'));
    await tester.pump();
    expect(activeBrowserStackIndex(tester), 1);
    expect(find.text('Flight Deck'), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-2')), findsOneWidget);
    final controllerCountBeforeFocus = fakeWebViewControllerCreationCount;

    await tester.tap(find.byTooltip('Enter Focus Mode'));
    await tester.pump();

    expect(activeBrowserStackIndex(tester), 1);
    expect(find.byTooltip('Exit Focus Mode'), findsOneWidget);
    expect(find.byTooltip('Enter Focus Mode'), findsNothing);
    expect(find.byTooltip('Open menu'), findsNothing);
    expect(find.byTooltip('New tab'), findsNothing);
    expect(find.byTooltip('Profile'), findsNothing);
    expect(find.bySemanticsLabel('Exit Focus Mode'), findsOneWidget);
    expect(find.text('Flight Deck'), findsNothing);
    expect(find.text('Wingman Home'), findsNothing);
    expect(fakeWebViewControllerCreationCount, controllerCountBeforeFocus);

    final restoreButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('exit-focus-mode-button')),
    );
    expect(restoreButton.icon, isA<Icon>());
    expect((restoreButton.icon as Icon).icon, Icons.fullscreen);
    expect(tester.getSize(find.byType(IconButton).last).width,
        greaterThanOrEqualTo(48));

    await tester.tap(find.byTooltip('Exit Focus Mode'));
    await tester.pump();

    expect(activeBrowserStackIndex(tester), 1);
    expect(find.byTooltip('Exit Focus Mode'), findsNothing);
    expect(find.byTooltip('Enter Focus Mode'), findsOneWidget);
    expect(find.byTooltip('Open menu'), findsOneWidget);
    expect(find.byTooltip('Profile'), findsOneWidget);
    expect(find.bySemanticsLabel('Enter Focus Mode'), findsOneWidget);
    expect(find.text('Flight Deck'), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-2')), findsOneWidget);
    expect(fakeWebViewControllerCreationCount, controllerCountBeforeFocus);

    await tester.tap(find.byTooltip('Enter Focus Mode'));
    await tester.pump();
    expect(find.byTooltip('Exit Focus Mode'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    installFakeWebViewPlatform();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ShellHome(
          config: config,
          bridge: NativeCoreBridge(),
          signerStore: SignerStore(),
          onConfigChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Enter Focus Mode'), findsOneWidget);
    expect(find.byTooltip('Exit Focus Mode'), findsNothing);
    semantics.dispose();
  });

  testWidgets('Wingman browser edits and persists local Nostr profile',
      (tester) async {
    final config = AppConfig.defaults().copyWith(
      deviceSecret: 'nsec-placeholder',
      deviceNpub: 'npub-profile',
      devicePublicKeyHex: 'abcdef',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ShellHome(
          config: config,
          bridge: NativeCoreBridge(),
          signerStore: SignerStore(),
          onConfigChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    final displayNameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Display name',
    );
    expect(displayNameField, findsOneWidget);

    await tester.enterText(displayNameField, 'Pete Winn');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Pete Winn'), findsNothing);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Pete Winn'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Pete Winn'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    installFakeWebViewPlatform();

    await tester.pumpWidget(
      MaterialApp(
        home: ShellHome(
          config: config,
          bridge: NativeCoreBridge(),
          signerStore: SignerStore(),
          onConfigChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pete Winn'), findsNothing);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Pete Winn'), findsOneWidget);
  });

  testWidgets('Wingman app persists the Flight Deck URL setting',
      (tester) async {
    await tester.pumpWidget(
      const WingmanApp(useSignerVault: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();

    final flightDeckField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Flight Deck URL',
    );
    expect(flightDeckField, findsOneWidget);

    await tester.enterText(flightDeckField, 'https://example.com/flightdeck');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    installFakeWebViewPlatform();

    await tester.pumpWidget(
      const WingmanApp(useSignerVault: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Flight Deck'), findsOneWidget);
    expect(fakeLoadedRequestUrls, contains('https://example.com/flightdeck'));
  });

  testWidgets('Wingman app prompts for signer vault on first launch',
      (tester) async {
    await tester.pumpWidget(
      WingmanApp(
        signerVault: SignerVault(
          localStore: MemorySignerVaultLocalStore(),
          secretStore: MemorySignerVaultSecretStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set Up Wingman Signer'), findsOneWidget);
    expect(find.text('Nostr private key'), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Confirm PIN'), findsOneWidget);
  });
}
