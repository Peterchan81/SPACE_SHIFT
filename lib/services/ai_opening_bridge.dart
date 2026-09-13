import 'dart:math' as math;
import 'dart:typed_data';

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/vision_understanding.dart';
import 'hinted_geometry_extractor.dart';
import 'vision_interpretation_service.dart';

/// SPACE SHIFT — AI×CV CANONICAL MERGE (문/창 우선) WO.
///
/// 지금까지 실제 CV 벽 검출 파이프라인([buildCadFloorPlan])은 벽 geometry는
/// 풍부하지만(예: 평면도.PNG에서 189개) 문/창 gap을 전혀 찾지 못했고
/// (openings=0), 별도 AI Vision 이해 경로([VisionInterpretationService])는
/// 문/창을 실제로 인식하지만(예: doors=2) 자체 boundary 목록이 훨씬
/// 성글다(예: boundaries=6) — 두 결과를 그대로 쓰면 "2D에서 보이는 문/창"과
/// "3D에 반영된 벽"이 서로 다른 벽 집합을 가리키게 된다.
///
/// 이 파일은 그 둘을 합치는 최소 다리다 — 새 wall geometry를 만들지
/// 않는다(§ CV의 189개 벽을 그대로 유지). 대신:
///
/// AI(semantic) — "여기(대략 어디)에 문/창이 있다"
///   ↓
/// 이미 검증된 CV wall geometry 중 가장 가까운 실제 벽을 찾는다
///   ↓
/// [HintedGeometryExtractor.refineOpening](geometric evidence) — 그 실제
/// 벽의 시작/끝점 사이에서 원본 이미지 픽셀로 gap이 실제로 있는지
/// 독립적으로 재확인하고, 있다면 정확한 중심/폭을 잰다
///   ↓
/// SS(canonical) — 검증된 것만 실제 [CadOpening](wallId = 실제 CadWall.id)
/// 으로 합친다.
///
/// AI가 문/창이라고 주장해도 그 벽 근처에 실제 픽셀 gap이 없으면
/// 절대 반영하지 않는다(근거 없는 문/창을 지어내지 않는다) — 그 경우
/// [CadFloorPlan.warnings]에 정직하게 남긴다. Vision 서비스 자체가
/// 실패/미설정이어도 이 함수는 절대 예외를 던지지 않고, 원본 [plan]을
/// 그대로 돌려주며 이유를 경고에 남긴다(화면은 절대 죽지 않는다).
Future<CadFloorPlan> mergeAiDetectedOpenings({
  required CadFloorPlan plan,
  required Uint8List originalImageBytes,
  required VisionInterpretationService visionService,
}) async {
  final VisionUnderstanding understanding;
  try {
    understanding = await visionService.interpret(originalImageBytes);
  } catch (e) {
    return _withWarning(plan, 'AI 문/창 감지를 사용할 수 없어 건너뜁니다: $e');
  }

  if (understanding.openings.isEmpty) {
    return _withWarning(plan, 'AI가 이 도면에서 문/창 후보를 감지하지 못했습니다 — 기존 벽 geometry만 사용합니다.');
  }
  if (plan.walls.isEmpty) {
    return _withWarning(plan, '연결할 실제 벽이 없어 AI 문/창 감지 결과를 반영하지 못했습니다.');
  }

  final extractor = HintedGeometryExtractor(originalImageBytes);
  if (!extractor.isReady) {
    return _withWarning(plan, '원본 이미지를 다시 읽지 못해 AI 문/창 개구부를 pixel로 검증하지 못했습니다.');
  }

  // WO097 — anisotropic(가로≠세로) 이미지에서 거리 계산은 반드시 실제
  // 픽셀 공간에서 해야 한다(정규화 좌표를 그대로 쓰면 종횡비가 다른
  // 이미지에서 거리 비교가 왜곡된다).
  final maxSnapDistancePx = plan.diagonalPx * 0.04;

  final newOpenings = <CadOpening>[];
  final warnings = <String>[];
  var mergedCount = 0;
  var skippedNoWall = 0;
  var skippedNoGapEvidence = 0;
  var aiOpeningIndex = 0;

  for (final opening in understanding.openings) {
    aiOpeningIndex++;
    final hintPoint = _hintPoint(opening.geometryHint);
    if (hintPoint == null) {
      warnings.add('AI 개구부 후보 $aiOpeningIndex: 사용 가능한 위치 힌트가 없어 건너뜁니다.');
      continue;
    }

    final nearest = _nearestWall(plan, hintPoint);
    if (nearest == null || nearest.distancePx > maxSnapDistancePx) {
      skippedNoWall++;
      warnings.add(
        'AI 개구부 후보 $aiOpeningIndex(${_typeLabel(opening.openingType)}): 벽 연결 정보 없음/불일치 — '
        '가까운 실제 벽을 찾지 못해 건너뜁니다.',
      );
      continue;
    }
    final wall = nearest.wall;

    final geometryResult = extractor.refineOpening(
      boundaryStart: NormalizedPoint(wall.start.x, wall.start.y),
      boundaryEnd: NormalizedPoint(wall.end.x, wall.end.y),
      openingHint: hintPoint,
    );

    if (!geometryResult.found || geometryResult.wallContinuous) {
      skippedNoGapEvidence++;
      warnings.add(
        'AI 개구부 후보 $aiOpeningIndex(${_typeLabel(opening.openingType)}, 벽 ${wall.id} 근처): '
        '실제 픽셀에서 벽이 끊기지 않아(gap 없음) 반영하지 않습니다 — 지어내지 않습니다.',
      );
      continue;
    }

    final center = geometryResult.center;
    final widthNormalized = geometryResult.widthNormalized;
    if (center == null || widthNormalized == null || widthNormalized <= 0) {
      skippedNoGapEvidence++;
      warnings.add('AI 개구부 후보 $aiOpeningIndex: gap을 찾았지만 크기를 확정하지 못해 건너뜁니다.');
      continue;
    }

    final visionTypeConfident = opening.confidence == VisionConfidence.high ||
        opening.confidence == VisionConfidence.medium;
    final snapIsClose = nearest.distancePx <= maxSnapDistancePx * 0.5;

    newOpenings.add(
      CadOpening(
        id: 'ai-opening-$aiOpeningIndex',
        // pixel evidence는 "여기 gap이 있다"만 확인해줄 뿐 문/창을
        // 구분해주지 않는다 — 그 분류는 AI semantic 판단을 그대로
        // 쓴다(§ VisionGeometryMatcher의 CASE 원칙과 동일).
        type: switch (opening.openingType) {
          VisionOpeningType.door => OpeningType.door,
          VisionOpeningType.window => OpeningType.window,
          VisionOpeningType.openPassage => OpeningType.unknown,
        },
        center: Point2(center.x, center.y),
        widthNormalized: widthNormalized,
        confidence: visionTypeConfident && snapIsClose ? 0.85 : 0.6,
        wallId: wall.id,
        source: CadElementSource.analyzed,
        reviewNeeded: !visionTypeConfident || !snapIsClose,
        reviewReasons: [
          if (!visionTypeConfident) 'AI가 문/창 종류를 낮은 확신으로 판단했습니다 — pixel은 gap 존재만 확인했습니다.',
          if (!snapIsClose) 'AI가 지목한 위치와 실제 벽 사이 거리가 다소 멀어(스냅) 확인이 필요합니다.',
        ],
      ),
    );
    mergedCount++;
  }

  if (mergedCount > 0) {
    warnings.add(
      'AI가 감지한 문/창 개구부 $mergedCount개를 실제 벽의 pixel gap으로 확인해 반영했습니다 '
      '(건너뜀: 벽 연결 실패 $skippedNoWall개, gap 근거 없음 $skippedNoGapEvidence개).',
    );
  }

  if (newOpenings.isEmpty) return _withWarning(plan, warnings.join(' '));

  return CadFloorPlan(
    sourceWidthPx: plan.sourceWidthPx,
    sourceHeightPx: plan.sourceHeightPx,
    walls: plan.walls,
    openings: [...plan.openings, ...newOpenings],
    rooms: plan.rooms,
    warnings: [...plan.warnings, ...warnings],
    objectCandidates: plan.objectCandidates,
  );
}

