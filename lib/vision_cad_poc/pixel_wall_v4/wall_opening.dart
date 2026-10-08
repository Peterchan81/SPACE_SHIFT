// SPACE SHIFT — PC1 CONTINUE: DOOR/WINDOW → PARENT WALL + PARAMETRIC OPENING.
//
// 핵심 원칙(§1): 문/창은 room/topology wall boundary를 끊지 않는다.
// [WallSystem](wall_system.dart)이 이미 "문/창이 있어도 연속된 구조
// 벽"(parent WallEdge) 그 자체다 — segments가 물리 벽 자재 조각,
// gaps가 그 사이 틈이다. 이 파일은 그 gaps 중 문/창 크기 범위인 것만
// 골라 정규화된 interval(startT/endT)을 가진 [WallOpening]으로 만들고,
// GPT 의미 ROI 근거(doorArc/windowDetail)가 있으면 종류를 확정한다(§7:
// imageBreak/openPlan/notConnected gap은 절대 Opening이 되지 않는다 —
// 근거 없이 문을 만들지 않는다).

import 'dart:math' as math;

import 'pixel_wall_types.dart';
import 'wall_system.dart';

enum OpeningKind { door, window, unknownOpening }

/// §4 — 이 opening의 근거가 어디서 왔는지. 기존 SSEntitySource(vision/
/// geometry/ocr/user/validated)와 다른, 이 opening-매칭 계층 전용 분류다
/// (최종 SSOpening으로 변환할 때만 SSEntitySource로 접는다 — 두 계층을
/// 섞지 않는다).
enum OpeningEvidenceSource { pixel, semanticAi, geometry, userEdited }

/// 문/창/미상 개구부 하나 — 항상 하나의 [WallSystem](parent wall) 위의
/// 정규화된 interval[startT, endT]로만 존재한다. 물리 벽 자재를 자르는
/// 것은 렌더링 단계의 책임이고, 이 모델 자체는 위상(topology)을 절대
/// 깨지 않는다(§1).
class WallOpening {
  const WallOpening({
    required this.id,
    required this.kind,
    required this.parentWallId,
    required this.startT,
    required this.endT,
    required this.confidence,
    required this.reviewNeeded,
    required this.source,
    this.provenance = const [],
  });

  final String id;
  final OpeningKind kind;

  /// [WallSystem.id] — 이 opening이 속한 연속 구조 벽.
  final String parentWallId;

  /// parentWallId를 따라 0.0~1.0로 정규화된 시작/끝 — 0.0 <= startT <
  /// endT <= 1.0.
  final double startT;
  final double endT;

  final double confidence;
  final bool reviewNeeded;
  final OpeningEvidenceSource source;

  /// 이 opening을 만든 근거 id들(WallSystem id, 앞뒤 물리 segment id,
  /// 매칭된 GPT 의미 candidate id 등) — 어디서 왔는지 항상 추적 가능해야
  /// 한다(§4 provenance).
  final List<String> provenance;

  bool get isValidInterval => startT.isFinite && endT.isFinite && startT >= 0 && endT <= 1 && startT < endT;
}

const double _matchTolMinPx = 8.0;
const double _matchTolMaxPx = 24.0;

double _matchTolerance(double a, double b) => (math.max(a, b) * 1.5).clamp(_matchTolMinPx, _matchTolMaxPx);

