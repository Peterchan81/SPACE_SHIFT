// SPACE SHIFT — WO088-1 IMAGE 2 COORDINATE-BASED 2D STRUCTURE POC.
//
// §0/§1 — 이 모듈은 CAD/FloorDomain을 "고치는" 것이 아니라, 그것들과
// 완전히 분리된 별도 실험 경로다. WallSystem/PlanarGraph/FloorDomain/
// CadFloorPlan을 전혀 import하지 않는다 — FloorDomain이 INVALID여도
// 이 모델은 그대로 만들어져야 한다(§8). 대신 pixel_wall_extractor.dart의
// "1단계"(순수 pixel/room/opening 검출, topology 이전) evidence만
// 재사용한다 — CAD topology를 가져오는 것이 아니라 그 이전 evidence를
// 가져온다는 것이 핵심 구분이다.
//
// 좌표는 [Point2](floor_plan_geometry.dart, 이미 프로젝트 전체가 쓰는
// [0,1] 정규화 좌표)를 그대로 재사용한다 — 새 좌표 타입을 중복
// 발명하지 않는다(§5 "이에 준하는 안정적인 모델"). 이미지 해상도가
// 바뀌어도 이 값 자체는 절대 안 바뀐다(픽셀로 변환하는 시점에만 w/h를
// 곱한다).

import 'dart:math' as math;

import '../../models/floor_plan_geometry.dart';
import '../pixel_wall_v4/gpt_semantic_schema.dart';
import '../pixel_wall_v4/pixel_wall_classifier.dart';
import '../pixel_wall_v4/pixel_wall_extractor.dart';
import '../pixel_wall_v4/pixel_wall_types.dart';

enum CoordEvidenceSource {
  /// pixel_wall_extractor.dart가 직접 검출한 벽 candidate.
  pixelWall,

  /// flood-fill로 찾은 방/영역 후보.
  pixelRoom,

  /// 벽 gap 폭 기반 문/창 후보(옛 opening 스캔 — geometry 근거).
  pixelOpening,

  /// GPT 의미 ROI와 겹쳐 doorArc/windowDetail로 분류된 candidate(pixel_wall_classifier.dart,
  /// WallSystem/PlanarGraph 없이도 계산 가능한 pre-topology 근거) — 이미
  /// 캡처된 fixture만 재사용하고 새 GPT 호출은 하지 않는다(§12).
  semanticHint,

  /// 사용자가 직접 수정(이동/삭제/추가)한 값 — §9 "AI 결과를 정답으로
  /// 고정하지 않는다"의 핵심 상태.
  userEdited,
}

/// §5 필수 구조요소 중 Corner/Vertex — 여기서는 wall segment 끝점을
/// 단순히 근접 거리로 묶어 "화면에 표시하고 스냅할 대상"으로만 쓴다.
/// PlanarGraph의 canonical vertex(위상 판단 근거)와 다르다 — 이 corner는
/// 아무 위상적 주장도 하지 않는다(§8 CAD topology 가져오지 않음).
class CoordCorner {
  const CoordCorner({required this.id, required this.point, required this.wallIds});
  final String id;
  final Point2 point;

  /// 이 corner 근처에 끝점이 있는 wall segment id들(표시/디버그용).
  final List<String> wallIds;
}

class CoordWallSegment {
  const CoordWallSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.thicknessNormalized,
    required this.isExterior,
    required this.confidence,
    required this.reviewNeeded,
    required this.source,
    this.reviewReasons = const [],
  });

  final String id;
  final Point2 start;
  final Point2 end;
  final double thicknessNormalized;
  final bool isExterior;
  final double confidence;
  final bool reviewNeeded;
  final CoordEvidenceSource source;

  /// §8 WO088-2 — 왜 reviewNeeded인지(예: furniture/fixture region과
  /// 겹침) 사람이 읽을 수 있는 근거. 비어 있을 수 있다(reviewNeeded=true
  /// 여도 근거 문자열이 항상 있는 건 아니다 — 기존 WO088-1 reviewNeeded
  /// 경로는 이 필드를 채우지 않는다).
  final List<String> reviewReasons;

  CoordWallSegment copyWith({
    Point2? start,
    Point2? end,
    bool? reviewNeeded,
    CoordEvidenceSource? source,
    List<String>? reviewReasons,
  }) => CoordWallSegment(
    id: id,
    start: start ?? this.start,
    end: end ?? this.end,
    thicknessNormalized: thicknessNormalized,
    isExterior: isExterior,
    confidence: confidence,
    reviewNeeded: reviewNeeded ?? this.reviewNeeded,
    source: source ?? this.source,
    reviewReasons: reviewReasons ?? this.reviewReasons,
  );
}

