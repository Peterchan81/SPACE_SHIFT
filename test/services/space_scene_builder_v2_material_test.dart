// GPT FLOORPLAN → STRUCTURED 2D → REAL 3D ISO FLOW WO §11 — V1 기본 재질
// (일반 내부 벽: white / 일반 바닥: wood / 욕실 바닥·벽: tile)이 실제
// SpaceSceneV2 mesh identity.color에 반영되는지, 그리고 사용자
// override(CadWall/CadRoom.materialOverride)가 항상 그 기본값보다
// 우선하는지 확인한다.
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/space_scene_v2.dart';
import 'package:ason_space/models/ss_spatial_model.dart' show SSRoomType;
import 'package:ason_space/services/space_scene_builder_v2.dart';

const _scale = FloorPlanScale(
  mmPerPixel: 5.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 5000,
  source: ScaleSource.measured,
);

SpaceWallMeshV2 _wallMeshFor(SpaceSceneV2 scene, String id) =>
    scene.wallMeshes.singleWhere((w) => w.identity.wallId == id);

SpaceFloorMeshV2 _floorMeshFor(SpaceSceneV2 scene, String id) =>
    scene.floorMeshes.singleWhere((f) => f.identity.roomId == id);

SpaceFloorMeshV2 _ceilingMeshFor(SpaceSceneV2 scene, String id) =>
    scene.ceilingMeshes.singleWhere((c) => c.identity.roomId == id);