/// §5 PARENT WALL MATCHING — collinearity(같은 axis, 두께 기반 허용
/// 오차) + interval이 실제로 그 벽의 extent 안에 있는지로만 판정한다.
/// 순수 Euclidean 최단거리로 아무 벽에나 붙이지 않는다 — 방향이 다르거나
/// extent 밖이면 "더 가까워 보여도" 후보에서 제외된다.
WallSystem? matchParentWallSystem({
  required List<WallSystem> systems,
  required PixelWallOrientation orientation,
  required double crossPx,
  required double alongPx,
  required double candidateThicknessPx,
  // CAD/DXF FIRST GOAL 인식 품질 개선 WO §2(계속) — collinearity(crossPx)
  // 허용 오차는 그대로 두고, "그 벽의 extent 밖" 판정에만 별도로 더 넓은
  // 오차를 쓸 수 있게 한다. 실제 실측도면에서 GPT가 지목한 문 위치가
  // 진짜 그 벽 line 위(같은 축, 4~5px 이내)에 있는데도, run-length
  // 검출이 얇고 흐릿한 손그림 선 끝을 몇십 px 짧게 잡아서(연필 끝이
  // 흐려지는 지점) opening이 유효 extent 밖으로 밀려나는 사례가 확인됐다
  // (§ 조사: pxwall-47 실제 벽, hint와 collinear 오차 4.7px, 다만 extent가
  // 23.8px 부족해 실패). collinearity는 여전히 엄격하게 유지해(§5 "순수
  // 최단거리로 아무 벽에나 붙이지 않는다") 다른 벽으로 잘못 붙는 위험을
  // 늘리지 않는다 — null(기본값)이면 기존과 완전히 동일하게 동작한다.
  double? extentTolerancePx,
}) {
  WallSystem? best;
  var bestCrossDist = double.infinity;
  for (final system in systems) {
    if (system.orientation != orientation) continue; // 방향 다르면 제외(§5).
    final tolerance = _matchTolerance(system.thicknessPx, candidateThicknessPx);
    final crossDist = (crossPx - system.axisPx).abs();
    if (crossDist > tolerance) continue; // collinear 아님 — 제외(항상 엄격).
    final extentTolerance = extentTolerancePx ?? tolerance;
    if (alongPx < system.startAlongPx - extentTolerance || alongPx > system.endAlongPx + extentTolerance) {
      continue; // 이 벽의 extent 밖 — 제외.
    }
    if (crossDist < bestCrossDist) {
      bestCrossDist = crossDist;
      best = system;
    }
  }
  return best;
}

