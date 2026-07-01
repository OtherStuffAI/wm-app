import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_app/src/app.dart';

void main() {
  testWidgets('Wingman shell renders primary tabs', (tester) async {
    await tester.pumpWidget(const WingmanApp());

    expect(find.text('Setup'), findsAtLeastNWidgets(1));
    expect(find.text('Drive'), findsAtLeastNWidgets(1));
    expect(find.text('Browser'), findsAtLeastNWidgets(1));
    expect(find.text('Status'), findsAtLeastNWidgets(1));
  });
}
