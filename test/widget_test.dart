import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sync_assam/main.dart';

void main() {
  testWidgets('Home page shows setup steps', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SyncAssamApp());

    expect(find.text('SRT Sync'), findsOneWidget);
    expect(find.text('1. Audio file'), findsOneWidget);
    expect(find.text('2. Language'), findsOneWidget);
    expect(find.text('3. Words per subtitle line'), findsOneWidget);
    expect(find.text('Generate captions'), findsOneWidget);
  });
}
