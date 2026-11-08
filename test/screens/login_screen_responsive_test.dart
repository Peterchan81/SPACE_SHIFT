// SS-수정001 §1·§2·§6 — 로그인 화면이 세로 스크롤 없이 다양한 창 크기에서
// 이메일·비밀번호 입력, 로그인·회원가입 버튼을 모두 화면 안에, 서로 겹치지
// 않게 보여주는지 검증한다(1280x720, 1024x640, 800x600, 1920x1080, 세로
// Galaxy Tab 800x1280).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/screens/login_screen.dart';
import 'package:ason_space/widgets/gradient_cta_button.dart';

bool _within(Rect rect, Size screen) {
  const epsilon = 0.5;
  return rect.left >= -epsilon && rect.top >= -epsilon && rect.right <= screen.width + epsilon && rect.bottom <= screen.height + epsilon;
}

void main() {
  const sizes = <String, Size>{
    '1280x720': Size(1280, 720),
    '1024x640': Size(1024, 640),
    '800x600': Size(800, 600),
    '1920x1080': Size(1920, 1080),
    '800x1280(세로 Galaxy Tab)': Size(800, 1280),
  };

  for (final entry in sizes.entries) {
    testWidgets(
      '${entry.key} — 이메일·비밀번호 입력과 로그인·회원가입 버튼이 모두 화면 안에, 겹치지 않게, 스크롤 없이 보인다',
      (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
        await tester.pump();

        // §1 "세로 스크롤을 없앤다" — 페이지 수준 스크롤 컨테이너가 없어야
        // 한다(TextField 내부의 EditableText 전용 Scrollable은 Flutter
        // 프레임워크 자체 구현이라 검사 대상이 아니다).
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(find.byType(ListView), findsNothing);

        expect(find.byType(TextField), findsNWidgets(2));
        expect(find.byType(GradientCtaButton), findsOneWidget);
        expect(find.byType(OutlinedButton), findsOneWidget);

        final emailRect = tester.getRect(find.byType(TextField).first);
        final passwordRect = tester.getRect(find.byType(TextField).last);
        final loginRect = tester.getRect(find.byType(GradientCtaButton));
        final signupRect = tester.getRect(find.byType(OutlinedButton));

        final rects = <String, Rect>{
          '이메일 입력': emailRect,
          '비밀번호 입력': passwordRect,
          '로그인 버튼': loginRect,
          '회원가입 버튼': signupRect,
        };

        rects.forEach((name, rect) {
          expect(_within(rect, entry.value), isTrue, reason: '$name이 화면 밖($rect, screen=${entry.value})');
        });

        final entries = rects.entries.toList();
        for (var i = 0; i < entries.length; i++) {
          for (var j = i + 1; j < entries.length; j++) {
            expect(
              entries[i].value.overlaps(entries[j].value),
              isFalse,
              reason: '${entries[i].key}과 ${entries[j].key}이 겹친다',
            );
          }
        }

        expect(tester.takeException(), isNull);
      },
    );
  }
}
