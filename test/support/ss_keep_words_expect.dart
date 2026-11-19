// SS-수정003 4차 — 단어 단위 줄바꿈 확인 도우미(테스트 전용).
import 'package:ason_space/widgets/ss_keep_words_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

bool _isSpaceCode(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x3000;

String _clean(String s) => s.replaceAll(kSsWordJoiner, '');

/// 보이는 줄과 줄 사이 경계가 모두 띄어쓰기인지(마지막 줄 뒤 말줄임은 보지 않는다).
void expectLinesBreakOnlyAtSpaces(TextPainter painter, String text, {String reason = ''}) {
  final lineCount = painter.computeLineMetrics().length;
  var offset = 0;
  for (var i = 0; i < lineCount - 1; i++) {
    final range = painter.getLineBoundary(TextPosition(offset: offset));
    final end = range.end;
    if (end <= offset || end >= text.length) break;
    final ok = _isSpaceCode(text.codeUnitAt(end - 1)) || _isSpaceCode(text.codeUnitAt(end));
    expect(ok, isTrue, reason: '$reason — 단어 중간에서 줄이 바뀜: "${_clean(text.substring(range.start, end))}" | "${_clean(text.substring(end))}"');
    offset = end;
    while (offset < text.length && _isSpaceCode(text.codeUnitAt(offset))) {
      offset++;
    }
  }
}

/// [finder]가 [SsKeepWordsText]이고, 문구는 그대로이며, 화면에 그려진 폭에서 단어 중간에서 줄이 바뀌지 않는다.
void expectKeepsWords(WidgetTester tester, Finder finder, {String reason = ''}) {
  expect(finder, findsOneWidget, reason: reason);
  final widget = tester.widget<Text>(finder);
  expect(widget, isA<SsKeepWordsText>(), reason: '$reason — 단어 단위 줄바꿈 글');
  final richFinder = find.descendant(of: finder, matching: find.byType(RichText)).first;
  final rich = tester.widget<RichText>(richFinder);
  final shown = rich.text.toPlainText(includeSemanticsLabels: false);
  expect(_clean(shown), widget.data, reason: '$reason — 문구는 그대로');
  if (!rich.softWrap) return;
  final paragraph = tester.renderObject<RenderParagraph>(richFinder);
  final maxWidth = paragraph.constraints.maxWidth;
  if (!maxWidth.isFinite) return;
  final painter = TextPainter(
    text: rich.text,
    textAlign: rich.textAlign,
    textDirection: rich.textDirection ?? TextDirection.ltr,
    textScaler: rich.textScaler,
    maxLines: rich.maxLines,
    ellipsis: rich.overflow == TextOverflow.ellipsis ? String.fromCharCode(0x2026) : null,
    locale: rich.locale,
    strutStyle: rich.strutStyle,
    textWidthBasis: rich.textWidthBasis,
    textHeightBehavior: rich.textHeightBehavior,
  )..layout(maxWidth: maxWidth);
  expectLinesBreakOnlyAtSpaces(painter, shown, reason: reason);
  painter.dispose();
}