/// §6/§7/§8 — 각 WallSystem의 doorOpening 크기 gap만 Opening 후보로
/// 삼는다(imageBreak/openPlan/notConnected는 제외 — §7 "imageBreak는
/// 자동으로 Door가 아니다"). GPT doorArc/windowDetail 의미 근거가 그
/// interval과 실제로 겹치면 종류를 door/window로 확정하고
/// reviewNeeded=false로 내린다 — 겹치는 근거가 없으면 unknownOpening +
/// reviewNeeded=true로 남긴다(정확히 미상인 편이 잘못 분류하는 것보다
/// 낫다, §16). pixel gap 자체가 없어도 GPT hint가 실제 wall system 근처에
/// 있으면 reviewNeeded 상태로 만든다(아래 §2 인식 품질 개선 참고).
WallOpeningBuildResult buildWallOpenings({
  required List<WallSystem> wallSystems,
  required List<PixelWallCandidate> allCandidates,
  required int w,
  required int h,
}) {
  double crossPxOf(PixelWallCandidate c) =>
      c.orientation == PixelWallOrientation.horizontal ? c.start.y * h : c.start.x * w;
  double alongPxOf(PixelWallCandidate c) => c.orientation == PixelWallOrientation.horizontal
      ? ((c.start.x + c.end.x) / 2) * w
      : ((c.start.y + c.end.y) / 2) * h;
  double thicknessPxOf(PixelWallCandidate c) =>
      c.thicknessNormalized * (c.orientation == PixelWallOrientation.horizontal ? h : w);
  double alongMinPxOf(PixelWallCandidate c) => c.orientation == PixelWallOrientation.horizontal
      ? math.min(c.start.x, c.end.x) * w
      : math.min(c.start.y, c.end.y) * h;
  double alongMaxPxOf(PixelWallCandidate c) => c.orientation == PixelWallOrientation.horizontal
      ? math.max(c.start.x, c.end.x) * w
      : math.max(c.start.y, c.end.y) * h;

  // GPT 의미 ROI와 겹쳐 doorArc/windowDetail로 분류된, 이미 구조 벽에서는
  // 제외된 reviewNeeded candidate들 — 여기서는 버리지 않고 opening 종류를
  // 확정하는 근거로 재사용한다(§3 MODEL GAP에서 확인된 "지금은 버려지는
  // 근거").
  final semanticHints = allCandidates
      .where((c) => c.noiseCategory == PixelWallNoiseCategory.doorArc || c.noiseCategory == PixelWallNoiseCategory.windowDetail)
      .toList();

  final openings = <WallOpening>[];
  var counter = 0;
  for (final system in wallSystems) {
    for (var k = 0; k < system.gaps.length; k++) {
      final gap = system.gaps[k];
      if (gap.kind != GapKind.doorOpening) continue;
      if (system.lengthPx <= 0) continue;

      final centerAlong = system.orientation == PixelWallOrientation.horizontal ? gap.centerPx.x : gap.centerPx.y;
      final alongStart = centerAlong - gap.gapPx / 2;
      final alongEnd = centerAlong + gap.gapPx / 2;
      final startT = ((alongStart - system.startAlongPx) / system.lengthPx).clamp(0.0, 1.0);
      final endT = ((alongEnd - system.startAlongPx) / system.lengthPx).clamp(0.0, 1.0);
      if (startT >= endT) continue; // 방어적 — 정상 데이터에서는 발생하지 않아야 한다.

      PixelWallCandidate? matchedHint;
      for (final hint in semanticHints) {
        if (hint.orientation != system.orientation) continue;
        final tolerance = _matchTolerance(system.thicknessPx, thicknessPxOf(hint));
        if ((crossPxOf(hint) - system.axisPx).abs() > tolerance) continue;
        final hintAlong = alongPxOf(hint);
        if (hintAlong < alongStart - tolerance || hintAlong > alongEnd + tolerance) continue;
        matchedHint = hint;
        break;
      }

      final segBefore = system.segments[k];
      final segAfter = system.segments[k + 1];
      final provenance = <String>[system.id, segBefore.id, segAfter.id];

      var kind = OpeningKind.unknownOpening;
      var source = OpeningEvidenceSource.pixel;
      var confidence = (segBefore.baseConfidence + segAfter.baseConfidence) / 2;
      var reviewNeeded = true;
      if (matchedHint != null) {
        kind = matchedHint.noiseCategory == PixelWallNoiseCategory.doorArc ? OpeningKind.door : OpeningKind.window;
        source = OpeningEvidenceSource.semanticAi;
        confidence = matchedHint.baseConfidence;
        reviewNeeded = false;
        provenance.add(matchedHint.id);
      }

      openings.add(WallOpening(
        id: 'opening-${counter++}',
        kind: kind,
        parentWallId: system.id,
        startT: startT,
        endT: endT,
        confidence: confidence,
        reviewNeeded: reviewNeeded,
        source: source,
        provenance: provenance,
      ));
    }
  }

  // CAD/DXF FIRST GOAL 인식 품질 개선 WO §2 — 실제 실측도면 LIVE 검증에서
  // GPT semantic이 문을 감지했는데도(doorArc hint까지 만들어졌는데도)
  // 최종 CadFloorPlan에는 0개만 남는 사례가 확인됐다. 원인: 위 루프는
  // WallSystem 내부에 이미 존재하는 pixel gap(GapKind.doorOpening)의
  // "종류"만 doorArc/windowDetail hint로 확정할 뿐, gap 자체가 없으면
  // (예: 이 사진처럼 pixel 근거가 부실해 구조 벽이 조각조각 reviewNeeded로
  // 빠지고 남은 structural segment가 끊김 없이 이어져 버린 경우) hint가
  // 있어도 opening을 아예 만들지 않아 semantic evidence가 조용히
  // 버려졌다. 여기서는 gap 매칭에 쓰이지 못한 hint를 대상으로
  // matchParentWallSystem(§5, 기존 collinearity+extent 판정 재사용)으로
  // 실제 근처 wall system을 찾아 opening을 만든다 — pixel gap 근거가
  // 없으므로 항상 reviewNeeded=true로 남겨 사람 확인을 요구한다(§16 "정확히
  // 미상인 편이 잘못 분류하는 것보다 낫다"와 동일한 정직성 원칙). 근처에
  // 매칭되는 wall system이 전혀 없으면(진짜 벽 geometry 자체가 없음) 조용히
  // 버리지 않고 unmatchedHints로 남긴다(§10 "절대 조용히 버리지 않는다").
  // CAD/DXF FIRST GOAL 인식 품질 개선 WO §2(계속) — 위 1차 시도조차 실제
  // 실측도면에서는 대부분 실패했다: hint 근처의 진짜 벽이 애초에
  // `structural`(=wallSystems)로 확정되지 못하고 reviewNeeded(trueStructural/
  // unknown)로 남는 경우가 많기 때문이다(§ pixel_wall_extractor.dart의
  // structural 판정 기준이 낮은 품질 사진에서는 보수적으로 작동). 그렇다고
  // reviewNeeded candidate를 무작정 신뢰해 구조 벽으로 승격하지는 않는다
  // (§6 "이미 근거 충분한 것만 구조 벽" 원칙 유지) — 대신 "GPT가 독립적으로
  // 여기 문/창이 있다고 지목한 지점 바로 옆에, 노이즈로 확정되지 않은
  // (trueStructural/unknown) pixel 증거가 실제로 있다"는 두 증거의 교차
  // 검증만 이 opening 하나에 한해 허용한다 — 그 reviewNeeded candidate
  // 자체를 다른 곳에서 구조 벽으로 취급하지 않는다(startAlongPx/endAlongPx가
  // 이 candidate 하나 길이로만 한정된 1-segment 임시 시스템이라 opening
  // interval도 그 범위를 벗어날 수 없다).
  WallSystem singleCandidateSystem(PixelWallCandidate c) {
    final a0 = alongMinPxOf(c);
    final a1 = alongMaxPxOf(c);
    return WallSystem(
      id: 'reviewwall-${c.id}',
      orientation: c.orientation,
      axisPx: crossPxOf(c),
      isExterior: c.isExterior,
      segments: [c],
      gaps: const [],
      startAlongPx: a0,
      endAlongPx: a1,
      thicknessPx: thicknessPxOf(c),
    );
  }

  final reviewCandidatePool = allCandidates.where(
    (c) =>
        c.category == PixelWallCategory.reviewNeeded &&
        (c.noiseCategory == PixelWallNoiseCategory.trueStructural || c.noiseCategory == PixelWallNoiseCategory.unknown),
  );
  final reviewSystems = [for (final c in reviewCandidatePool) singleCandidateSystem(c)];

  final usedHintIds = {
    for (final o in openings)
      if (o.source == OpeningEvidenceSource.semanticAi) o.provenance.last,
  };
  final unmatchedHints = <PixelWallCandidate>[];
  final extraWallSystems = <WallSystem>[];
  for (final hint in semanticHints) {
    if (usedHintIds.contains(hint.id)) continue;
    final crossPx = crossPxOf(hint);
    final alongPx = alongPxOf(hint);
    final thicknessPx = thicknessPxOf(hint);
    var system = matchParentWallSystem(
      systems: wallSystems,
      orientation: hint.orientation,
      crossPx: crossPx,
      alongPx: alongPx,
      candidateThicknessPx: thicknessPx,
    );
    var fromReviewPool = false;
    if (system == null) {
      // extentTolerancePx: collinearity(같은 축, 몇 px 이내)는 그대로
      // 엄격하게 유지하면서, "이 벽 line의 감지된 끝점"만 조금 더
      // 넉넉하게 봐준다 — 얇고 흐릿한 손그림 선의 run-length 검출이
      // 실제 끝보다 짧게 멈추는 경우를 보정한다(§ 위 문서 참고). 이
      // 값(40px)은 실측 조사에서 필요했던 23.8px에 여유를 더한 것이며,
      // collinearity 기준(보통 8px)과는 별개다 — "아무 벽에나 붙는"
      // 위험은 늘리지 않는다.
      system = matchParentWallSystem(
        systems: reviewSystems,
        orientation: hint.orientation,
        crossPx: crossPx,
        alongPx: alongPx,
        candidateThicknessPx: thicknessPx,
        extentTolerancePx: 40,
      );
      fromReviewPool = system != null;
    }
    if (system == null || system.lengthPx <= 0) {
      unmatchedHints.add(hint);
      continue;
    }

    final hintLenPx = hint.orientation == PixelWallOrientation.horizontal
        ? (hint.end.x - hint.start.x).abs() * w
        : (hint.end.y - hint.start.y).abs() * h;
    final halfWidthPx = math.max(hintLenPx / 2, _matchTolMinPx);
    // CAD/DXF FIRST GOAL 인식 품질 개선 WO §2(계속) — extentTolerancePx로
    // "이 벽 extent 밖" 판정만 넉넉하게 봐줘도, hint의 위치 자체가 여전히
    // system의 실제 감지된 extent [startAlongPx, endAlongPx] 밖에 있으면
    // alongStart/alongEnd를 각각 독립적으로 clamp할 때 둘 다 같은 경계
    // 값으로 무너져(둘 다 startAlongPx로 붙어버림) startT==endT인 폭 0
    // interval이 되고, 그 결과가 다시 무효 처리되어 조용히
    // unmatchedHints로 떨어지는 2차 버그가 있었다(실측 조사로 확인:
    // pxwall-47을 부모로 찾고도 이 단계에서 다시 버려짐). 중심점을 먼저
    // extent 안으로 clamp한 뒤 그 중심을 기준으로 폭을 두면, 최소
    // halfWidthPx만큼은 항상 system extent 안에 남는다.
    final clampedAlongPx = alongPx.clamp(system.startAlongPx, system.endAlongPx);
    final alongStart = (clampedAlongPx - halfWidthPx).clamp(system.startAlongPx, system.endAlongPx);
    final alongEnd = (clampedAlongPx + halfWidthPx).clamp(system.startAlongPx, system.endAlongPx);
    final startT = ((alongStart - system.startAlongPx) / system.lengthPx).clamp(0.0, 1.0);
    final endT = ((alongEnd - system.startAlongPx) / system.lengthPx).clamp(0.0, 1.0);
    if (startT >= endT) {
      unmatchedHints.add(hint);
      continue;
    }

    if (fromReviewPool) extraWallSystems.add(system);
    openings.add(WallOpening(
      id: 'opening-${counter++}',
      kind: hint.noiseCategory == PixelWallNoiseCategory.doorArc ? OpeningKind.door : OpeningKind.window,
      parentWallId: system.id,
      startT: startT,
      endT: endT,
      confidence: hint.baseConfidence,
      reviewNeeded: true,
      source: OpeningEvidenceSource.semanticAi,
      provenance: [system.id, hint.id],
    ));
  }

  return WallOpeningBuildResult(
    openings: openings,
    unmatchedSemanticHints: unmatchedHints,
    extraWallSystems: extraWallSystems,
  );
}

