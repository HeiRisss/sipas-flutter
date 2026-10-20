
import 'package:flutter_test/flutter_test.dart';
import 'package:sipas/main.dart';

void main() {
  testWidgets('SIPAS menampilkan dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SIPASApp());

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('SIPAS'), findsOneWidget);
  });
}