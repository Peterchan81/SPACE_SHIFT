// SPACE SHIFT — WO099 3D ISO INTERIOR WORKSPACE FOUNDATION (Phase A).
//
// 이 파일은 space_scene_builder_v2.dart에 새로 추가된 두 가지를 검증한다:
// 1. §6 벽 top면(단면)이 옆면과 다른(살짝 어두운) 색을 쓴다.
// 2. §8 Phase A 최소 가구(sofa/table/bed)가 방 면적 순위로 배치되고,
//    각각 안정적인 identity(objectId/roomId/sourceKind)를 가진다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/space_scene_v2.dart';
import 'package:ason_space/services/space_scene_builder_v2.dart';

const _scale = FloorPlanScale(
  mmPerPixel: 5.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 5000,
  source: ScaleSource.measured,
);

CadWall _wall(String id, Point2 start, Point2 end, {bool exterior = true}) => CadWall(
  id: id,
  start: start,
  end: end,
  thicknessNormalized: 0.02,
  wallType: exterior ? CadWallType.exterior : CadWallType.interior,
  confidence: 0.9,
);

/// 정사각형 방 하나짜리 최소 평면도 — 1000px * 5mm/px * 0.8 = 4000mm
/// 정사각형 방(가구가 넉넉히 들어갈 크기).
CadFloorPlan _squareRoomPlan(String roomId) {
  const corners = [
    Point2(0.1, 0.1),
    Point2(0.9, 0.1),
    Point2(0.9, 0.9),
    Point2(0.1, 0.9),
  ];
  return CadFloorPlan(
    sourceWidthPx: 1000,
    sourceHeightPx: 1000,
    walls: [
      _wall('n', const Point2(0.1, 0.1), const Point2(0.9, 0.1)),
      _wall('s', const Point2(0.1, 0.9), const Point2(0.9, 0.9)),
      _wall('w', const Point2(0.1, 0.1), const Point2(0.1, 0.9)),
      _wall('e', const Point2(0.9, 0.1), const Point2(0.9, 0.9)),
    ],
    openings: const [],
    rooms: [CadRoom(id: roomId, polygon: corners, areaNormalized: 0.64, confidence: 0.9)],
    warnings: const [],
  );
}

void main() {
  group('WO099 §6 — 벽 top면 색이 옆면과 다르다', () {
    test('벽 mesh의 top face triangle 색이 side face 색보다 어둡다', () {
      final scene = buildSpaceSceneV2(
        plan: _squareRoomPlan('room-0'),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      final wall = scene.wallMeshes.first;
      // top면: 모든 정점의 y가 heightMm(2400)인 두 triangle.
      final topTriangles = wall.triangles.where(
        (t) => t.a.y == 2400 && t.b.y == 2400 && t.c.y == 2400,
      );
      // side면: 정점 중 하나 이상이 y=0(바닥)인 triangle.
      final sideTriangles = wall.triangles.where(
        (t) => t.a.y == 0 || t.b.y == 0 || t.c.y == 0,
      );
      expect(topTriangles, isNotEmpty);
      expect(sideTriangles, isNotEmpty);
      final topColor = topTriangles.first.color;
      final sideColor = sideTriangles.first.color;
      expect(topColor, isNot(sideColor), reason: '단면(top)은 옆면보다 살짝 어두운 별도 색이어야 한다(§6).');
      // "살짝 어둡게"이지 완전히 다른 색(예: 사고로 검정)이 아니어야 한다.
      expect(topColor.r, lessThanOrEqualTo(sideColor.r));
      expect(topColor.g, lessThanOrEqualTo(sideColor.g));
      expect(topColor.b, lessThanOrEqualTo(sideColor.b));
    });
  });

  group('WO099 §8 — Phase A 최소 가구 3종', () {
    test('방이 1개뿐이면 sofa/table/bed 3개 모두 그 방에 배치된다', () {
      final scene = buildSpaceSceneV2(
        plan: _squareRoomPlan('room-0'),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      expect(scene.furnitureMeshes, hasLength(3));
      expect(
        scene.furnitureMeshes.map((f) => f.furnitureType).toSet(),
        {SpaceFurnitureType.sofa, SpaceFurnitureType.table, SpaceFurnitureType.bed},
      );
      for (final f in scene.furnitureMeshes) {
        expect(f.roomId, 'room-0', reason: '방이 하나뿐이면 그 방에 배치돼야 한다.');
        expect(f.identity.sourceKind, SpaceElementKindV2.furniture);
        expect(f.identity.roomId, 'room-0');
        expect(f.triangles, isNotEmpty);
      }
      // 서로 다른 안정적 objectId(§9/§10 "stable object identity").
      final ids = scene.furnitureMeshes.map((f) => f.identity.objectId).toSet();
      expect(ids, hasLength(3));
    });

    test('방이 여러 개면 가장 넓은 방에 sofa+table, 그다음으로 넓은 방에 bed가 배치된다', () {
      // 큰 방(room-big, 0.05~0.55 => 정규화폭 0.5)과 작은 방(room-small,
      // 0.6~0.9 => 정규화폭 0.3)을 나란히 둔다 — sourceWidthPx=2000이라
      // 실제 mm로도 큰 방이 확실히 더 넓다.
      final plan = CadFloorPlan(
        sourceWidthPx: 2000,
        sourceHeightPx: 1000,
        walls: [
          _wall('n1', const Point2(0.05, 0.1), const Point2(0.55, 0.1)),
          _wall('s1', const Point2(0.05, 0.9), const Point2(0.55, 0.9)),
          _wall('w1', const Point2(0.05, 0.1), const Point2(0.05, 0.9)),
          _wall('mid', const Point2(0.55, 0.1), const Point2(0.55, 0.9), exterior: false),
          _wall('n2', const Point2(0.6, 0.1), const Point2(0.9, 0.1)),
          _wall('s2', const Point2(0.6, 0.9), const Point2(0.9, 0.9)),
          _wall('e2', const Point2(0.9, 0.1), const Point2(0.9, 0.9)),
        ],
        openings: const [],
        rooms: const [
          CadRoom(
            id: 'room-big',
            polygon: [
              Point2(0.05, 0.1),
              Point2(0.55, 0.1),
              Point2(0.55, 0.9),
              Point2(0.05, 0.9),
            ],
            areaNormalized: 0.4,
            confidence: 0.9,
          ),
          CadRoom(
            id: 'room-small',
            polygon: [
              Point2(0.6, 0.1),
              Point2(0.9, 0.1),
              Point2(0.9, 0.9),
              Point2(0.6, 0.9),
            ],
            areaNormalized: 0.24,
            confidence: 0.9,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: 2400);

      final sofa = scene.furnitureMeshes.singleWhere((f) => f.furnitureType == SpaceFurnitureType.sofa);
      final table = scene.furnitureMeshes.singleWhere((f) => f.furnitureType == SpaceFurnitureType.table);
      final bed = scene.furnitureMeshes.singleWhere((f) => f.furnitureType == SpaceFurnitureType.bed);
      expect(sofa.roomId, 'room-big');
      expect(table.roomId, 'room-big');
      expect(bed.roomId, 'room-small');
    });

    test('방이 없으면 가구도 생성되지 않는다(존재하지 않는 공간을 지어내지 않는다)', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [_wall('a', const Point2(0.1, 0.1), const Point2(0.9, 0.1))],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: 2400);
      expect(scene.furnitureMeshes, isEmpty);
    });
  });
}