enum CoordOpeningKind { door, window, unknown }

class CoordOpening {
  const CoordOpening({
    required this.id,
    required this.center,
    required this.widthNormalized,
    required this.kind,
    required this.confidence,
    required this.reviewNeeded,
    required this.source,
  });

  final String id;
  final Point2 center;
  final double widthNormalized;
  final CoordOpeningKind kind;
  final double confidence;
  final bool reviewNeeded;
  final CoordEvidenceSource source;

  CoordOpening copyWith({Point2? center}) => CoordOpening(
    id: id,
    center: center ?? this.center,
    widthNormalized: widthNormalized,
    kind: kind,
    confidence: confidence,
    reviewNeeded: reviewNeeded,
    source: source,
  );
}

/// §5 RoomBoundary/Region — flood-fill이 실제로 찾은 영역 그대로다.
/// 벽으로 완전히 닫혔다는 위상적 보장이 없다(FloorDomain의 역할이
/// 아니다) — 참고용 표시일 뿐이다.
class CoordRegion {
  const CoordRegion({required this.id, required this.polygon, required this.areaNormalized, required this.confidence});
  final String id;
  final List<Point2> polygon;
  final double areaNormalized;
  final double confidence;
}

class CoordStructureModel {
  const CoordStructureModel({required this.walls, required this.openings, required this.regions, required this.corners});

  final List<CoordWallSegment> walls;
  final List<CoordOpening> openings;
  final List<CoordRegion> regions;

  /// wall 끝점에서 파생된 표시/스냅 전용 목록 — [walls]가 바뀌면 항상
  /// [recomputeCorners]로 다시 계산해야 한다(별도로 편집되지 않는다).
  final List<CoordCorner> corners;

  CoordStructureModel copyWithWalls(List<CoordWallSegment> newWalls) =>
      CoordStructureModel(walls: newWalls, openings: openings, regions: regions, corners: deriveCorners(newWalls));

  CoordStructureModel copyWithOpenings(List<CoordOpening> newOpenings) =>
      CoordStructureModel(walls: walls, openings: newOpenings, regions: regions, corners: corners);
}

