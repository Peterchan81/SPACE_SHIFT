import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../models/cad_floor_plan.dart';
import '../models/space_scene_v2.dart';
import 'room_area_calculator_v2.dart';

/// SpaceScene V2 빌더 — NOMPASS V2 WO: "기존 3D 구현(SpaceScene/
/// space_scene_builder.dart)에 patch를 계속 추가하지 않는다. 새
/// pipeline을 병렬로 만든다." 이 파일은 [space_scene_builder.dart](V1)를
/// import하지 않고 완전히 독립적으로 존재한다.
///
/// 3D의 source of truth는 [CadWall]/[CadOpening]/[CadRoom]/
/// [FloorPlanScale]/천장고뿐이다(WO 8번) — 벽은 room polygon
/// triangulation에서 절대 파생되지 않고, 각 [CadWall]로부터 직접
/// 안정적인 직육면체를 만든다(WO 9번). 바닥은 벽과 완전히 분리된
/// pipeline(WO 11번)이다.

const List<Color> _wallColorsV2 = [
  Color(0xFFC9C2B4), // exterior
  Color(0xFFE7E2D8), // interior
];

const Color _floorColorV2 = Color(0xFFD9CBB2);

bool _isFiniteVec3(Vector3 v) => v.x.isFinite && v.y.isFinite && v.z.isFinite;

