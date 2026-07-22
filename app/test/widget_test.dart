import 'package:flutter/material.dart';
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
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Wingman Home'), findsOneWidget);
    expect(fakeLoadedHtmlStrings.single, contains('Rick Autopilot'));
    expect(
      fakeLoadedHtmlStrings.single,
      contains('data-wingman-tab-url="https://rick.runwingman.com"'),
    );
    expect(fakeLoadedHtmlStrings.single, contains("method: 'openTab'"));

    await tester.pump(const Duration(seconds: 6));
    expect(find.byTooltip('Back'), findsNothing);

    await tester.tap(find.text('Wingman Home'));
    await tester.pump();
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('Back'), findsNothing);

    await tester.tap(find.byTooltip('New tab'));
    await tester.pump();
    expect(find.text('Wingman Home'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signer').last);
    await tester.pumpAndSettle();
    expect(find.text('Signer'), findsAtLeastNWidgets(1));

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browser').last);
    await tester.pumpAndSettle();
    expect(find.text('Wingman Home'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();

    expect(find.text('Browser'), findsOneWidget);
    expect(find.text('Drive'), findsAtLeastNWidgets(1));
    expect(find.text('Signer'), findsAtLeastNWidgets(1));
    expect(find.text('Status'), findsAtLeastNWidgets(1));

    await tester.tapAt(const Offset(500, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Setup'), findsOneWidget);
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
