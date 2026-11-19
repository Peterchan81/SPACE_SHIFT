// SS-수정003 4차 — 단어(띄어쓰기) 단위 줄바꿈 함수·위젯 단위 테스트.
import 'package:ason_space/widgets/ss_keep_words_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ss_keep_words_expect.dart';

void main() {
  group('ssKeepWords', () {
    test('단어 안 글자 사이에만 줄바꿈 금지 문자를 넣는다', () {
      final j = kSsWordJoiner;
      expect(ssKeepWords('시작 합니다'), '시$j작 합$j니$j다');
      expect(ssKeepWords('확인·보정'), '확$j인$j·$j보$j정');
    });

    test('금지 문자를 빼면 원문 그대로이고, 다시 불러도 같다', () {
      const s = '진행 중인 프로젝트를 선택하여 작업을 계속하거나 새로운 프로젝트를 만들어보세요.';
      expect(ssKeepWords(s).replaceAll(kSsWordJoiner, ''), s);
      expect(ssKeepWords(ssKeepWords(s)), ssKeepWords(s));
    });

    test('빈 글·한 글자·띄어쓰기만 있는 글', () {
      expect(ssKeepWords(''), '');
      expect(ssKeepWords('가'), '가');
      expect(ssKeepWords('가 나'), '가 나');
      expect(ssKeepWords('   '), '   ');
    });

    test('단어 나누기', () {
      expect(ssWordsOf('  평면도  확인·보정 '), ['평면도', '확인·보정']);
      expect(ssWordsOf(ssKeepWords('공간을 구성해보세요.')), ['공간을', '구성해보세요.']);
    });
  });

  testWidgets('가장 긴 단어가 들어가는 어느 폭에서도 줄은 띄어쓰기에서만 바뀐다', (tester) async {
    const sentences = [
      '도면 이미지를 업로드하여 공간을 분석하고 시작합니다.',
      '간단한 도구로 직접 평면도를 그리고 공간을 구성해보세요.',
      'AI와 함께, 당신의 공간을 새롭게 디자인하세요.',
      '진행 중인 프로젝트를 선택하여 작업을 계속하거나 새로운 프로젝트를 만들어보세요.',
      '마지막 작업: 우리집 리모델링 · 평면도 확인·보정 단계에서 이어서 할 수 있습니다.',
    ];
    const style = TextStyle(fontSize: 14);
    for (final s in sentences) {
      final text = ssKeepWords(s);
      final widest = SsKeepWordsText.longestWordWidth(s, style: style);
      for (final extra in const [1.0, 13.0, 40.0, 90.0, 200.0]) {
        final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: widest + extra);
        expectLinesBreakOnlyAtSpaces(painter, text, reason: '$s @ ${widest + extra}');
        painter.dispose();
      }
    }
  });

  testWidgets('data는 원래 문장이고, 그릴 때만 줄바꿈 금지 문자를 넣는다', (tester) async {
    const original = '공간 사진을 업로드하여 새로운 디자인을 만들어보세요.';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 300, child: SsKeepWordsText(original, key: Key('k')))))),
    );
    expect(tester.widget<Text>(find.byKey(const Key('k'))).data, original);
    expect(find.text(original), findsOneWidget);
    final inner = tester.widget<Text>(find.descendant(of: find.byKey(const Key('k')), matching: find.byType(Text)).first);
    expect(inner.data, ssKeepWords(original));
    expect(inner.maxLines, isNull);
  });

  testWidgets('너무 좁아 한 단어도 들어가지 않으면 한 줄 말줄임', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 40, child: SsKeepWordsText('SPACESHIFT design', key: Key('k'), style: TextStyle(fontSize: 14)))),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final inner = tester.widget<Text>(find.descendant(of: find.byKey(const Key('k')), matching: find.byType(Text)).first);
    expect(inner.maxLines, 1);
    expect(inner.overflow, TextOverflow.ellipsis);
  });
}
