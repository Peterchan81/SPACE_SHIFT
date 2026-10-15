import 'package:flutter_test/flutter_test.dart';
import 'package:ason_space/main.dart';

void main() {
  testWidgets('Login Screen has a title', (WidgetTester tester) async {
    await tester.pumpWidget(SpaceShiftApp());
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
  });
  testWidgets('Home Screen has a title', (WidgetTester tester) async {
    await tester.pumpWidget(SpaceShiftApp());
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
}