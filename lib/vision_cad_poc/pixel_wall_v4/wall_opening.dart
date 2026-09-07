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
}) {
  WallSystem? best;
  var bestCrossDist = double.infinity;
  for (final system in systems) {
    if (system.orientation != orientation) continue; // 방향 다르면 제외(§5).
    final tolerance = _matchTolerance(system.thicknessPx, candidateThicknessPx);
    final crossDist = (crossPx - system.axisPx).abs();
    if (crossDist > tolerance) continue; // collinear 아님 — 제외.
    if (alongPx < system.startAlongPx - tolerance || alongPx > system.endAlongPx + tolerance) {
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
/// 낫다, §16).
List<WallOpening> buildWallOpenings({
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
  return openings;
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
