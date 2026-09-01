// CadFloorPlan/CadWall 모델과 buildCadFloorPlan 변환에 대한 단위 테스트.
//
// 1. 분석 결과(FloorPlanAnalysisResult)를 CAD geometry로 변환해도 좌표/
//    두께/신뢰도가 새로 만들어지지 않고 그대로 옮겨진다(WO 15번).
// 2. CadWall에는 사용자 작업 번호(number) 개념이 아예 없다 — geometry
//    id와 사용자 작업 번호는 타입 수준에서부터 분리되어 있다(WO 1/12번).
// 3. 벽 경계 폴리곤(boundaryPolygon)이 중심선 + 두께로 정확히 계산된다.
// 4. 축척(FloorPlanScale)이 없으면 실제 mm 값을 계산하지 않는다(WO 9번,
//    임의 추정 금지) — 있으면 픽셀 거리 기반으로 정확히 계산한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';

FloorPlanAnalysisResult _sampleAnalysisResult() {
  return const FloorPlanAnalysisResult(
    sourceWidthPx: 800,
    sourceHeightPx: 600,
    walls: [
      WallSegment(
        id: 'wall-0',
        start: Point2(0.1, 0.1),
        end: Point2(0.9, 0.1),
        thicknessNormalized: 0.02,
        confidence: 0.75,
        isExterior: true,
      ),
      WallSegment(
        id: 'wall-1',
        start: Point2(0.5, 0.1),
        end: Point2(0.5, 0.9),
        thicknessNormalized: 0.015,
        confidence: 0.6,
      ),
    ],
    openings: [
      OpeningCandidate(
        id: 'opening-0',
        type: OpeningType.door,
        center: Point2(0.5, 0.5),
        widthNormalized: 0.05,
        confidence: 0.4,
        wallId: 'wall-1',
      ),
    ],
    rooms: [
      RoomCandidate(
        id: 'room-0',
        polygon: [
          Point2(0.1, 0.1),
          Point2(0.5, 0.1),
          Point2(0.5, 0.9),
          Point2(0.1, 0.9),
        ],
        areaNormalized: 0.32,
        confidence: 0.8,
      ),
    ],
    warnings: [],
    debugStats: FloorPlanAnalysisDebugStats(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      analysisWidthPx: 800,
      analysisHeightPx: 600,
      rawHorizontalRuns: 1,
      rawVerticalRuns: 1,
      mergedWallCount: 2,
      roomCandidateCount: 1,
      openingCandidateCount: 1,
      durationMs: 5,
    ),
  );
}

void main() {
  test('buildCadFloorPlan은 분석 결과 좌표/두께/신뢰도를 그대로 옮긴다', () {
    final result = _sampleAnalysisResult();
    final cad = buildCadFloorPlan(result);

    expect(cad.sourceWidthPx, 800);
    expect(cad.sourceHeightPx, 600);
    expect(cad.walls, hasLength(2));

    final exteriorWall = cad.walls.firstWhere((w) => w.id == 'wall-0');
    expect(exteriorWall.wallType, CadWallType.exterior);
    expect(exteriorWall.start, const Point2(0.1, 0.1));
    expect(exteriorWall.end, const Point2(0.9, 0.1));
    expect(exteriorWall.thicknessNormalized, 0.02);
    expect(exteriorWall.confidence, 0.75);
    expect(exteriorWall.source, CadElementSource.analyzed);
    expect(exteriorWall.edited, isFalse);

    final interiorWall = cad.walls.firstWhere((w) => w.id == 'wall-1');
    expect(interiorWall.wallType, CadWallType.interior);

    expect(cad.openings, hasLength(1));
    expect(cad.rooms, hasLength(1));
  });

  test('CadWall에는 사용자 작업 번호 개념이 없다(geometry id와 완전히 분리)', () {
    final cad = buildCadFloorPlan(_sampleAnalysisResult());
    final wall = cad.walls.first;
    // CadWall이 담는 값은 id/geometry 정보뿐이며, 화면에 그리는 ①②③
    // 같은 "번호"는 이 모델에 전혀 존재하지 않는다 — 별도의
    // WorkspaceTaskItem.number가 사용자가 작업을 만들 때만 생긴다.
    expect(wall.id, isA<String>());
    expect(wall.id, isNot(matches(RegExp(r'^\d+$'))));
  });

  test('boundaryPolygon은 중심선을 두께의 절반만큼 수직으로 펼친 4점이다', () {
    const wall = CadWall(
      id: 'wall-h',
      start: Point2(0.2, 0.5),
      end: Point2(0.8, 0.5),
      thicknessNormalized: 0.1,
      wallType: CadWallType.exterior,
      confidence: 0.9,
    );

    final polygon = wall.boundaryPolygon;
    expect(polygon, hasLength(4));
    // 수평 벽이므로 두께는 y축 방향으로만(±0.05, 부동소수 오차 허용)
    // 펼쳐져야 한다.
    for (final p in polygon) {
      expect(p.y, closeTo(0.5, 0.0501));
      expect(p.y, isNot(0.5));
    }
  });

  test('축척이 없으면 실제 mm 값을 계산하지 않는다', () {
    final cad = buildCadFloorPlan(_sampleAnalysisResult());
    final mm = cad.realMmForNormalizedLength(0.5, null);
    expect(mm, isNull);
  });

  test('축척이 있으면 정규화 길이 × 대각선 픽셀 × mmPerPixel로 mm를 계산한다', () {
    final cad = buildCadFloorPlan(_sampleAnalysisResult());
    const scale = FloorPlanScale(
      mmPerPixel: 2.0,
      referenceStart: Point2(0, 0),
      referenceEnd: Point2(1, 0),
      referenceLengthMm: 1600,
    );

    final mm = cad.realMmForNormalizedLength(0.5, scale);
    final expectedDiagonal = cad.diagonalPx; // sqrt(800^2+600^2) = 1000
    expect(expectedDiagonal, closeTo(1000, 0.001));
    expect(mm, closeTo(0.5 * 1000 * 2.0, 0.001));
  });

  test('두 점의 실제 길이는 원본 이미지의 가로와 세로 픽셀 축을 각각 적용한다', () {
    final cad = buildCadFloorPlan(_sampleAnalysisResult());
    const scale = FloorPlanScale(
      mmPerPixel: 2.0,
      referenceStart: Point2(0, 0),
      referenceEnd: Point2(1, 0),
      referenceLengthMm: 1600,
    );

    expect(
      cad.realMmBetween(const Point2(0.1, 0.1), const Point2(0.9, 0.1), scale),
      closeTo(1280, 0.001),
    );
    expect(
      cad.realMmBetween(const Point2(0.5, 0.1), const Point2(0.5, 0.9), scale),
      closeTo(960, 0.001),
    );
  });

  test('CeilingHeightSettings는 room override가 없으면 기본값을 쓴다', () {
    const settings = CeilingHeightSettings(defaultHeightMm: 2400);
    expect(settings.heightForRoom('room-0'), 2400);
  });

  test('CeilingHeightSettings는 room override가 있으면 그 값을 우선한다', () {
    const settings = CeilingHeightSettings(
      defaultHeightMm: 2400,
      perRoomOverridesMm: {'room-0': 2700},
    );
    expect(settings.heightForRoom('room-0'), 2700);
    expect(settings.heightForRoom('room-1'), 2400);
  });
}
