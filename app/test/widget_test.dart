import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wingman_app/src/app.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('Wingman shell renders primary tabs', (tester) async {
    await tester.pumpWidget(const WingmanApp());

    expect(find.text('Setup'), findsAtLeastNWidgets(1));
    expect(find.text('Drive'), findsAtLeastNWidgets(1));
    expect(find.text('Browser'), findsAtLeastNWidgets(1));
    expect(find.text('Signer'), findsAtLeastNWidgets(1));
    expect(find.text('Status'), findsAtLeastNWidgets(1));
  });
}
