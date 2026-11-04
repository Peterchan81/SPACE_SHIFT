/// SS013 — [SsIsoEditorController]의 상태(기존 [SsCadScene] + 새 [SsIsoDesignExtras])로부터 실제
/// 3D scene([SpaceSceneV2])을 만든다. 벽/바닥/천장/창은 전부 기존 [buildSpaceSceneV2](새로 만들지
/// 않는다)를 그대로 호출해 얻고, 이 함수는 그 결과 위에 SS013에서만 생기는 객체(사용자가 추가한
/// 가구/조명/설비, 3D에서 숨긴 객체 제외)만 더한다.
library;

import 'package:flutter/material.dart' show Color;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../models/cad_floor_plan.dart' show CadFloorPlan, CadRoom, FloorPlanScale, resolveAutoScale;
import '../models/floor_plan_geometry.dart';
import '../models/space_scene_v2.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_iso_design_extras.dart';
import 'room_area_calculator_v2.dart' show pointToMm;
import 'space_scene_builder_v2.dart';

/// 가구/조명/설비처럼 작은 직육면체 한 개로 표현하는 객체의 공통 box geometry — 기존
/// [space_scene_builder_v2.dart]의 가구 primitive(테이블 다리 등)와 같은 생각(삼각형 12개,
/// outward normal, 각 꼭짓점을 공유하지 않아 flat shading)으로 새로 만든다(그 파일 내부 함수는
/// private이라 재사용할 수 없다 — 원리만 그대로 따른다).
List<SpaceTriangleV2> buildIsoBoxTriangles({
  required double centerXMm,
  required double centerZMm,
  required double widthMm,
  required double depthMm,
  required double baseYMm,
  required double topYMm,
  required Color color,
}) {
  final hw = widthMm / 2, hd = depthMm / 2;
  final x0 = centerXMm - hw, x1 = centerXMm + hw;
  final z0 = centerZMm - hd, z1 = centerZMm + hd;
  final b00 = Vector3(x0, baseYMm, z0), b10 = Vector3(x1, baseYMm, z0), b11 = Vector3(x1, baseYMm, z1), b01 = Vector3(x0, baseYMm, z1);
  final t00 = Vector3(x0, topYMm, z0), t10 = Vector3(x1, topYMm, z0), t11 = Vector3(x1, topYMm, z1), t01 = Vector3(x0, topYMm, z1);
  SpaceTriangleV2 tri(Vector3 a, Vector3 b, Vector3 c) => SpaceTriangleV2(a: a, b: b, c: c, color: color);
  return [
    tri(t00, t10, t11), tri(t00, t11, t01), // top
    tri(b00, b11, b10), tri(b00, b01, b11), // bottom
    tri(b00, b01, t01), tri(b00, t01, t00), // -X side
    tri(b10, t10, t11), tri(b10, t11, b11), // +X side
    tri(b00, t00, t10), tri(b00, t10, b10), // -Z side
    tri(b01, b11, t11), tri(b01, t11, t01), // +Z side
  ];
}

SpaceObjectIdentityV2 _identity({required String objectId, required SpaceElementKindV2 sourceKind, required String sourceId, String? roomId, Color? color}) =>
    SpaceObjectIdentityV2(objectId: objectId, sourceKind: sourceKind, sourceId: sourceId, roomId: roomId, color: color);

