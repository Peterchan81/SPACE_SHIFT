// SPACE SHIFT — PC1 CONTINUE: FLOOR DOMAIN FIRST + PHYSICAL ROOM / SEMANTIC
// ZONE SPLIT.
//
// pixel_wall_extractor.dart는 GPT와 무관하게 순수 픽셀 근거(두께/길이/
// junction)만으로 structural/reviewNeeded를 나눈다. 이 파일은 그 위에
// GPT의 의미 ROI(가구/애매 영역/문·창 힌트)까지 결합해 reviewNeeded
// candidate를 TEXT/FURNITURE/FIXTURE/DOOR_ARC/WINDOW_DETAIL/UNKNOWN으로
// 더 세분화한다 — "짧으면 무조건 노이즈"가 아니라 여러 근거를 함께 본다
// (§3 요구). structural candidate는 재분류하지 않는다(이미 근거 충분).

import 'dart:math' as math;

import 'gpt_semantic_schema.dart';
import 'pixel_wall_types.dart';

double _lengthPx(PixelWallCandidate c, int w, int h) {
  final dx = (c.end.x - c.start.x) * w;
  final dy = (c.end.y - c.start.y) * h;
  return math.sqrt(dx * dx + dy * dy);
}

double _thicknessPx(PixelWallCandidate c, int w, int h) =>
    c.thicknessNormalized * (c.orientation == PixelWallOrientation.horizontal ? h : w);

/// candidate.start/end는 중심선(centerline)이라 수평 벽은 항상 높이가
/// 0인, 수직 벽은 항상 폭이 0인 퇴화(degenerate) bbox가 된다 — 교집합
/// 넓이가 항상 0이 되어 어떤 ROI와도 절대 겹치지 않는 버그였다. 실제
/// 벽은 두께가 있으므로, 두께 방향으로 최소 여유(padding)를 줘서 "선"이
/// 아니라 얇은 "띠"로 취급한다.
const double _candidateBboxPadding = 0.01;

GptApproxRegion _candidateBbox(PixelWallCandidate c) {
  return GptApproxRegion(
    x0: math.min(c.start.x, c.end.x) - _candidateBboxPadding,
    y0: math.min(c.start.y, c.end.y) - _candidateBboxPadding,
    x1: math.max(c.start.x, c.end.x) + _candidateBboxPadding,
    y1: math.max(c.start.y, c.end.y) + _candidateBboxPadding,
  );
}

/// [a](후보 벽의 좁은 bbox)가 [b](GPT의 대략 ROI) 안에 "대부분" 들어있는지 —
/// IoU 대신 "얼마나 안에 포함되는가"를 본다. 얇고 짧은 후보 bbox는 면적이
/// 거의 0이라 IoU 자체가 항상 작게 나오기 때문이다.
double _containmentRatio(GptApproxRegion a, GptApproxRegion b) {
  final ix0 = math.max(a.x0, b.x0);
  final iy0 = math.max(a.y0, b.y0);
  final ix1 = math.min(a.x1, b.x1);
  final iy1 = math.min(a.y1, b.y1);
  final iw = ix1 - ix0;
  final ih = iy1 - iy0;
  if (iw <= 0 || ih <= 0) return 0;
  final interArea = iw * ih;
  // 두께가 0에 가까운 축은 padding을 살짝 줘서 "선이 영역을 스치기만
  // 해도 0"이 되는 것을 막는다 — 실제 벽/가구 경계선은 늘 이렇게 얇다.
  final aArea = math.max(a.area, 0.0005);
  return interArea / aArea;
}

const double _textMaxThicknessPx = 2.5;
const double _textMaxLengthPx = 20;
const double _openingProximityPadding = 0.03; // ROI를 살짝 넓혀서 근처 후보도 잡는다.

/// [candidates] 중 reviewNeeded 항목만 GPT 의미 정보를 더해 세분화한다.
/// structural 항목은 그대로 반환한다.
List<PixelWallCandidate> classifyNoiseCategories({
  required List<PixelWallCandidate> candidates,
  required GptSemanticResponse? semantic,
}) {
  if (semantic == null) return candidates;

  GptApproxRegion pad(GptApproxRegion r) => GptApproxRegion(
    x0: r.x0 - _openingProximityPadding,
    y0: r.y0 - _openingProximityPadding,
    x1: r.x1 + _openingProximityPadding,
    y1: r.y1 + _openingProximityPadding,
  );

  return [
    for (final c in candidates)
      if (c.category != PixelWallCategory.reviewNeeded)
        c
      else
        _classifyOne(c, semantic, pad),
  ];
}

PixelWallCandidate _classifyOne(
  PixelWallCandidate c,
  GptSemanticResponse semantic,
  GptApproxRegion Function(GptApproxRegion) pad,
) {
  final bbox = _candidateBbox(c);

  for (final opening in semantic.openings) {
    if (_containmentRatio(bbox, pad(opening.approxRegion)) > 0.4) {
      return c.withNoiseCategory(
        opening.type == 'window' ? PixelWallNoiseCategory.windowDetail : PixelWallNoiseCategory.doorArc,
      );
    }
  }

  for (final furniture in semantic.furnitureRegions) {
    if (_containmentRatio(bbox, furniture.approxRegion) > 0.5) {
      final insideBathroom = semantic.spaces.any(
        (s) => s.semanticType.toLowerCase().contains('bath') && _containmentRatio(bbox, s.approxRegion) > 0.8,
      );
      return c.withNoiseCategory(insideBathroom ? PixelWallNoiseCategory.fixture : PixelWallNoiseCategory.furniture);
    }
  }

  // thickness/length는 extractPixelWalls 호출부가 넘겨준 analysis 해상도
  // 기준으로 다시 계산해야 하지만, 이 함수는 분류만 하므로 정규화 값을
  // 그대로 비율로 비교해도 충분하다(픽셀 환산은 파이프라인에서 이미
  // reviewNeeded 판정에 쓰인 것과 동일한 기준 — 여기서는 추가로 "매우
  // 얇고 매우 짧다"만 재확인).
  return c;
}

/// pixel 해상도를 아는 파이프라인 쪽에서 두께/길이 기준 TEXT 판정을
/// 마저 적용한다(정규화 좌표만으로는 종횡비 문제로 부정확할 수 있어
/// 분리했다).
List<PixelWallCandidate> applyTextHeuristic({
  required List<PixelWallCandidate> candidates,
  required int analysisWidthPx,
  required int analysisHeightPx,
}) {
  return [
    for (final c in candidates)
      if (c.category != PixelWallCategory.reviewNeeded || c.noiseCategory != PixelWallNoiseCategory.trueStructural)
        c
      else if (_thicknessPx(c, analysisWidthPx, analysisHeightPx) <= _textMaxThicknessPx &&
          _lengthPx(c, analysisWidthPx, analysisHeightPx) <= _textMaxLengthPx &&
          c.junctionSupport <= 1)
        c.withNoiseCategory(PixelWallNoiseCategory.text)
      else
        c.withNoiseCategory(PixelWallNoiseCategory.unknown),
  ];
}
