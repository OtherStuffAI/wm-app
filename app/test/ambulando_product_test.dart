import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wingman_app/src/core/app_product.dart';
import 'fake_webview_platform.dart';
import 'mesh_auth_signing_test.dart' show Harness;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets(
      'Ambulando opens the bundled product once with browser chrome hidden',
      (tester) async {
    const origin = 'http://127.0.0.1:47832/';
    final h = Harness(localFlightDeckUrl: origin);
    await h.start(tester);
    expect(fakeLoadedRequestUrls.where((url) => url == origin).length, 1);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(AppProduct.title, 'Ambulando');
    expect(AppProduct.assetPrefix, 'assets/ambulando/');
    await tester.pumpWidget(const SizedBox());
  }, skip: !AppProduct.ambulando);
}
