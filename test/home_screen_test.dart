import 'package:flutter_test/flutter_test.dart';
import 'package:ason_space/screens/home_screen.dart';

void main() {
  testWidgets('Home screen has project management button', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeScreen()));
    expect(find.text('프로젝트 관리'), findsOneWidget);
    expect(find.text('프로젝트 생성'), findsOneWidget);
  });
}