/// [buildWallOpenings] 결과 — pixel gap 근거 유무와 무관하게 확정된
/// [openings]와, GPT가 문/창이라고 짚었지만 근처에 매칭되는 wall system이
/// 전혀 없어(진짜 벽 geometry 자체가 없어) opening으로 만들 수 없었던
/// [unmatchedSemanticHints](§10 "절대 조용히 버리지 않는다" — 호출부가
/// warning으로 노출한다). [extraWallSystems]는 reviewNeeded candidate
/// 풀에서 GPT hint와의 교차 검증으로 새로 만들어진 1-segment 임시
/// WallSystem — 호출부(pixel_wall_pipeline.dart)가 자신의 wallSystems
/// 목록에 합쳐야 opening.parentWallId 조회가 성립한다.
class WallOpeningBuildResult {
  const WallOpeningBuildResult({
    required this.openings,
    required this.unmatchedSemanticHints,
    this.extraWallSystems = const [],
  });
  final List<WallOpening> openings;
  final List<PixelWallCandidate> unmatchedSemanticHints;
  final List<WallSystem> extraWallSystems;
}

class RejectedOpening {
  const RejectedOpening({required this.opening, required this.reason});
  final WallOpening opening;
  final String reason;
}

class OpeningValidationResult {
  const OpeningValidationResult({required this.valid, required this.rejected});
  final List<WallOpening> valid;
  final List<RejectedOpening> rejected;
}