/// [plan]/[scale]/[ceilingHeightMm]로부터 [SpaceSceneV2]를 만든다.
/// 실패(비정상 geometry)는 절대 조용히 숨기지 않고 [SpaceSceneV2.warnings]
/// 로 정직하게 보고한다(가짜 3D 금지 원칙, WO 공통).
SpaceSceneV2 buildSpaceSceneV2({
  required CadFloorPlan plan,
  required FloorPlanScale scale,
  required double ceilingHeightMm,
}) {
  final expectedDiagonalMm = math.sqrt(
    math.pow(plan.sourceWidthPx * scale.mmPerPixel, 2) +
        math.pow(plan.sourceHeightPx * scale.mmPerPixel, 2),
  );
  final maxValidEdgeMm = expectedDiagonalMm * 3;
  final invalidSources = <String>{};

  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  void extend(Vector3 v) {
    if (v.x < minX) minX = v.x;
    if (v.y < minY) minY = v.y;
    if (v.z < minZ) minZ = v.z;
    if (v.x > maxX) maxX = v.x;
    if (v.y > maxY) maxY = v.y;
    if (v.z > maxZ) maxZ = v.z;
  }

  SpaceTriangleV2? makeTriangle(
    Vector3 a,
    Vector3 b,
    Vector3 c,
    Color color,
    String debugSourceLabel,
  ) {
    if (!_isFiniteVec3(a) || !_isFiniteVec3(b) || !_isFiniteVec3(c)) {
      invalidSources.add('$debugSourceLabel (NaN/Infinity 좌표)');
      return null;
    }
    final longestEdge = math.max(
      (b - a).length,
      math.max((c - b).length, (a - c).length),
    );
    if (maxValidEdgeMm > 0 && longestEdge > maxValidEdgeMm) {
      invalidSources.add('$debugSourceLabel (비정상적으로 긴 edge)');
      return null;
    }
    final area = (b - a).cross(c - a).length / 2;
    if (area < 1e-6) return null; // 중복/일직선 정점 — 정상 케이스, 경고 아님.
    extend(a);
    extend(b);
    extend(c);
    return SpaceTriangleV2(a: a, b: b, c: c, color: color);
  }

  void addQuad(
    List<SpaceTriangleV2> into,
    Vector3 p0,
    Vector3 p1,
    Vector3 p2,
    Vector3 p3,
    Color color,
    String debugSourceLabel,
  ) {
    final t1 = makeTriangle(p0, p1, p2, color, debugSourceLabel);
    if (t1 != null) into.add(t1);
    final t2 = makeTriangle(p0, p2, p3, color, debugSourceLabel);
    if (t2 != null) into.add(t2);
  }

  // ---- 벽(WO 9번 — 항상 CadWall에서 직접 만든 안정적인 직육면체) ----
  final wallMeshes = <SpaceWallMeshV2>[];
  for (final wall in plan.walls) {
    final heightMm = wall.heightMm ?? ceilingHeightMm;
    if (heightMm <= 0) continue;
    // CadWall.boundaryPolygon이 이미 "두께를 그 축의 정규화 단위로 정확히
    // 오프셋"하도록 검증된 유일한 벽 footprint 계산이라(3D 근본 수정 WO),
    // 여기서 다시 구현하지 않고 CAD source of truth를 그대로 재사용한다
    // (WO 8번 — "3D의 source of truth는 CadWall이다").
    final footprint = wall.boundaryPolygon;
    if (footprint.length != 4) continue;
    final footprintMm = [for (final p in footprint) pointToMm(p, plan, scale)];
    final bottom = footprintMm;
    final top = [for (final p in footprintMm) Vector3(p.x, heightMm, p.z)];

    final isExterior = wall.wallType == CadWallType.exterior;
    final color = isExterior ? _wallColorsV2[0] : _wallColorsV2[1];
    final triangles = <SpaceTriangleV2>[];

    // top face(천장과 맞닿는 면) — 1 quad.
    addQuad(
      triangles,
      top[0],
      top[1],
      top[2],
      top[3],
      color,
      'wall:${wall.id}',
    );
    // 4개 측면(outer/inner + start/end cap) — 4 quad.
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      addQuad(
        triangles,
        bottom[i],
        bottom[j],
        top[j],
        top[i],
        color,
        'wall:${wall.id}',
      );
    }
    if (triangles.isEmpty) continue;

    final isHorizontal =
        (wall.start.y - wall.end.y).abs() < (wall.start.x - wall.end.x).abs();
    final thicknessMm = isHorizontal
        ? wall.thicknessNormalized * plan.sourceHeightPx * scale.mmPerPixel
        : wall.thicknessNormalized * plan.sourceWidthPx * scale.mmPerPixel;
    final lengthMm = plan.realMmBetween(wall.start, wall.end, scale) ?? 0;

    wallMeshes.add(
      SpaceWallMeshV2(
        identity: SpaceObjectIdentityV2(
          objectId: 'wall:${wall.id}',
          sourceKind: SpaceElementKindV2.wall,
          sourceId: wall.id,
          wallId: wall.id,
          dimensions: SpaceDimensionsV2(
            heightMm: heightMm,
            widthMm: lengthMm,
            thicknessMm: thicknessMm,
          ),
          color: color,
        ),
        triangles: triangles,
        startMm: bottom[0],
        endMm: bottom[1],
        isExterior: isExterior,
      ),
    );
  }

  // ---- 바닥(WO 11/12번 — 벽과 완전히 분리, 실패해도 벽에 영향 없음) ----
  final areaSummary = computeRoomAreasV2(plan: plan, scale: scale);
  final areaById = {for (final r in areaSummary.rooms) r.id: r};
  final floorMeshes = <SpaceFloorMeshV2>[];
  var floorTriangulationFailures = 0;
  for (final room in plan.rooms) {
    final area = areaById[room.id];
    if (area == null || area.polygonMm.isEmpty) continue; // invalid polygon.
    final cleanedNormalized = cleanPolygonV2(room.polygon);
    final earTriangles = earClipTriangulateV2(cleanedNormalized);
    if (earTriangles.isEmpty) {
      floorTriangulationFailures++;
      continue;
    }
    final pts = area.polygonMm;
    final triangles = <SpaceTriangleV2>[];
    for (final tri in earTriangles) {
      final a = pts[tri[0]];
      var b = pts[tri[1]];
      var c = pts[tri[2]];
      // 바닥 법선을 항상 +Y로 고정한다(WO — winding에 따라 방마다
      // 위/아래가 뒤섞이면 backface culling에서 무작위로 사라진다).
      if ((b - a).cross(c - a).y < 0) {
        final tmp = b;
        b = c;
        c = tmp;
      }
      final t = makeTriangle(a, b, c, _floorColorV2, 'floor:${room.id}');
      if (t != null) triangles.add(t);
    }
    if (triangles.isEmpty) continue;

    floorMeshes.add(
      SpaceFloorMeshV2(
        identity: SpaceObjectIdentityV2(
          objectId: 'floor:${room.id}',
          sourceKind: SpaceElementKindV2.floor,
          sourceId: room.id,
          roomId: room.id,
          floorId: room.id,
          color: _floorColorV2,
        ),
        triangles: triangles,
        polygonMm: pts,
      ),
    );
  }

  // ---- opening identity만(WO 19번 — geometry에는 아직 반영하지 않음) ----
  final openings = [
    for (final opening in plan.openings)
      SpaceOpeningV2(
        identity: SpaceObjectIdentityV2(
          objectId: 'opening:${opening.id}',
          sourceKind: SpaceElementKindV2.opening,
          sourceId: opening.id,
          wallId: opening.wallId,
          openingId: opening.id,
        ),
        centerMm: pointToMm(opening.center, plan, scale),
        widthMm: opening.widthNormalized * plan.diagonalPx * scale.mmPerPixel,
      ),
  ];

  final excludedRoomCount = areaSummary.rooms
      .where((r) => !r.includedInTotal)
      .length;
  final warnings = <String>[
    if (plan.openings.isNotEmpty)
      '문/창 ${plan.openings.length}개를 인식했지만, 이번 버전은 벽에 실제로 '
          '반영하지 않습니다(다음 단계 예정) — 벽이 뚫려 있지 않은 것으로 '
          '보일 수 있습니다.',
    if (floorMeshes.isEmpty && wallMeshes.isNotEmpty)
      '공간(방)을 인식하지 못해 바닥은 생성하지 않았습니다.',
    if (floorTriangulationFailures > 0)
      '$floorTriangulationFailures개 공간의 바닥 polygon을 삼각분할하지 못해 그 공간만 '
          '바닥 없이 표시됩니다(벽은 정상 표시).',
    if (excludedRoomCount > 0)
      '공간 $excludedRoomCount개가 실제 방이 아닐 가능성이 있어(벽 틈/구조 노이즈 등) 전체 '
          '면적 합계에서 제외했습니다 — 3D에는 계속 표시됩니다.',
    if (invalidSources.isNotEmpty)
      '비정상 geometry ${invalidSources.length}건을 제외했습니다: '
          '${invalidSources.take(5).join(', ')}'
          '${invalidSources.length > 5 ? ' 외 ${invalidSources.length - 5}건' : ''}',
  ];

  if (wallMeshes.isEmpty && floorMeshes.isEmpty) {
    return SpaceSceneV2(
      wallMeshes: const [],
      floorMeshes: const [],
      openings: openings,
      minBounds: Vector3.zero(),
      maxBounds: Vector3.zero(),
      warnings: warnings,
    );
  }

  return SpaceSceneV2(
    wallMeshes: wallMeshes,
    floorMeshes: floorMeshes,
    openings: openings,
    minBounds: Vector3(minX, minY, minZ),
    maxBounds: Vector3(maxX, maxY, maxZ),
    warnings: warnings,
  );
}
