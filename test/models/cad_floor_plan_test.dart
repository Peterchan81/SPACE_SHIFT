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

  group('2D 단순화 WO — 자동 축척(ScaleSource/estimateScaleFromDoors)', () {
    test('A(대조군) — 사용자가 직접 입력한 실측값은 source가 measured다', () {
      const scale = FloorPlanScale(
        mmPerPixel: 2.0,
        referenceStart: Point2(0, 0),
        referenceEnd: Point2(1, 0),
        referenceLengthMm: 1600,
      );
      expect(scale.source, ScaleSource.measured);
      expect(scale.source.isReliable, isTrue);
    });

    test('B — 문 후보가 있으면 표준 문 폭(kAssumedDoorWidthMm)으로 역산해 '
        'estimatedFromDoor로 표시한다(정확한 값처럼 위장하지 않는다)', () {
      final cad = buildCadFloorPlan(_sampleAnalysisResult());
      final estimated = estimateScaleFromDoors(cad);

      expect(estimated, isNotNull);
      expect(estimated!.source, ScaleSource.estimatedFromDoor);
      expect(estimated.source.isReliable, isFalse);

      // 대각선 1000px(sqrt(800^2+600^2)) × widthNormalized 0.05 = 50px
      // → mmPerPixel = 900 / 50 = 18.
      final widthPx = 0.05 * cad.diagonalPx;
      expect(
        estimated.mmPerPixel,
        closeTo(kAssumedDoorWidthMm / widthPx, 1e-9),
      );
    });

    test('B — 문 후보가 여러 개면 각 문에서 독립적으로 역산한 mmPerPixel의 '
        '중앙값을 쓴다(평균이 아니라 중앙값 — 잘못 검출된 극단값 하나가 '
        '전체를 왜곡하지 않게)', () {
      // 3개 문 gap(정규화 폭)이 각각 이런 mmPerPixel을 암시한다:
      // door-a: widthPx=20 → 900/20=45, door-b: widthPx=45 → 20,
      // door-c: widthPx=90 → 10. 중앙값은 door-b의 20이어야 한다.
      const result = FloorPlanAnalysisResult(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: [],
        openings: [
          OpeningCandidate(
            id: 'door-a',
            type: OpeningType.door,
            center: Point2(0.1, 0.1),
            widthNormalized: 0.02, // widthPx = 0.02*1000 = 20
            confidence: 0.5,
          ),
          OpeningCandidate(
            id: 'door-b',
            type: OpeningType.door,
            center: Point2(0.5, 0.5),
            widthNormalized: 0.045, // widthPx = 45
            confidence: 0.5,
          ),
          OpeningCandidate(
            id: 'door-c',
            type: OpeningType.door,
            center: Point2(0.9, 0.9),
            widthNormalized: 0.09, // widthPx = 90
            confidence: 0.5,
          ),
        ],
        rooms: [],
        warnings: [],
        debugStats: FloorPlanAnalysisDebugStats(
          sourceWidthPx: 800,
          sourceHeightPx: 600,
          analysisWidthPx: 800,
          analysisHeightPx: 600,
          rawHorizontalRuns: 0,
          rawVerticalRuns: 0,
          mergedWallCount: 0,
          roomCandidateCount: 0,
          openingCandidateCount: 3,
          durationMs: 1,
        ),
      );
      final cad = buildCadFloorPlan(result);
      final estimated = estimateScaleFromDoors(cad);

      expect(estimated, isNotNull);
      expect(estimated!.referenceStart, const Point2(0.5, 0.5)); // door-b.
      expect(estimated.mmPerPixel, closeTo(20, 1e-9));
    });

    test('C — 문 후보가 없으면 estimateScaleFromDoors는 null(거짓 값을 만들지 않는다)', () {
      const result = FloorPlanAnalysisResult(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: [],
        openings: [],
        rooms: [],
        warnings: [],
        debugStats: FloorPlanAnalysisDebugStats(
          sourceWidthPx: 800,
          sourceHeightPx: 600,
          analysisWidthPx: 800,
          analysisHeightPx: 600,
          rawHorizontalRuns: 0,
          rawVerticalRuns: 0,
          mergedWallCount: 0,
          roomCandidateCount: 0,
          openingCandidateCount: 0,
          durationMs: 1,
        ),
      );
      final cad = buildCadFloorPlan(result);
      expect(estimateScaleFromDoors(cad), isNull);
    });

    test('C — 문도 없을 때 unknownFallbackScale은 source=unknown인 임시 '
        '기준을 만들어 3D 생성 자체는 막지 않는다', () {
      final cad = buildCadFloorPlan(_sampleAnalysisResult().copyWithWalls([]));
      final fallback = unknownFallbackScale(cad);
      expect(fallback.source, ScaleSource.unknown);
      expect(fallback.source.isReliable, isFalse);
      expect(fallback.mmPerPixel, greaterThan(0));
    });

    test('resolveAutoScale — 이미 축척이 있으면(사용자가 직접 보정) 절대 덮어쓰지 않는다', () {
      final cad = buildCadFloorPlan(_sampleAnalysisResult());
      const existing = FloorPlanScale(
        mmPerPixel: 5.0,
        referenceStart: Point2(0, 0),
        referenceEnd: Point2(1, 0),
        referenceLengthMm: 4000,
      );

      final resolved = resolveAutoScale(cad, existing);
      expect(identical(resolved, existing), isTrue);
    });

    test('resolveAutoScale — 축척이 없으면 문 기준 추정을 우선 적용한다', () {
      final cad = buildCadFloorPlan(_sampleAnalysisResult());
      final resolved = resolveAutoScale(cad, null);
      expect(resolved.source, ScaleSource.estimatedFromDoor);
    });

    test('resolveAutoScale — 문도 없으면 unknown 폴백을 적용해 3D 생성을 막지 않는다', () {
      const noOpeningsResult = FloorPlanAnalysisResult(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: [],
        openings: [],
        rooms: [],
        warnings: [],
        debugStats: FloorPlanAnalysisDebugStats(
          sourceWidthPx: 800,
          sourceHeightPx: 600,
          analysisWidthPx: 800,
          analysisHeightPx: 600,
          rawHorizontalRuns: 0,
          rawVerticalRuns: 0,
          mergedWallCount: 0,
          roomCandidateCount: 0,
          openingCandidateCount: 0,
          durationMs: 1,
        ),
      );
      final cad = buildCadFloorPlan(noOpeningsResult);
      final resolved = resolveAutoScale(cad, null);
      expect(resolved.source, ScaleSource.unknown);
    });
  });

  group('2D 정확도 개선 WO — 공간별 ㎡/평/전체 합계/이름', () {
    // 800x600 이미지, room-0 polygon은 (0.1,0.1)~(0.5,0.9) — 정규화
    // 면적 0.32(=areaNormalized), 실제 이미지 면적 480000px².
    const scale = FloorPlanScale(
      mmPerPixel: 2.0,
      referenceStart: Point2(0, 0),
      referenceEnd: Point2(1, 0),
      referenceLengthMm: 1600,
    );

    test('A — roomAreaM2는 정규화 면적×이미지 픽셀 면적×mmPerPixel²로 계산한다', () {
      final cad = buildCadFloorPlan(_sampleAnalysisResult());
      final room = cad.rooms.first;

      final m2 = roomAreaM2(cad, room, scale);
      // areaPx2 = 0.32 * 800 * 600 = 153600. mm2 = 153600 * 2^2 = 614400.
      // m2 = 614400 / 1e6 = 0.6144.
      expect(m2, closeTo(0.6144, 1e-9));
    });

    test('A — scale이 없으면 roomAreaM2는 null(임의 mm 추정 금지)', () {
      final cad = buildCadFloorPlan(_sampleAnalysisResult());
      final room = cad.rooms.first;
      expect(roomAreaM2(cad, room, null), isNull);
    });

    test('B — squareMetersToPyeong은 3.305785로 나눈 값이다', () {
      expect(squareMetersToPyeong(3.305785), closeTo(1.0, 1e-9));
      expect(squareMetersToPyeong(33.05785), closeTo(10.0, 1e-9));
      expect(squareMetersToPyeong(0), 0);
    });

    test('C — totalAreaM2는 모든 공간의 roomAreaM2 합이다', () {
      const twoRoomsResult = FloorPlanAnalysisResult(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: [],
        openings: [],
        rooms: [
          RoomCandidate(
            id: 'room-a',
            polygon: [
              Point2(0, 0),
              Point2(0.5, 0),
              Point2(0.5, 0.5),
              Point2(0, 0.5),
            ],
            areaNormalized: 0.1,
            confidence: 0.7,
          ),
          RoomCandidate(
            id: 'room-b',
            polygon: [
              Point2(0.5, 0.5),
              Point2(1, 0.5),
              Point2(1, 1),
              Point2(0.5, 1),
            ],
            areaNormalized: 0.2,
            confidence: 0.7,
          ),
        ],
        warnings: [],
        debugStats: FloorPlanAnalysisDebugStats(
          sourceWidthPx: 800,
          sourceHeightPx: 600,
          analysisWidthPx: 800,
          analysisHeightPx: 600,
          rawHorizontalRuns: 0,
          rawVerticalRuns: 0,
          mergedWallCount: 0,
          roomCandidateCount: 2,
          openingCandidateCount: 0,
          durationMs: 1,
        ),
      );
      final cad = buildCadFloorPlan(twoRoomsResult);
      final total = totalAreaM2(cad, scale);
      final a = roomAreaM2(cad, cad.rooms[0], scale)!;
      final b = roomAreaM2(cad, cad.rooms[1], scale)!;
      expect(total, closeTo(a + b, 1e-9));
    });

    test('C — 공간이 없으면 totalAreaM2는 null', () {
      const empty = FloorPlanAnalysisResult(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: [],
        openings: [],
        rooms: [],
        warnings: [],
        debugStats: FloorPlanAnalysisDebugStats(
          sourceWidthPx: 800,
          sourceHeightPx: 600,
          analysisWidthPx: 800,
          analysisHeightPx: 600,
          rawHorizontalRuns: 0,
          rawVerticalRuns: 0,
          mergedWallCount: 0,
          roomCandidateCount: 0,
          openingCandidateCount: 0,
          durationMs: 1,
        ),
      );
      expect(totalAreaM2(buildCadFloorPlan(empty), scale), isNull);
    });

    test('거짓 이름 단정 금지 — name이 없으면 "공간 N"(1부터)으로 표시한다', () {
      final cad = buildCadFloorPlan(_sampleAnalysisResult());
      final room = cad.rooms.first;
      expect(room.name, isNull);
      expect(displayRoomName(room, 0), '공간 1');
      expect(displayRoomName(room, 3), '공간 4');
    });

    test('withName()으로 실제 이름을 지으면 그 이름이 표시된다', () {
      final cad = buildCadFloorPlan(_sampleAnalysisResult());
      final renamed = cad.rooms.first.withName('거실');
      expect(displayRoomName(renamed, 0), '거실');
    });

    test('withName(null) 또는 빈 이름이면 다시 자동 이름("공간 N")으로 돌아간다', () {
      final cad = buildCadFloorPlan(_sampleAnalysisResult());
      final renamed = cad.rooms.first.withName('거실').withName(null);
      expect(renamed.name, isNull);
      expect(displayRoomName(renamed, 0), '공간 1');
    });
  });
}