/// §10 — 절대 조용히 버리지 않는다: 유효하지 않은 opening은 [rejected]에
/// 이유와 함께 남는다. 검사 항목: parentWallId 존재 여부, interval
/// 유효성([0,1] 안, startT < endT), 같은 벽 위에서 서로 다른 종류로
/// 겹치는 opening(충돌).
OpeningValidationResult validateOpenings({
  required List<WallOpening> openings,
  required Set<String> validParentWallIds,
}) {
  final valid = <WallOpening>[];
  final rejected = <RejectedOpening>[];
  final byWall = <String, List<WallOpening>>{};

  for (final o in openings) {
    if (o.parentWallId.isEmpty || !validParentWallIds.contains(o.parentWallId)) {
      rejected.add(RejectedOpening(opening: o, reason: '존재하지 않는 parentWallId: "${o.parentWallId}"'));
      continue;
    }
    if (!o.isValidInterval) {
      rejected.add(RejectedOpening(opening: o, reason: '잘못된 interval(startT=${o.startT}, endT=${o.endT})'));
      continue;
    }
    valid.add(o);
    byWall.putIfAbsent(o.parentWallId, () => []).add(o);
  }

  final conflictIds = <String>{};
  for (final list in byWall.values) {
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final a = list[i];
        final b = list[j];
        final overlaps = a.startT < b.endT && b.startT < a.endT;
        if (overlaps && a.kind != b.kind) {
          conflictIds.add(a.id);
          conflictIds.add(b.id);
        }
      }
    }
  }

  if (conflictIds.isEmpty) {
    return OpeningValidationResult(valid: valid, rejected: rejected);
  }

  final stillValid = <WallOpening>[];
  for (final o in valid) {
    if (conflictIds.contains(o.id)) {
      rejected.add(RejectedOpening(opening: o, reason: '같은 parent wall 위에서 다른 종류의 opening과 겹침(충돌)'));
    } else {
      stillValid.add(o);
    }
  }
  return OpeningValidationResult(valid: stillValid, rejected: rejected);
}
