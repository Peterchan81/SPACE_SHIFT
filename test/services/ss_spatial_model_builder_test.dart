// SSSpatialModelBuilder(evidence → 해석) 단위 테스트.
//
// PC2 재작업 WO — "닫힌 사각형을 찾는다"가 아니라 "사람이 사용/이동할
// 수 있는 건축 공간인가?"를 판단하는 해석 계층. 검증 항목:
//
// 1. 더 큰 공간 안에 완전히 둘러싸인 훨씬 작은 닫힌 영역(가구/설비
//    섬)은 공간이 아니라 SSObjectCandidate로 분류된다.
// 2. 작아도 스스로 출입 가능한(근처에 문/창이 있는) 닫힌 영역은
//    포함 관계만으로 가구/설비로 재분류되지 않는다.
// 3. 두 공간이 내벽 하나를 공유하면 서로의 adjacentSpaceIds에 들어간다.
// 4. 문이 두 공간을 나누는 벽 위에 있으면 그 문의 connectsSpaceIds에
//    두 공간이 모두 들어간다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/services/ss_spatial_model_builder.dart';

FloorPlanAnalysisDebugStats _stats({int rooms = 0, int openings = 0}) =>
    FloorPlanAnalysisDebugStats(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      analysisWidthPx: 800,
      analysisHeightPx: 600,
      rawHorizontalRuns: 0,
      rawVerticalRuns: 0,
      mergedWallCount: 0,
      roomCandidateCount: rooms,
      openingCandidateCount: openings,
      durationMs: 1,
    );

