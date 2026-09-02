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

/// 단순 다각형(오목 가능, 자기교차 없음)을 삼각형 인덱스 목록(원본
/// [polygon] 기준)으로 분할한다(ear clipping) — 2D 정확도 개선 WO(8번),
/// 방 polygon이 이제 항상 사각형이 아니라 실제 윤곽(오목 형태 포함)일
/// 수 있어 바닥 생성에 일반적인 다각형 삼각분할이 필요하다. 예상 밖
/// 입력(자기교차 등)을 만나면 그때까지 만든 삼각형만 반환한다(전체를
/// 포기하지 않는다 — 부분적으로라도 실제 바닥을 보여주는 쪽이 안전).
List<List<int>> _earClipTriangulate(List<Point2> polygon) {
  final n = polygon.length;
  if (n < 3) return const [];
  if (n == 3) {
    return [
      [0, 1, 2],
    ];
  }

  double signedArea() {
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % n];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum / 2;
  }

  final ccw = signedArea() > 0;

  bool isConvexCorner(Point2 a, Point2 b, Point2 c) {
    final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    return ccw ? cross > 0 : cross < 0;
  }

  bool pointInTriangle(Point2 p, Point2 a, Point2 b, Point2 c) {
    double sign(Point2 p1, Point2 p2, Point2 p3) =>
        (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y);
    final d1 = sign(p, a, b);
    final d2 = sign(p, b, c);
    final d3 = sign(p, c, a);
    final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
    final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(hasNeg && hasPos);
  }

  final indices = List<int>.generate(n, (i) => i);
  final triangles = <List<int>>[];
  var guard = 0;
  while (indices.length > 3 && guard < n * n + 8) {
    guard++;
    var earFound = false;
    for (var i = 0; i < indices.length; i++) {
      final prevI = indices[(i - 1 + indices.length) % indices.length];
      final curI = indices[i];
      final nextI = indices[(i + 1) % indices.length];
      final a = polygon[prevI], b = polygon[curI], c = polygon[nextI];
      if (!isConvexCorner(a, b, c)) continue;

      var containsOther = false;
      for (final idx in indices) {
        if (idx == prevI || idx == curI || idx == nextI) continue;
        if (pointInTriangle(polygon[idx], a, b, c)) {
          containsOther = true;
          break;
        }
      }
      if (containsOther) continue;

      triangles.add([prevI, curI, nextI]);
      indices.removeAt(i);
      earFound = true;
      break;
    }
    if (!earFound) break; // 예상 밖(자기교차 등) — 지금까지 만든 것만 쓴다.
  }
  if (indices.length == 3) {
    triangles.add([indices[0], indices[1], indices[2]]);
  }
  return triangles;
}

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
    String id, {
    bool isExteriorWall = false,
  }) {
    triangles.add(
      SpaceTriangle(
        a: p0,
        b: p1,
        c: p2,
        color: color,
        sourceKind: kind,
        sourceId: id,
        isExteriorWall: isExteriorWall,
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
        isExteriorWall: isExteriorWall,
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
    final isExterior = wall.wallType == CadWallType.exterior;
    final color = isExterior ? _wallColors[0] : _wallColors[1];

    // 상단(천장과 맞닿는 면) — cutaway(WO 20번) 대상에서 제외한다(항상
    // 보임): 근접 외벽의 측면만 숨겨도 상단 테두리가 남아 있으면 실내
    // 구조를 이해하는 데 오히려 도움이 된다.
    addQuad(
      top[0],
      top[1],
      top[2],
      top[3],
      color,
      SpaceElementKind.wall,
      wall.id,
    );
    // 4개 측면 — 외벽이면 cutaway 대상 표시(isExteriorWall)만 남기고,
    // 실제로 숨길지는 렌더러가 카메라 방향을 보고 매 프레임 판단한다
    // (WO 20번 — 정적으로 결정하지 않는다, 회전하면 다른 벽이 숨겨진다).
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
        isExteriorWall: isExterior,
      );
    }
    wallCount++;
  }

  var floorCount = 0;
  for (final room in plan.rooms) {
    // 2D 정확도 개선 WO(8번) — room.polygon이 이제 항상 사각형이 아니라
    // 실제 윤곽(N점, L자 등 오목 형태 포함)일 수 있다. ear clipping으로
    // 일반 단순 다각형을 삼각형으로 분할한다(사각형도 이 경로로 그대로
    // 처리된다 — 특수 케이스를 따로 두지 않는다).
    final earTriangles = _earClipTriangulate(room.polygon);
    if (earTriangles.isEmpty) continue;
    final pts = [for (final p in room.polygon) toVec(p, 0)];
    for (final tri in earTriangles) {
      final a = pts[tri[0]];
      final b = pts[tri[1]];
      final c = pts[tri[2]];
      triangles.add(
        SpaceTriangle(
          a: a,
          b: b,
          c: c,
          color: _floorColor,
          sourceKind: SpaceElementKind.floor,
          sourceId: room.id,
        ),
      );
      for (final v in [a, b, c]) {
        extend(v);
      }
    }
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
