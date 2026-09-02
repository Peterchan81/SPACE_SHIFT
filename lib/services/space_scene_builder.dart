import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/space_scene.dart';

/// 2D CAD geometry(mm 실측/추정값) → 실제 3D 공간 geometry 변환
/// (transformation/conversion layer, WO 13번 — [CadFloorPlan]과 [SpaceScene]
/// 사이의 경계를 이 파일 하나로 유지한다).
///
/// 이번 1차 구현의 생성 대상은 벽과 바닥까지다(WO 11번). 문/창 opening은
/// [CadOpening]이 중심점 + gap 폭만 담고 있어(벽의 어느 위치에서 실제로
/// 벽체를 잘라내야 하는지 계산할 안전한 근거가 부족하다), 이번 범위에서는
/// 벽에 반영하지 않는다 — 가짜 문/창(구멍이 없는데 있는 척, 또는 실제
/// 위치와 다른 자리에 임의로 뚫기)을 만들지 않기 위해서다. 대신
/// [SpaceScene.warnings]로 그 사실을 그대로 알린다.
const List<Color> _wallColors = [
  Color(0xFFC9C2B4), // exterior
  Color(0xFFE7E2D8), // interior
];

const Color _floorColor = Color(0xFFD9CBB2);

double _mmX(Point2 p, int sourceWidthPx, double mmPerPixel) =>
    p.x * sourceWidthPx * mmPerPixel;

double _mmZ(Point2 p, int sourceHeightPx, double mmPerPixel) =>
    p.y * sourceHeightPx * mmPerPixel;

/// [plan]의 벽/공간을 [scale]과 [ceilingHeightMm] 기준으로 실제 3D
/// geometry로 변환한다. [scale]은 호출부([resolveAutoScale] 등)가 이미
/// "측정/추정/알 수 없음" 중 하나로 확정해 넘겨야 한다 — 여기서는 값을
/// 판단하지 않고 그대로 mm 변환에만 쓴다.
SpaceScene buildSpaceScene({
  required CadFloorPlan plan,
  required FloorPlanScale scale,
  required double ceilingHeightMm,
}) {
  final triangles = <SpaceTriangle>[];
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

  Vector3 toVec(Point2 p, double y) => Vector3(
    _mmX(p, plan.sourceWidthPx, scale.mmPerPixel),
    y,
    _mmZ(p, plan.sourceHeightPx, scale.mmPerPixel),
  );

  void addQuad(
    Vector3 p0,
    Vector3 p1,
    Vector3 p2,
    Vector3 p3,
    Color color,
    SpaceElementKind kind,
    String id,
  ) {
    triangles.add(
      SpaceTriangle(
        a: p0,
        b: p1,
        c: p2,
        color: color,
        sourceKind: kind,
        sourceId: id,
      ),
    );
    triangles.add(
      SpaceTriangle(
        a: p0,
        b: p2,
        c: p3,
        color: color,
        sourceKind: kind,
        sourceId: id,
      ),
    );
    for (final v in [p0, p1, p2, p3]) {
      extend(v);
    }
  }

  var wallCount = 0;
  for (final wall in plan.walls) {
    final heightMm = wall.heightMm ?? ceilingHeightMm;
    if (heightMm <= 0) continue;
    final footprint = wall.boundaryPolygon; // 4 normalized points, closed loop
    if (footprint.length != 4) continue;

    final bottom = [for (final p in footprint) toVec(p, 0)];
    final top = [for (final p in footprint) toVec(p, heightMm)];
    final color = wall.wallType == CadWallType.exterior
        ? _wallColors[0]
        : _wallColors[1];

    // 상단(천장과 맞닿는 면).
    addQuad(
      top[0],
      top[1],
      top[2],
      top[3],
      color,
      SpaceElementKind.wall,
      wall.id,
    );
    // 4개 측면.
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      addQuad(
        bottom[i],
        bottom[j],
        top[j],
        top[i],
        color,
        SpaceElementKind.wall,
        wall.id,
      );
    }
    wallCount++;
  }

  var floorCount = 0;
  for (final room in plan.rooms) {
    if (room.polygon.length != 4) continue;
    final pts = [for (final p in room.polygon) toVec(p, 0)];
    addQuad(
      pts[0],
      pts[1],
      pts[2],
      pts[3],
      _floorColor,
      SpaceElementKind.floor,
      room.id,
    );
    floorCount++;
  }

  final warnings = <String>[
    if (plan.openings.isNotEmpty)
      '문/창 ${plan.openings.length}개를 인식했지만, 이번 버전은 벽에 실제로 '
          '반영하지 않습니다(다음 단계 예정) — 벽이 뚫려 있지 않은 것으로 '
          '보일 수 있습니다.',
    if (floorCount == 0 && wallCount > 0) '공간(방)을 인식하지 못해 바닥은 생성하지 않았습니다.',
  ];

  if (triangles.isEmpty) {
    return SpaceScene(
      triangles: const [],
      minBounds: Vector3.zero(),
      maxBounds: Vector3.zero(),
      wallCount: 0,
      floorCount: 0,
      warnings: warnings,
    );
  }

  return SpaceScene(
    triangles: triangles,
    minBounds: Vector3(minX, minY, minZ),
    maxBounds: Vector3(maxX, maxY, maxZ),
    wallCount: wallCount,
    floorCount: floorCount,
    warnings: warnings,
  );
}
