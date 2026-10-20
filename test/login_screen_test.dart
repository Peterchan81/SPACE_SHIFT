import 'package:flutter_test/flutter_test.dart';
import 'package:ason_space/screens/login_screen.dart';

void main() {
  testWidgets('Login screen has email and password fields', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen()));
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
  });
}