double _pointDistance(Point2 a, Point2 b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// §7 corner 근접 판정 허용 오차(정규화 좌표 기준) — 화면 zoom/이미지
/// 해상도와 무관하게 항상 같은 상대적 근접도를 뜻한다.
const double kCornerSnapToleranceNormalized = 0.01;

/// wall segment 끝점들을 가까운 것끼리 묶어 corner 목록을 만든다. 이건
/// PlanarGraph의 canonical vertex 병합과 겉보기엔 비슷하지만 목적이
/// 다르다 — 여기서는 "위상을 판단"하지 않고 순수히 "화면에 점 하나로
/// 보여주고 스냅할 대상"만 만든다(§8 CAD topology를 가져오지 않는다).
List<CoordCorner> deriveCorners(List<CoordWallSegment> walls) {
  final endpoints = <(Point2 point, String wallId)>[
    for (final w in walls) (w.start, w.id),
    for (final w in walls) (w.end, w.id),
  ];
  final used = List<bool>.filled(endpoints.length, false);
  final corners = <CoordCorner>[];
  var index = 0;
  for (var i = 0; i < endpoints.length; i++) {
    if (used[i]) continue;
    final (anchor, firstWallId) = endpoints[i];
    used[i] = true;
    final wallIds = <String>{firstWallId};
    var sumX = anchor.x, sumY = anchor.y, count = 1;
    for (var j = i + 1; j < endpoints.length; j++) {
      if (used[j]) continue;
      final (p, wallId) = endpoints[j];
      if (_pointDistance(anchor, p) <= kCornerSnapToleranceNormalized) {
        used[j] = true;
        wallIds.add(wallId);
        sumX += p.x;
        sumY += p.y;
        count++;
      }
    }
    corners.add(CoordCorner(id: 'corner-${index++}', point: Point2(sumX / count, sumY / count), wallIds: wallIds.toList()));
  }
  return corners;
}

/// §6/§7 OVERLAY TRANSFORM — 정규화 좌표를 화면(캔버스) 픽셀로 옮긴다.
/// zoom/화면 크기가 바뀌어도 [canvasWidth]/[canvasHeight]만 바뀔 뿐 이
/// 함수의 상대적 결과(비율)는 항상 같다 — 내부 정규화 좌표 자체는 절대
/// 변형되지 않는다.
({double x, double y}) toCanvasPoint(Point2 normalized, {required double canvasWidth, required double canvasHeight}) =>
    (x: normalized.x * canvasWidth, y: normalized.y * canvasHeight);

/// §7 좌표판(Grid) — 정규화 좌표계 위에 등간격 격자선을 만든다.
/// [stepNormalized]는 화면 zoom과 무관한 고정 간격이다(예: 0.1 =
/// 세로/가로를 10등분).
List<double> gridLines({double stepNormalized = 0.1}) {
  final count = (1.0 / stepNormalized).round();
  return [for (var i = 0; i <= count; i++) i == count ? 1.0 : i * stepNormalized];
}

/// §8 WO088-2 — 가구/설비 아이콘 오탐을 pixel threshold 재튜닝이 아니라
/// semantic evidence(이미 캡처된 GPT furnitureRegions/ambiguousRegions)로
/// 처리하는 방향을 검증한다. wall의 중점이 그런 영역 안에 있으면
/// reviewNeeded를 켜고 사람이 읽을 수 있는 근거를 남긴다 — 절대
/// 자동으로 삭제/제외하지 않는다(실제 구조벽과 겹칠 수 있으므로 최종
/// 판단은 사람 또는 향후 정밀 evidence에 맡긴다).
bool _pointInApproxRegion(Point2 p, GptApproxRegion r) {
  final minX = math.min(r.x0, r.x1);
  final maxX = math.max(r.x0, r.x1);
  final minY = math.min(r.y0, r.y1);
  final maxY = math.max(r.y0, r.y1);
  return p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY;
}

List<CoordWallSegment> flagInterferenceEvidence(List<CoordWallSegment> walls, GptSemanticResponse? semantic) {
  if (semantic == null) return walls;
  if (semantic.furnitureRegions.isEmpty && semantic.ambiguousRegions.isEmpty) return walls;

  return [
    for (final w in walls)
      () {
        final mid = Point2((w.start.x + w.end.x) / 2, (w.start.y + w.end.y) / 2);
        final reasons = <String>[
          for (final f in semantic.furnitureRegions)
            if (_pointInApproxRegion(mid, f.approxRegion)) 'possibleFurnitureInterference: ${f.note}',
          // ambiguousRegions는 GPT 스키마상 "가구/설비"로 좁혀 태깅된
          // 영역이 아니라 "구조가 불명확함" 일반 힌트다(gpt_semantic_schema.dart
          // 참고) — WO가 예시로 든 possibleFixtureInterference라는 이름을
          // 실제로 없는 별도 fixtureRegions 필드가 있는 것처럼 잘못
          // 붙이지 않는다. 실제 스키마 의미 그대로 정직하게 남긴다.
          for (final a in semantic.ambiguousRegions)
            if (_pointInApproxRegion(mid, a.approxRegion)) 'possibleAmbiguousRegionInterference: ${a.note}',
        ];
        if (reasons.isEmpty) return w;
        return w.copyWith(reviewNeeded: true, reviewReasons: [...w.reviewReasons, ...reasons]);
      }(),
  ];
}

/// noiseCategory가 확실히 "벽이 아님"으로 분류된 candidate만 제외한다
/// (pixel_wall_pipeline.dart의 `_isConfirmedNonWall`과 같은 기준 재사용 —
/// 중복 로직 발명 금지). trueStructural/unknown은 근거가 불확실할 뿐
/// 배제하지 않는다.
bool _isConfirmedNonWall(PixelWallCandidate c) {
  return c.noiseCategory == PixelWallNoiseCategory.text ||
      c.noiseCategory == PixelWallNoiseCategory.furniture ||
      c.noiseCategory == PixelWallNoiseCategory.fixture ||
      c.noiseCategory == PixelWallNoiseCategory.doorArc ||
      c.noiseCategory == PixelWallNoiseCategory.windowDetail;
}

/// §8 — pixel_wall_extractor.dart의 1단계 evidence(candidates/openings/
/// rooms)만 가져온다. WallSystem/PlanarGraph/FloorDomain은 전혀 쓰지
/// 않는다 — 이 함수 안 어디에도 그 모듈들을 import하지 않는다는 것
/// 자체가 분리의 증거다. structural/reviewNeeded 후보를 전부 포함한다
/// (조용히 삭제하지 않는다 — 이 프로젝트 전체의 관례와 동일).
///
/// [semantic]을 넘기면(§12 — 새 GPT 호출이 아니라 이미 캡처된 fixture만)
/// pixel_wall_classifier.dart의 순수 candidate-level 분류(WallSystem/
/// PlanarGraph 의존 없음)를 재사용해 텍스트/가구/설비로 확정된 candidate를
/// wall 목록에서 제외하고, doorArc/windowDetail로 확정된 candidate는
/// semanticHint 근거를 가진 opening으로 옮긴다 — 실측 결과 이 단계 없이는
/// 가구 아이콘 선이 벽처럼 그대로 남는 오탐이 실제로 확인됐다.
CoordStructureModel buildCoordStructureFromExtraction(
  PixelWallExtractionResult extraction, {
  GptSemanticResponse? semantic,
}) {
  var classified = classifyNoiseCategories(candidates: extraction.candidates, semantic: semantic);
  classified = applyTextHeuristic(candidates: classified, analysisWidthPx: extraction.analysisWidthPx, analysisHeightPx: extraction.analysisHeightPx);

  var walls = [
    for (final c in classified)
      if (!_isConfirmedNonWall(c))
        CoordWallSegment(
          id: c.id,
          start: c.start,
          end: c.end,
          thicknessNormalized: c.thicknessNormalized,
          isExterior: c.isExterior,
          confidence: c.baseConfidence,
          reviewNeeded: c.category == PixelWallCategory.reviewNeeded,
          source: CoordEvidenceSource.pixelWall,
        ),
  ];
  walls = flagInterferenceEvidence(walls, semantic);

  final semanticHintOpenings = [
    for (final c in classified)
      if (c.noiseCategory == PixelWallNoiseCategory.doorArc || c.noiseCategory == PixelWallNoiseCategory.windowDetail)
        CoordOpening(
          id: 'coord-opening-hint-${c.id}',
          center: Point2((c.start.x + c.end.x) / 2, (c.start.y + c.end.y) / 2),
          widthNormalized: c.lengthNormalized,
          kind: c.noiseCategory == PixelWallNoiseCategory.doorArc ? CoordOpeningKind.door : CoordOpeningKind.window,
          confidence: c.baseConfidence,
          reviewNeeded: false,
          source: CoordEvidenceSource.semanticHint,
        ),
  ];

  final openings = [
    ...semanticHintOpenings,
    for (var i = 0; i < extraction.openings.length; i++)
      CoordOpening(
        id: 'coord-opening-$i',
        center: extraction.openings[i].center,
        widthNormalized: extraction.openings[i].widthNormalized,
        kind: switch (extraction.openings[i].type) {
          OpeningType.door => CoordOpeningKind.door,
          OpeningType.window => CoordOpeningKind.window,
          OpeningType.unknown => CoordOpeningKind.unknown,
        },
        confidence: extraction.openings[i].confidence,
        reviewNeeded: true,
        source: CoordEvidenceSource.pixelOpening,
      ),
  ];

  final regions = [
    for (final r in extraction.rooms)
      CoordRegion(id: r.id, polygon: r.polygon, areaNormalized: r.areaNormalized, confidence: r.confidence),
  ];

  return CoordStructureModel(walls: walls, openings: openings, regions: regions, corners: deriveCorners(walls));
}
