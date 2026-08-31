import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/screens/signup_screen.dart';
import 'package:ason_space/widgets/gradient_cta_button.dart';

void main() {
  Future<void> pumpSignup(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    await tester.pump();
  }

  Future<void> fillRequiredFields(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextFormField, '이름'), '홍길동');
    await tester.enterText(find.widgetWithText(TextFormField, '이메일'), 'a@b.com');
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호'),
      'password1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호 확인'),
      'password1',
    );
  }

  testWidgets('필수 항목이 비어 있으면 회원가입을 진행하지 않는다', (tester) async {
    await pumpSignup(tester);

    await tester.tap(find.byType(GradientCtaButton));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.text('필수 항목입니다.'), findsWidgets);
  });

  testWidgets('비밀번호와 비밀번호 확인이 다르면 SnackBar로 안내하고 진행하지 않는다', (tester) async {
    await pumpSignup(tester);
    await tester.enterText(find.widgetWithText(TextFormField, '이름'), '홍길동');
    await tester.enterText(find.widgetWithText(TextFormField, '이메일'), 'a@b.com');
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호'),
      'password1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호 확인'),
      'password2',
    );

    await tester.tap(find.byType(GradientCtaButton));
    await tester.pump();

    expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
  });

  testWidgets('약관 동의 체크박스를 선택하지 않으면 회원가입을 진행하지 않는다', (tester) async {
    await pumpSignup(tester);
    await fillRequiredFields(tester);

    await tester.tap(find.byType(GradientCtaButton));
    await tester.pump();

    expect(find.text('이용약관 및 개인정보처리방침에 동의해주세요.'), findsOneWidget);
    expect(find.byType(SignupScreen), findsOneWidget);
  });

  testWidgets('필수 항목을 채우고 약관에 동의하면 사진 등록 화면으로 이동한다', (tester) async {
    await pumpSignup(tester);
    await fillRequiredFields(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    await tester.tap(find.byType(GradientCtaButton));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsNothing);
  });

  testWidgets('비밀번호 필드의 보기/숨기기 아이콘이 각각 독립적으로 동작한다', (tester) async {
    await pumpSignup(tester);

    // 초기 상태: 두 필드 모두 숨김(visibility_off) 아이콘 두 개.
    expect(find.byIcon(Icons.visibility_off_outlined), findsNWidgets(2));
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);

    // 첫 번째(비밀번호) 아이콘만 탭 → 하나만 보임 상태로 바뀐다.
    await tester.tap(find.byIcon(Icons.visibility_off_outlined).first);
    await tester.pump();

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('이용약관을 탭하면 원문 준비 상태를 안내하는 바텀시트가 열린다', (tester) async {
    await pumpSignup(tester);

    await tester.tap(find.text('이용약관'));
    await tester.pumpAndSettle();

    expect(find.textContaining('이용약관 원문이 아직 등록되지 않았습니다'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('이용약관 원문이 아직 등록되지 않았습니다'), findsNothing);
  });

  testWidgets('개인정보처리방침을 탭하면 원문 준비 상태를 안내하는 바텀시트가 열린다', (tester) async {
    await pumpSignup(tester);

    await tester.tap(find.text('개인정보처리방침'));
    await tester.pumpAndSettle();

    expect(find.textContaining('개인정보처리방침 원문이 아직 등록되지 않았습니다'), findsOneWidget);
  });

  testWidgets('프로필 사진 없이도 카메라 아이콘 placeholder가 표시된다', (tester) async {
    await pumpSignup(tester);

    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
  });
}
