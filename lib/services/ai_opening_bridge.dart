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
///
/// OPENING BRIDGE 정밀 진단 WO — 실제 평면도.PNG로 6개 AI 문 후보를
/// 하나씩 진단한 결과("가장 가까운 벽 하나"만 시도하던 이전 버전의
/// 근본 한계): 실제 코너(두 벽이 만나는 지점) 근처의 AI hint는 수평
/// 벽과 수직 벽까지의 거리가 비슷비슷해서(예: 57.0px vs 57.4px vs
/// 59.1px) 단순히 "제일 가까운 벽 1개"만 고르면 그게 우연히 틀린
/// 벽일 수 있다 — 그러면 진짜 gap이 있는 벽은 아예 시도조차 되지
/// 않는다. AI 자체의 `attachedBoundaryId`/`connectedSpaceIds`는 이
/// 실측에서 hint 위치와 모순되는 경우가 있어(예: 문 hint는 위쪽인데
/// attachedBoundaryId가 가리키는 boundary는 아래쪽) 신뢰할 수 있는
/// 방향 신호로 쓰지 않는다 — 대신 "근처 벽 후보 여러 개에 실제 pixel
/// gap 검증을 각각 시도하고, 실제로 gap이 있는 첫 번째 벽만 채택"
/// 하는 방식으로 바꾼다. 최종 판정은 언제나 [HintedGeometryExtractor]
/// 의 실제 pixel 증거이므로, 후보를 여러 개 시도해도 "근거 없는 문을
/// 지어내는" 위험은 늘지 않는다 — 늘어나는 건 "진짜 gap이 있는 올바른
/// 벽을 찾을 기회"뿐이다.
Future<CadFloorPlan> mergeAiDetectedOpenings({
  required CadFloorPlan plan,
  required Uint8List originalImageBytes,
  required VisionInterpretationService visionService,
  int sampleCount = 3,
}) async {
  // OPENING BRIDGE 정밀 진단 WO — 실제 반복 호출로 확인한 것: 같은
  // 원본 이미지를 같은 서비스로 반복 호출해도 GPT 응답의 opening hint
  // 위치는 호출마다 상당히 달라진다(예: 어떤 호출은 문 6개를 감지하되
  // 전부 실제 벽에서 60px 이상 떨어져 있고, 다른 호출은 완전히 다른
  // 위치를 가리킨다). 한 번의 호출 결과만 쓰면 "이 벽에는 실제 gap이
  // 있는데 이번 호출의 hint가 우연히 안 맞았다"는 이유만으로 실제
  // 존재하는 문/창을 계속 놓칠 수 있다.
  //
  // 그래서 같은 모델/프롬프트로 여러 번(기본 3회) 독립 호출해 hint
  // 후보를 모으고, 그 풀 전체에 대해 아래의 동일한 "실제 pixel gap
  // 검증"을 적용한다 — 모델을 재튜닝하는 게 아니라(프롬프트/파라미터/
  // 모델 자체는 전혀 바꾸지 않는다), 같은 모델을 여러 번 표본추출해
  // "실제로 존재하는 문/창 근처에 한 번이라도 hint가 떨어질 확률"을
  // 높이는 것뿐이다 — 최종 채택 여부는 여전히 오직 실제 pixel 증거로만
  // 결정되므로 "지어내기" 위험은 늘지 않는다. 여러 번 감지된 같은
  // 실제 문은 자연히 겹치는 CadOpening 여러 개가 되는데, 이는 이미
  // [buildSpaceSceneV2]가 겹치는 opening을 하나의 구간으로 병합하는
  // 기존 로직(WO097 `_mergeAlongIntervals`)으로 안전하게 처리된다.
  // 호출을 동시에 실행해(Future.wait) 분석 시간이 N배로 늘지 않게 한다.
  final results = await Future.wait(
    List.generate(sampleCount, (_) => visionService.interpret(originalImageBytes)).map(
      (f) => f.then<VisionUnderstanding?>((v) => v).catchError((_) => null),
    ),
  );
  final successfulSamples = results.whereType<VisionUnderstanding>().toList();
  if (successfulSamples.isEmpty) {
    return _withWarning(plan, 'AI 문/창 감지를 사용할 수 없어 건너뜁니다(모든 시도 실패).');
  }
  final pooledOpenings = [for (final s in successfulSamples) ...s.openings];
  final understanding = VisionUnderstanding(floorDomain: successfulSamples.first.floorDomain, openings: pooledOpenings);

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
  //
  // OPENING BRIDGE 정밀 진단 WO — 실제 호출(평면도.PNG)에서 진짜
  // 문으로 보이는 후보의 hint-실제벽 거리가 최대 약 85px(diagonal
  // 1020px 기준 약 8.3%)까지 벌어지는 경우를 확인했다(문 스윙 기호가
  // 벽에서 떨어진 위치에 그려지는 등, AI hint가 "벽 자체"가 아니라
  // "그 근처 심볼 전체"의 대략적 위치를 가리키기 때문으로 보인다).
  // 반면 명백히 무관한 오탐(다른 방 전체를 가로지르는 약 212px,
  // 20%대)도 있었다 — 그 사이인 10%를 상한으로 잡아 전자는 포함하고
  // 후자는 배제한다. 이 상한을 넓혀도 "지어내기" 위험이 커지지 않는
  // 이유는 최종 판정이 항상 [HintedGeometryExtractor]의 실제 pixel
  // gap 검증이기 때문이다 — 상한은 "검증을 시도해볼 후보"를 정할
  // 뿐이다.
  final maxSnapDistancePx = plan.diagonalPx * 0.10;
  // 코너(두 벽이 만나는 지점) 근처의 hint는 여러 벽까지의 거리가
  // 비슷할 수 있어 "가장 가까운 벽 1개"만 시도하면 우연히 틀린 벽을
  // 고를 수 있다 — 가까운 순서로 최대 이만큼 시도해 실제 gap이 있는
  // 첫 번째 벽을 찾는다. 8개 이상으로 더 넓혀 실측했더니, 벽 자체가
  // 매우 긴 경우(예: 600px+) [HintedGeometryExtractor.refineOpening]의
  // along 검색 범위가 사실상 벽 전체를 훑어, hint와 무관한 먼 곳의
  // gap(심지어 노이즈 수준의 3px짜리)까지 "찾음"으로 잘못 채택하는
  // 사례를 확인했다 — 그래서 후보 수를 늘리는 대신, 아래
  // [_isPlausibleMatch]로 "찾은 gap이 실제로 hint 근처에 있고 폭이
  // 그럴듯한지"를 별도로 재확인한다(먼 벽 후보를 무작정 더 시도하는
  // 것보다 안전하다).
  const maxCandidatesPerOpening = 6;
  // 찾은 gap 중심이 AI hint에서 이 거리보다 멀면 채택하지 않는다 —
  // 벽이 길어서 검색 범위가 넓어져도, "이 hint와 무관한 곳의 gap"을
  // 잘못 채택하지 않기 위한 안전장치(위 문서 참고).
  final maxGapCenterDistancePx = maxSnapDistancePx;
  // 노이즈/anti-aliasing 수준의 가짜 "gap"(예: 3px)을 걸러낸다 — 실제
  // 문/창이라면 이보다는 뚜렷하게 넓다. diagonal의 1%는 이 실측
  // 이미지에서 약 10px로, 확인된 진짜 매치(43~59px)보다는 한참
  // 작고 확인된 노이즈(3px)보다는 한참 커서 안전한 하한이다.
  final minPlausibleWidthPx = plan.diagonalPx * 0.01;

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

    final candidates = _nearestWalls(plan, hintPoint, maxSnapDistancePx).take(maxCandidatesPerOpening).toList();
    if (candidates.isEmpty) {
      skippedNoWall++;
      warnings.add(
        'AI 개구부 후보 $aiOpeningIndex(${_typeLabel(opening.openingType)}): 벽 연결 정보 없음/불일치 — '
        '가까운 실제 벽을 찾지 못해 건너뜁니다.',
      );
      continue;
    }

    // 가까운 벽부터 순서대로 실제 pixel gap 여부를 검증하고, 처음으로
    // "진짜 gap이 있다"고 확인되는 벽만 채택한다 — 코너 근처에서
    // 거리만으로는 어느 쪽 벽이 맞는지 애매한 경우를 해결한다(§ 위
    // 클래스 문서). 단, 찾은 gap이 hint에서 너무 멀거나(긴 벽 오검출)
    // 폭이 노이즈 수준이면 그 후보는 버리고 다음 후보를 마저 시도한다.
    CadWall? wall;
    OpeningGeometryResult? geometryResult;
    double matchedDistancePx = 0;
    for (final candidate in candidates) {
      final result = extractor.refineOpening(
        boundaryStart: NormalizedPoint(candidate.wall.start.x, candidate.wall.start.y),
        boundaryEnd: NormalizedPoint(candidate.wall.end.x, candidate.wall.end.y),
        openingHint: hintPoint,
      );
      if (!result.found || result.wallContinuous || result.center == null || result.widthNormalized == null) {
        continue;
      }
      final gapCenterDistPx = _distancePx(plan, result.center!, hintPoint);
      final widthPx = result.widthNormalized! * plan.diagonalPx;
      if (gapCenterDistPx > maxGapCenterDistancePx || widthPx < minPlausibleWidthPx) {
        continue;
      }
      wall = candidate.wall;
      geometryResult = result;
      matchedDistancePx = candidate.distancePx;
      break;
    }

    if (wall == null || geometryResult == null) {
      skippedNoGapEvidence++;
      warnings.add(
        'AI 개구부 후보 $aiOpeningIndex(${_typeLabel(opening.openingType)}): 인접 벽 후보 ${candidates.length}개 '
        '(${candidates.map((c) => c.wall.id).join(', ')}) 모두에서 실제 pixel gap 근거를 찾지 못해 '
        '반영하지 않습니다 — 지어내지 않습니다.',
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
    final snapIsClose = matchedDistancePx <= maxSnapDistancePx * 0.5;

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
        // CANONICAL 2D CONFIRMATION WO §2 — 이건 순수 CV 검출이 아니라
        // AI semantic 힌트를 pixel로 재검증한 결과다. `analyzed`(순수
        // CV)와 구분해 "이것도 여전히 초안/제안일 뿐"임을 명확히 한다.
        source: CadElementSource.aiSuggested,
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

/// 정규화 좌표 두 점 사이의 실제 픽셀 거리(anisotropic 보정 포함).
double _distancePx(CadFloorPlan plan, NormalizedPoint a, NormalizedPoint b) {
  final w = plan.sourceWidthPx.toDouble();
  final h = plan.sourceHeightPx.toDouble();
  final dx = (a.x - b.x) * w, dy = (a.y - b.y) * h;
  return math.sqrt(dx * dx + dy * dy);
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

/// [point](정규화 좌표)에서 [maxDistancePx] 이내에 있는 [plan]의 벽을
/// 전부 찾아 가까운 순서로 정렬해 돌려준다(실제 픽셀 공간
/// point-to-segment 거리 기준). 코너 근처에서는 여러 벽이 비슷한
/// 거리에 있을 수 있으므로, 호출부가 이 목록을 순서대로 시도해 실제
/// gap이 있는 벽을 스스로 찾게 한다(§ 클래스 문서).
List<_NearestWallResult> _nearestWalls(CadFloorPlan plan, NormalizedPoint point, double maxDistancePx) {
  final w = plan.sourceWidthPx.toDouble();
  final h = plan.sourceHeightPx.toDouble();
  final px = point.x * w, py = point.y * h;

  final results = <_NearestWallResult>[];
  for (final wall in plan.walls) {
    final ax = wall.start.x * w, ay = wall.start.y * h;
    final bx = wall.end.x * w, by = wall.end.y * h;
    final dist = _pointToSegmentDistance(px, py, ax, ay, bx, by);
    if (dist <= maxDistancePx) {
      results.add(_NearestWallResult(wall, dist));
    }
  }
  results.sort((a, b) => a.distancePx.compareTo(b.distancePx));
  return results;
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