void main() {
  group('default material — room type 기반', () {
    test('일반(other) 공간의 바닥은 wood 기본색이다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: const [],
        openings: const [],
        rooms: [
          CadRoom(
            id: 'living',
            polygon: const [
              Point2(0.1, 0.1),
              Point2(0.9, 0.1),
              Point2(0.9, 0.9),
              Point2(0.1, 0.9),
            ],
            areaNormalized: 0.64,
            confidence: 0.9,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: 2400);
      final floor = _floorMeshFor(scene, 'living');
      expect(floor.identity.color, isNotNull);
      // wood 기본색은 white/tile 계열과 확실히 다른 색이어야 한다.
      expect(floor.identity.color, isNot(const Color(0xFFFAFAF7)));
    });

    test('욕실(bathroom) 공간의 바닥은 tile 기본색이고, 일반 공간과 다르다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: const [],
        openings: const [],
        rooms: [
          CadRoom(
            id: 'living',
            polygon: const [
              Point2(0.1, 0.1),
              Point2(0.4, 0.1),
              Point2(0.4, 0.9),
              Point2(0.1, 0.9),
            ],
            areaNormalized: 0.24,
            confidence: 0.9,
          ),
          CadRoom(
            id: 'bath',
            polygon: const [
              Point2(0.6, 0.1),
              Point2(0.9, 0.1),
              Point2(0.9, 0.9),
              Point2(0.6, 0.9),
            ],
            areaNormalized: 0.24,
            confidence: 0.9,
            roomType: SSRoomType.bathroom,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: 2400);
      final livingFloor = _floorMeshFor(scene, 'living');
      final bathFloor = _floorMeshFor(scene, 'bath');

      expect(bathFloor.identity.color, isNot(livingFloor.identity.color));
    });

    test('욕실과 맞닿은 내벽은 tile 벽색, 욕실과 무관한 내벽은 white다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          // bath(0.6~0.9)와 living(0.1~0.4) 사이의 벽 — 어느 쪽에도 안
          // 닿음(중간이 비어 있는 배치라 가정, 욕실과 무관).
          const CadWall(
            id: 'wall-far',
            start: Point2(0.45, 0.1),
            end: Point2(0.45, 0.9),
            thicknessNormalized: 0.02,
            wallType: CadWallType.interior,
            confidence: 0.9,
          ),
          // bath 폴리곤 왼쪽 변과 정확히 겹치는 벽 — 욕실과 맞닿아야 한다.
          const CadWall(
            id: 'wall-bath',
            start: Point2(0.6, 0.1),
            end: Point2(0.6, 0.9),
            thicknessNormalized: 0.02,
            wallType: CadWallType.interior,
            confidence: 0.9,
          ),
        ],
        openings: const [],
        rooms: [
          CadRoom(
            id: 'bath',
            polygon: const [
              Point2(0.6, 0.1),
              Point2(0.9, 0.1),
              Point2(0.9, 0.9),
              Point2(0.6, 0.9),
            ],
            areaNormalized: 0.24,
            confidence: 0.9,
            roomType: SSRoomType.bathroom,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: 2400);
      final farWall = _wallMeshFor(scene, 'wall-far');
      final bathWall = _wallMeshFor(scene, 'wall-bath');

      expect(bathWall.identity.color, isNot(farWall.identity.color));
    });
  });

  group('user override — 항상 default보다 우선한다', () {
    test('CadRoom.materialOverride가 있으면 roomType 기본값 대신 그 색을 쓴다', () {
      const override = Color(0xFF123456);
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: const [],
        openings: const [],
        rooms: [
          CadRoom(
            id: 'bath',
            polygon: const [
              Point2(0.1, 0.1),
              Point2(0.9, 0.1),
              Point2(0.9, 0.9),
              Point2(0.1, 0.9),
            ],
            areaNormalized: 0.64,
            confidence: 0.9,
            roomType: SSRoomType.bathroom,
            materialOverride: override,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: 2400);
      expect(_floorMeshFor(scene, 'bath').identity.color, override);
    });

    test('CadWall.materialOverride가 있으면 exterior/interior 기본값 대신 그 색을 쓴다', () {
      const override = Color(0xFF654321);
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          CadWall(
            id: 'wall-ext',
            start: const Point2(0.1, 0.1),
            end: const Point2(0.9, 0.1),
            thicknessNormalized: 0.02,
            wallType: CadWallType.exterior,
            confidence: 0.9,
            materialOverride: override,
          ),
        ],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: 2400);
      expect(_wallMeshFor(scene, 'wall-ext').identity.color, override);
    });

    test(
      'CadRoom.ceilingMaterialOverride는 materialOverride(바닥)와 완전히 독립된 '
      '색이다 — 하나를 바꿔도 다른 하나는 그대로다',
      () {
        const floorOverride = Color(0xFF00AA00);
        const ceilingOverride = Color(0xFFAA0000);
        final plan = CadFloorPlan(
          sourceWidthPx: 1000,
          sourceHeightPx: 1000,
          walls: const [],
          openings: const [],
          rooms: [
            CadRoom(
              id: 'living',
              polygon: const [
                Point2(0.1, 0.1),
                Point2(0.9, 0.1),
                Point2(0.9, 0.9),
                Point2(0.1, 0.9),
              ],
              areaNormalized: 0.64,
              confidence: 0.9,
              materialOverride: floorOverride,
              ceilingMaterialOverride: ceilingOverride,
            ),
          ],
          warnings: const [],
        );
        final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: 2400);
        expect(_floorMeshFor(scene, 'living').identity.color, floorOverride);
        expect(_ceilingMeshFor(scene, 'living').identity.color, ceilingOverride);
      },
    );
  });

  group('WO092 §4 — 천장 geometry', () {
    test('공간마다 천장 mesh가 하나씩 생기고, 기본색은 바닥 기본색과 다르다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: const [],
        openings: const [],
        rooms: [
          CadRoom(
            id: 'living',
            polygon: const [
              Point2(0.1, 0.1),
              Point2(0.9, 0.1),
              Point2(0.9, 0.9),
              Point2(0.1, 0.9),
            ],
            areaNormalized: 0.64,
            confidence: 0.9,
          ),
        ],
        warnings: const [],
      );
      const ceilingHeightMm = 2400.0;
      final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: ceilingHeightMm);
      final ceiling = _ceilingMeshFor(scene, 'living');
      final floor = _floorMeshFor(scene, 'living');

      expect(ceiling.identity.sourceKind, SpaceElementKindV2.ceiling);
      expect(ceiling.identity.color, isNot(floor.identity.color));
      // 천장 polygon은 바닥과 같은 평면 모양을 천장고 높이(Y)로 그대로
      // 올린 것이어야 한다.
      for (final p in ceiling.polygonMm) {
        expect(p.y, closeTo(ceilingHeightMm, 1e-6));
      }
      // 천장 삼각형 normal은 방 안쪽(아래, -Y)을 향해야 한다 — 위에서
      // 내려다보는 기본 아이소 카메라에는 backface로 컬링되어 보이지
      // 않고, 방 안에서 위를 보면(3D 투시 등) 보이게 하기 위함이다.
      for (final tri in ceiling.triangles) {
        expect(tri.normal.y, lessThan(0));
      }
      // 바닥 normal은 여전히 위(+Y)를 향한다(회귀 방지 — 천장 추가가
      // 기존 바닥 winding을 건드리지 않았는지 확인).
      for (final tri in floor.triangles) {
        expect(tri.normal.y, greaterThan(0));
      }
    });
  });
}