/// [SsIsoEditorController.scene3d]가 쓰는 메인 빌더. [ceilingHeightMm]는 조명을 천장 근처에 놓을
/// 때만 쓰고 geometry는 항상 CadWall의 실측/기본 높이([buildSpaceSceneV2] 기존 로직)를 따른다.
SpaceSceneV2 buildIsoEditorScene({required SsCadScene cad, required SsIsoDesignExtras extras, required double ceilingHeightMm}) {
  final plan = cad.plan;
  final scale = cad.scale ?? resolveAutoScale(plan, null);
  final base = buildSpaceSceneV2(plan: plan, scale: scale, ceilingHeightMm: ceilingHeightMm);

  final keptBase = [
    for (final f in base.furnitureMeshes)
      if (!extras.hiddenObjectIds.contains(f.identity.objectId)) f,
  ];

  final extraMeshes = <SpaceFurnitureMeshV2>[];
  for (final f in cad.furniture) {
    final objectId = 'isoFurniture:${f.id}';
    if (extras.hiddenObjectIds.contains(objectId)) continue;
    final center = pointToMm(f.center, plan, scale);
    final widthMm = (plan.realMmForNormalizedLength(f.widthNormalized, scale) ?? 600).abs();
    final depthMm = (plan.realMmForNormalizedLength(f.depthNormalized, scale) ?? 600).abs();
    final color = const Color(0xFF8B2FE0);
    extraMeshes.add(
      SpaceFurnitureMeshV2(
        identity: _identity(objectId: objectId, sourceKind: SpaceElementKindV2.furniture, sourceId: f.id, roomId: '', color: color),
        triangles: buildIsoBoxTriangles(centerXMm: center.x, centerZMm: center.z, widthMm: widthMm, depthMm: depthMm, baseYMm: 0, topYMm: 750, color: color),
        furnitureType: SpaceFurnitureType.table,
        centerMm: center,
        roomId: '',
      ),
    );
  }

  for (final l in extras.lights) {
    final objectId = 'isoLight:${l.id}';
    if (extras.hiddenObjectIds.contains(objectId)) continue;
    final color = Color(l.kind.defaultColorValue);
    final center = Vector3(l.xMm, l.yMm, l.zMm);
    extraMeshes.add(
      SpaceFurnitureMeshV2(
        identity: _identity(objectId: objectId, sourceKind: SpaceElementKindV2.light, sourceId: l.id, roomId: l.roomId, color: color),
        triangles: buildIsoBoxTriangles(centerXMm: l.xMm, centerZMm: l.zMm, widthMm: 150, depthMm: 150, baseYMm: l.yMm - 40, topYMm: l.yMm + 40, color: color),
        furnitureType: SpaceFurnitureType.table,
        centerMm: center,
        roomId: l.roomId,
      ),
    );
  }

  for (final e in extras.equipment) {
    final objectId = 'isoEquipment:${e.id}';
    if (extras.hiddenObjectIds.contains(objectId)) continue;
    final color = Color(e.kind.defaultColorValue);
    final center = Vector3(e.xMm, 0, e.zMm);
    extraMeshes.add(
      SpaceFurnitureMeshV2(
        identity: _identity(objectId: objectId, sourceKind: SpaceElementKindV2.other, sourceId: e.id, roomId: e.roomId, color: color),
        triangles: buildIsoBoxTriangles(centerXMm: e.xMm, centerZMm: e.zMm, widthMm: 500, depthMm: 450, baseYMm: 0, topYMm: 850, color: color),
        furnitureType: SpaceFurnitureType.table,
        centerMm: center,
        roomId: e.roomId,
      ),
    );
  }

  return SpaceSceneV2(
    wallMeshes: base.wallMeshes,
    floorMeshes: base.floorMeshes,
    ceilingMeshes: base.ceilingMeshes,
    furnitureMeshes: [...keptBase, ...extraMeshes],
    windowMeshes: base.windowMeshes,
    openings: base.openings,
    minBounds: base.minBounds,
    maxBounds: base.maxBounds,
    warnings: base.warnings,
  );
}

/// 방 중심(정규화 좌표 polygon 평균)을 world mm로 — 조명/설비를 "방 한가운데"에 기본 배치할 때 쓴다.
/// 방이 없거나(폴리곤 0점) plan에 없는 roomId면 null(지어내지 않는다).
Vector3? roomCenterMm(CadFloorPlan plan, FloorPlanScale scale, String roomId) {
  CadRoom? room;
  for (final r in plan.rooms) {
    if (r.id == roomId) {
      room = r;
      break;
    }
  }
  if (room == null || room.polygon.isEmpty) return null;
  var sx = 0.0, sy = 0.0;
  for (final p in room.polygon) {
    sx += p.x;
    sy += p.y;
  }
  final centroid = Point2(sx / room.polygon.length, sy / room.polygon.length);
  return pointToMm(centroid, plan, scale);
}