void main() {
  const builder = SSSpatialModelBuilder();

  test('더 큰 공간 안에 완전히 둘러싸인 훨씬 작은 영역은 가구/설비 후보로 '
      '분류되고, 공간 목록에서는 제외된다', () {
    const outer = RoomCandidate(
      id: 'room-outer',
      polygon: [
        Point2(0.1, 0.1),
        Point2(0.9, 0.1),
        Point2(0.9, 0.9),
        Point2(0.1, 0.9),
      ],
      areaNormalized: 0.64,
      confidence: 0.8,
    );
    // outer 안에 완전히 들어있고 훨씬 작은 "가구" 후보(주변에 문 없음).
    const furniture = RoomCandidate(
      id: 'room-inner',
      polygon: [
        Point2(0.4, 0.4),
        Point2(0.5, 0.4),
        Point2(0.5, 0.5),
        Point2(0.4, 0.5),
      ],
      areaNormalized: 0.01,
      confidence: 0.7,
    );
    final result = FloorPlanAnalysisResult(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      walls: const [],
      openings: const [],
      rooms: const [outer, furniture],
      warnings: const [],
      debugStats: _stats(rooms: 2),
    );

    final model = builder.build(result);

    expect(model.spaces.map((s) => s.id), ['room-outer']);
    expect(model.objects, hasLength(1));
    expect(model.objects.single.kind, SSObjectKind.furnitureOrEquipment);
    expect(model.objects.single.containingSpaceId, 'room-outer');
    expect(model.warnings, contains(contains('가구/설비')));
  });

  test('포함되어 있어도 경계 근처에 문/창이 있으면 독립 공간으로 유지된다 '
      '(예: 작은 팬트리)', () {
    const outer = RoomCandidate(
      id: 'room-outer',
      polygon: [
        Point2(0.1, 0.1),
        Point2(0.9, 0.1),
        Point2(0.9, 0.9),
        Point2(0.1, 0.9),
      ],
      areaNormalized: 0.64,
      confidence: 0.8,
    );
    const pantry = RoomCandidate(
      id: 'room-pantry',
      polygon: [
        Point2(0.15, 0.15),
        Point2(0.25, 0.15),
        Point2(0.25, 0.25),
        Point2(0.15, 0.25),
      ],
      areaNormalized: 0.01,
      confidence: 0.7,
    );
    // pantry 경계(bounding box) 바로 위에 걸리는 문 후보.
    const door = OpeningCandidate(
      id: 'door-pantry',
      type: OpeningType.door,
      center: Point2(0.2, 0.15),
      widthNormalized: 0.03,
      confidence: 0.5,
    );
    final result = FloorPlanAnalysisResult(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      walls: const [],
      openings: const [door],
      rooms: const [outer, pantry],
      warnings: const [],
      debugStats: _stats(rooms: 2, openings: 1),
    );

    final model = builder.build(result);

    expect(
      model.spaces.map((s) => s.id).toSet(),
      {'room-outer', 'room-pantry'},
    );
    expect(model.objects, isEmpty);
  });

  test('내벽 하나를 공유하는 두 공간은 서로 adjacentSpaceIds에 등록되고, '
      '그 벽의 separatesSpaceIds에도 둘 다 들어간다', () {
    const roomA = RoomCandidate(
      id: 'room-a',
      polygon: [
        Point2(0.1, 0.1),
        Point2(0.5, 0.1),
        Point2(0.5, 0.9),
        Point2(0.1, 0.9),
      ],
      areaNormalized: 0.32,
      confidence: 0.8,
    );
    const roomB = RoomCandidate(
      id: 'room-b',
      polygon: [
        Point2(0.5, 0.1),
        Point2(0.9, 0.1),
        Point2(0.9, 0.9),
        Point2(0.5, 0.9),
      ],
      areaNormalized: 0.32,
      confidence: 0.8,
    );
    const sharedWall = WallSegment(
      id: 'wall-shared',
      start: Point2(0.5, 0.1),
      end: Point2(0.5, 0.9),
      thicknessNormalized: 0.01,
      confidence: 0.7,
    );
    final result = FloorPlanAnalysisResult(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      walls: const [sharedWall],
      openings: const [],
      rooms: const [roomA, roomB],
      warnings: const [],
      debugStats: _stats(rooms: 2),
    );

    final model = builder.build(result);

    final a = model.spaces.firstWhere((s) => s.id == 'room-a');
    final b = model.spaces.firstWhere((s) => s.id == 'room-b');
    expect(a.adjacentSpaceIds, contains('room-b'));
    expect(b.adjacentSpaceIds, contains('room-a'));

    final wall = model.walls.single;
    expect(wall.separatesSpaceIds.toSet(), {'room-a', 'room-b'});
  });

  test('두 공간을 나누는 벽 위의 문은 그 두 공간을 모두 connectsSpaceIds로 '
      '연결한다', () {
    const roomA = RoomCandidate(
      id: 'room-a',
      polygon: [
        Point2(0.1, 0.1),
        Point2(0.5, 0.1),
        Point2(0.5, 0.9),
        Point2(0.1, 0.9),
      ],
      areaNormalized: 0.32,
      confidence: 0.8,
    );
    const roomB = RoomCandidate(
      id: 'room-b',
      polygon: [
        Point2(0.5, 0.1),
        Point2(0.9, 0.1),
        Point2(0.9, 0.9),
        Point2(0.5, 0.9),
      ],
      areaNormalized: 0.32,
      confidence: 0.8,
    );
    const sharedWall = WallSegment(
      id: 'wall-shared',
      start: Point2(0.5, 0.1),
      end: Point2(0.5, 0.9),
      thicknessNormalized: 0.01,
      confidence: 0.7,
    );
    const door = OpeningCandidate(
      id: 'door-ab',
      type: OpeningType.door,
      center: Point2(0.5, 0.5),
      widthNormalized: 0.03,
      confidence: 0.5,
      wallId: 'wall-shared',
    );
    final result = FloorPlanAnalysisResult(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      walls: const [sharedWall],
      openings: const [door],
      rooms: const [roomA, roomB],
      warnings: const [],
      debugStats: _stats(rooms: 2, openings: 1),
    );

    final model = builder.build(result);

    final opening = model.openings.single;
    expect(opening.kind, SSOpeningKind.door);
    expect(opening.connectsSpaceIds.toSet(), {'room-a', 'room-b'});
  });

  test('가구/설비 후보가 없으면 경고 메시지를 추가하지 않는다', () {
    const outer = RoomCandidate(
      id: 'room-outer',
      polygon: [
        Point2(0.1, 0.1),
        Point2(0.9, 0.1),
        Point2(0.9, 0.9),
        Point2(0.1, 0.9),
      ],
      areaNormalized: 0.64,
      confidence: 0.8,
    );
    final result = FloorPlanAnalysisResult(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      walls: const [],
      openings: const [],
      rooms: const [outer],
      warnings: const [],
      debugStats: _stats(rooms: 1),
    );

    final model = builder.build(result);
    expect(model.warnings, isEmpty);
  });
}
