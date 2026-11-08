// SS-수정001 §1·§2·§6 — 로그인 화면이 1280x720·1024x640·800x600·
// 1920x1080·800x1280(Galaxy Tab 세로)·640x480·624x441(640x480 Windows
// 창에서 제목줄·테두리를 뺀 실제 화면 영역) 7개 창 크기에서 세로 스크롤
// 없이, 이메일·비밀번호 입력·로그인 버튼·회원가입 버튼·제목·로고·"또는"이
// 모두 화면 안(Rect 안)에 있고 서로 겹치지 않으며 overflow 오류가 없음을
// 검사한다.
//
// Scrollable 위젯 자체는 Flutter의 TextField/EditableText가 내부적으로
// 항상 포함하므로(스크롤이 필요 없어도 존재) 그 타입으로는 검사하지 않고,
// "화면 전체를 스크롤시키는" SingleChildScrollView/ListView가 없는지로
// 검사한다 — SS-수정001이 실제로 없앤 것이 그 위젯이다.
//
// 624x441 + 글자 크기 1.2배(TextScaler.linear(1.2))는 실제 Windows 한글
// 글꼴이 테스트용 글꼴보다 줄 높이가 큰 경우를 흉내내, 그런 경우에도
// overflow 오류 없이 회원가입 버튼이 화면 안에 있는지 따로 검사한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/screens/login_screen.dart';
import 'package:ason_space/widgets/gradient_cta_button.dart';

void main() {
  const sizes = [
    Size(1280, 720),
    Size(1024, 640),
    Size(800, 600),
    Size(1920, 1080),
    Size(800, 1280),
    Size(640, 480),
    Size(624, 441),
  ];

  for (final size in sizes) {
    testWidgets(
      '${size.width.toInt()}x${size.height.toInt()}에서 이메일·비밀번호·로그인·회원가입·제목·로고·또는이 모두 화면 안에 겹치지 않게 보이고 스크롤이 없다',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsNothing, reason: '세로 스크롤을 없앤다(§1)');
        expect(find.byType(ListView), findsNothing);

        final screenRect = Rect.fromLTWH(0, 0, size.width, size.height);
        final emailField = tester.getRect(find.byType(TextField).first);
        final passwordField = tester.getRect(find.byType(TextField).last);
        final loginButton = tester.getRect(find.byType(GradientCtaButton));
        final signupButton = tester.getRect(find.byType(OutlinedButton));
        final title = tester.getRect(find.byKey(const Key('loginTitle')));
        final logo = tester.getRect(find.byKey(const Key('loginLogo')));
        final orText = tester.getRect(find.text('또는'));

        for (final rect in [emailField, passwordField, loginButton, signupButton, title, logo, orText]) {
          expect(screenRect.contains(rect.topLeft), isTrue, reason: '$rect 가 화면 밖(좌상단)');
          expect(screenRect.contains(rect.bottomRight - const Offset(1, 1)), isTrue, reason: '$rect 가 화면 밖(우하단)');
        }

        expect(emailField.bottom, lessThanOrEqualTo(passwordField.top + 0.5), reason: '이메일·비밀번호가 겹치지 않는다');
        expect(passwordField.bottom, lessThanOrEqualTo(loginButton.top + 0.5), reason: '비밀번호·로그인 버튼이 겹치지 않는다');
        expect(loginButton.bottom, lessThanOrEqualTo(signupButton.top + 0.5), reason: '로그인·회원가입 버튼이 겹치지 않는다');

        expect(loginButton.height, greaterThanOrEqualTo(44), reason: '로그인 버튼은 최소 터치 높이(44px)를 지킨다');
        expect(signupButton.height, greaterThanOrEqualTo(44), reason: '회원가입 버튼은 최소 터치 높이(44px)를 지킨다');

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    '624x441 + 글자 크기 1.2배(실제 Windows 글꼴처럼 줄 높이가 큰 경우)에도 overflow 없이 회원가입 버튼이 화면 안에 있다',
    (tester) async {
      const size = Size(624, 441);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: child!,
          ),
          home: const LoginScreen(),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '실제 Windows 글꼴처럼 줄 높이가 큰 경우에도 overflow 오류가 없다');
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ListView), findsNothing);

      final screenRect = Rect.fromLTWH(0, 0, size.width, size.height);
      final signupButton = tester.getRect(find.byType(OutlinedButton));

      expect(screenRect.contains(signupButton.topLeft), isTrue, reason: '회원가입 버튼이 화면 밖(좌상단)');
      expect(screenRect.contains(signupButton.bottomRight - const Offset(1, 1)), isTrue, reason: '회원가입 버튼이 화면 밖(우하단)');
      expect(signupButton.height, greaterThanOrEqualTo(44), reason: '회원가입 버튼은 최소 터치 높이(44px)를 지킨다');

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
