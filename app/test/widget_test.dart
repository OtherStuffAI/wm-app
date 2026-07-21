import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wingman_app/src/app.dart';

import 'fake_webview_platform.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    installFakeWebViewPlatform();
  });

  testWidgets('Wingman shell renders browser-first navigation', (tester) async {
    await tester.pumpWidget(
      const WingmanApp(seedDeviceKeyFromEnvironment: false),
    );
    await tester.pump();

    expect(find.byTooltip('New tab'), findsOneWidget);
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Wingman Home'), findsOneWidget);

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
}
