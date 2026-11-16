/// SS-수정003 4차 — 한국어 글을 단어(띄어쓰기) 단위로만 줄바꿈한다.
///
/// 한국어는 기본 줄바꿈 규칙상 글자(음절) 사이 어디서나 줄이 바뀔 수 있어 "시/작합니다"처럼 단어 중간에서
/// 끊긴다. [ssKeepWords]는 한 단어 안의 글자 사이에 줄바꿈 금지 문자(U+2060 WORD JOINER — 화면에 보이지 않음)를
/// 넣어 띄어쓰기에서만 줄이 바뀌게 한다. [SsKeepWordsText]는 이것을 쓰는 [Text]다 — 글자 크기·문구는 그대로이고
/// [Text.data]는 원래 문장 그대로다. 너무 좁아 가장 긴 단어 하나도 들어가지 않으면 한 줄 말줄임(…)으로 보인다.
library;

import 'package:flutter/material.dart';

/// 줄바꿈 금지 문자(WORD JOINER) 코드.
const int kSsWordJoinerCode = 0x2060;

/// 줄바꿈 금지 문자(WORD JOINER).
final String kSsWordJoiner = String.fromCharCode(kSsWordJoinerCode);

/// 줄을 바꿀 수 있는 띄어쓰기 문자인지.
bool ssIsWordBreakCode(int code) => code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D || code == 0x3000;

/// 앞 글자에 붙어 한 글자를 이루는 문자(결합 부호·이음 문자·이체자 선택자·한글 자모 중성/종성·피부색) — 그 앞에는 넣지 않는다.
bool _attachesToPrevious(int r) =>
    r == 0x200D ||
    (r >= 0xFE00 && r <= 0xFE0F) ||
    (r >= 0x0300 && r <= 0x036F) ||
    (r >= 0x1160 && r <= 0x11FF) ||
    (r >= 0xD7B0 && r <= 0xD7FF) ||
    (r >= 0x1F3FB && r <= 0x1F3FF) ||
    (r >= 0xE0100 && r <= 0xE01EF);

bool _isGap(int r) => ssIsWordBreakCode(r) || r == kSsWordJoinerCode;

/// 한 단어 안의 글자 사이에 줄바꿈 금지 문자를 넣는다(띄어쓰기는 그대로 — 그곳에서만 줄이 바뀐다).
/// 이미 넣은 글에 다시 불러도 같은 결과다.
String ssKeepWords(String text) {
  if (text.length < 2) return text;
  final out = StringBuffer();
  int? prev;
  for (final r in text.runes) {
    if (prev != null && !_isGap(prev) && !_isGap(r) && prev != 0x200D && !_attachesToPrevious(r)) {
      out.writeCharCode(kSsWordJoinerCode);
    }
    out.writeCharCode(r);
    prev = r;
  }
  return out.toString();
}

/// 띄어쓰기로 나눈 단어들(줄바꿈 금지 문자는 뺀다).
List<String> ssWordsOf(String text) {
  final words = <String>[];
  final current = StringBuffer();
  for (final r in text.runes) {
    if (ssIsWordBreakCode(r)) {
      if (current.isNotEmpty) {
        words.add(current.toString());
        current.clear();
      }
    } else if (r != kSsWordJoinerCode) {
      current.writeCharCode(r);
    }
  }
  if (current.isNotEmpty) words.add(current.toString());
  return words;
}

/// 단어 단위로만 줄을 바꾸는 [Text]. [data]는 원래 문장 그대로다(화면에 그릴 때만 [ssKeepWords]를 쓴다).
class SsKeepWordsText extends Text {
  const SsKeepWordsText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  /// 가장 긴 단어 하나의 폭(줄바꿈 없이 한 줄로 그렸을 때).
  static double longestWordWidth(
    String text, {
    required TextStyle style,
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    var widest = 0.0;
    for (final word in ssWordsOf(text)) {
      final painter = TextPainter(
        text: TextSpan(text: ssKeepWords(word), style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    final original = data ?? '';
    return LayoutBuilder(
      builder: (context, constraints) {
        var tooNarrow = false;
        if (constraints.maxWidth.isFinite && original.isNotEmpty) {
          var effective = DefaultTextStyle.of(context).style.merge(style);
          if (MediaQuery.boldTextOf(context)) effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
          final widest = longestWordWidth(
            original,
            style: effective,
            textScaler: textScaler ?? MediaQuery.textScalerOf(context),
            textDirection: textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr,
          );
          tooNarrow = widest > constraints.maxWidth + 0.5;
        }
        return Text(
          ssKeepWords(original),
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: tooNarrow ? false : softWrap,
          overflow: tooNarrow ? TextOverflow.ellipsis : overflow,
          textScaler: textScaler,
          maxLines: tooNarrow ? 1 : maxLines,
          semanticsLabel: semanticsLabel ?? original,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        );
      },
    );
  }
}