CadFloorPlan _withWarning(CadFloorPlan plan, String warning) => CadFloorPlan(
  sourceWidthPx: plan.sourceWidthPx,
  sourceHeightPx: plan.sourceHeightPx,
  walls: plan.walls,
  openings: plan.openings,
  rooms: plan.rooms,
  warnings: [...plan.warnings, warning],
  objectCandidates: plan.objectCandidates,
);

String _typeLabel(VisionOpeningType type) => switch (type) {
  VisionOpeningType.door => '문',
  VisionOpeningType.window => '창',
  VisionOpeningType.openPassage => '개방형 통로',
};

/// [hint]에서 매칭에 쓸 대표 점 하나를 뽑는다 — point가 아니면 첫 점을
/// 대신 쓴다(폭/방향 정보가 없는 대략의 위치 힌트라도 매칭 시도는
/// 한다).
NormalizedPoint? _hintPoint(GeometryHint? hint) {
  if (hint == null) return null;
  if (hint.kind == GeometryHintKind.point) return hint.point;
  final points = hint.allPoints;
  return points.isEmpty ? null : points.first;
}

class _NearestWallResult {
  const _NearestWallResult(this.wall, this.distancePx);
  final CadWall wall;
  final double distancePx;
}

/// [point](정규화 좌표)에서 [plan]의 모든 벽까지 실제 픽셀 공간
/// point-to-segment 거리를 계산해 가장 가까운 벽을 찾는다.
_NearestWallResult? _nearestWall(CadFloorPlan plan, NormalizedPoint point) {
  final w = plan.sourceWidthPx.toDouble();
  final h = plan.sourceHeightPx.toDouble();
  final px = point.x * w, py = point.y * h;

  CadWall? best;
  var bestDist = double.infinity;
  for (final wall in plan.walls) {
    final ax = wall.start.x * w, ay = wall.start.y * h;
    final bx = wall.end.x * w, by = wall.end.y * h;
    final dist = _pointToSegmentDistance(px, py, ax, ay, bx, by);
    if (dist < bestDist) {
      bestDist = dist;
      best = wall;
    }
  }
  if (best == null) return null;
  return _NearestWallResult(best, bestDist);
}

double _pointToSegmentDistance(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final abx = bx - ax, aby = by - ay;
  final lenSq = abx * abx + aby * aby;
  if (lenSq < 1e-9) return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
  final t = (((px - ax) * abx + (py - ay) * aby) / lenSq).clamp(0.0, 1.0);
  final projX = ax + t * abx, projY = ay + t * aby;
  return math.sqrt((px - projX) * (px - projX) + (py - projY) * (py - projY));
}
