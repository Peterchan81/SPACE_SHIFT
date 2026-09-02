import 'dart:math' as math;

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

/// [polygon]의 인접하지 않은 두 변이 실제로 교차하는지 확인한다(단순
/// 다각형인지 검사, ear-clipping 전 필수 전제조건). 표준 세그먼트 교차
/// 판정(orientation 부호 비교)만 쓴다 — 끝점이 살짝 스치는 경우까지
/// 전부 자기교차로 판정하면 정상적인 rectilinear 윤곽(연속된 변이
/// 같은 점을 공유)까지 걸릴 수 있어, 인접 변(같은 정점을 공유하는 변)은
/// 애초에 비교 대상에서 제외한다.
bool _isSelfIntersecting(List<Point2> polygon) {
  final n = polygon.length;
  double orientation(Point2 a, Point2 b, Point2 c) =>
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);

  bool segmentsIntersect(Point2 p1, Point2 p2, Point2 p3, Point2 p4) {
    final d1 = orientation(p3, p4, p1);
    final d2 = orientation(p3, p4, p2);
    final d3 = orientation(p1, p2, p3);
    final d4 = orientation(p1, p2, p4);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  for (var i = 0; i < n; i++) {
    final a1 = polygon[i];
    final a2 = polygon[(i + 1) % n];
    for (var j = i + 1; j < n; j++) {
      if (j == i) continue;
      // 인접 변(정점 공유)은 제외.
      if (j == (i + 1) % n || (j + 1) % n == i) continue;
      final b1 = polygon[j];
      final b2 = polygon[(j + 1) % n];
      if (segmentsIntersect(a1, a2, b1, b2)) return true;
    }
  }
  return false;
}

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
  // 3D 근본 수정 WO(3번) — 자기교차하는 폴리곤을 그대로 삼각분할하면
  // convex/point-in-triangle 판정이 폴리곤 밖을 가로지르는 삼각형을
  // 만들 수 있다(벽 geometry는 이 함수를 안 쓰므로 영향이 없지만, 방
  // 윤곽은 이 결과를 그대로 바닥 geometry로 쓴다). 여기서 미리 걸러
  // 아예 만들지 않는다 — 잘못된 바닥보다 바닥이 없는 쪽이 안전하다.
  if (_isSelfIntersecting(polygon)) return const [];

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

  // 3D 근본 수정 WO — 렌더러에 넘기기 전에 각 삼각형을 실제로 검증한다.
  // "근처 벽으로 확대했을 때 튀는 near-plane 정점" 문제는 이전에 이미
  // 고쳤지만, geometry 생성 단계 자체가 잘못된 폴리곤(자기교차·안장점
  // 등, 실제 CAD에서 나올 수 있는 예상 밖 입력)을 만들면 렌더러의
  // near-plane 방어만으로는 못 막는다 — 그래서 여기서 한 번 더, "이
  // 도면이 실제로 가질 수 있는 최대 대각선"을 기준으로 비정상적으로
  // 긴 edge/NaN/Infinity를 가진 삼각형을 소스별로 걸러낸다. 숨기고
  // 끝내지 않고 [SpaceScene.warnings]에 어떤 geometry(source id/kind)가
  // 문제였는지 정직하게 남긴다.
  final expectedDiagonalMm = math.sqrt(
    math.pow(plan.sourceWidthPx * scale.mmPerPixel, 2) +
        math.pow(plan.sourceHeightPx * scale.mmPerPixel, 2),
  );
  // 실측 오차·사용자 편집으로 정규화 좌표가 0~1을 살짝 벗어날 수 있어
  // 넉넉한 안전 배율을 둔다 — 그래도 "다른 vertex까지 길게 뻗는" 진짜
  // 깨진 삼각형은 이 배율을 몇 배씩 초과한다.
  final maxValidEdgeMm = expectedDiagonalMm * 3;
  final invalidSources = <String>{};

  void extend(Vector3 v) {
    if (v.x < minX) minX = v.x;
    if (v.y < minY) minY = v.y;
    if (v.z < minZ) minZ = v.z;
    if (v.x > maxX) maxX = v.x;
    if (v.y > maxY) maxY = v.y;
    if (v.z > maxZ) maxZ = v.z;
  }

  bool isFiniteVec(Vector3 v) => v.x.isFinite && v.y.isFinite && v.z.isFinite;

  void addTriangle(
    Vector3 a,
    Vector3 b,
    Vector3 c,
    Color color,
    SpaceElementKind kind,
    String id, {
    bool isExteriorWall = false,
  }) {
    if (!isFiniteVec(a) || !isFiniteVec(b) || !isFiniteVec(c)) {
      invalidSources.add('$kind:$id (NaN/Infinity 좌표)');
      return;
    }
    final longestEdge = math.max(
      (b - a).length,
      math.max((c - b).length, (a - c).length),
    );
    if (maxValidEdgeMm > 0 && longestEdge > maxValidEdgeMm) {
      invalidSources.add('$kind:$id (비정상적으로 긴 edge)');
      return;
    }
    // 넓이 0에 가까운 (중복/일직선) 정점은 조용히 버린다 — 벽 모서리가
    // 딱 맞물리는 곳에서 흔히 생기는 정상적인 케이스라 경고 대상이
    // 아니다.
    final area = (b - a).cross(c - a).length / 2;
    if (area < 1e-6) return;

    triangles.add(
      SpaceTriangle(
        a: a,
        b: b,
        c: c,
        color: color,
        sourceKind: kind,
        sourceId: id,
        isExteriorWall: isExteriorWall,
      ),
    );
    extend(a);
    extend(b);
    extend(c);
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
    addTriangle(p0, p1, p2, color, kind, id, isExteriorWall: isExteriorWall);
    addTriangle(p0, p2, p3, color, kind, id, isExteriorWall: isExteriorWall);
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
      var b = pts[tri[1]];
      var c = pts[tri[2]];
      // 3D 2차 근본 수정 — room.polygon의 winding(추적 방향에 따라
      // CW/CCW가 달라질 수 있다)에 그대로 의존하면 바닥 삼각형의 법선이
      // 방마다 위(+Y) 또는 아래(-Y)로 뒤섞여 나올 수 있다. 렌더러가
      // backface culling(카메라 반대쪽을 향한 면은 그리지 않음)을 쓰기
      // 시작하면, 뒤집힌 바닥은 위에서 보는 카메라에 아예 안 보이게
      // 된다 — 그래서 여기서 항상 위를 향하도록 명시적으로 고정한다.
      if ((b - a).cross(c - a).y < 0) {
        final tmp = b;
        b = c;
        c = tmp;
      }
      addTriangle(a, b, c, _floorColor, SpaceElementKind.floor, room.id);
    }
    floorCount++;
  }

  final warnings = <String>[
    if (plan.openings.isNotEmpty)
      '문/창 ${plan.openings.length}개를 인식했지만, 이번 버전은 벽에 실제로 '
          '반영하지 않습니다(다음 단계 예정) — 벽이 뚫려 있지 않은 것으로 '
          '보일 수 있습니다.',
    if (floorCount == 0 && wallCount > 0) '공간(방)을 인식하지 못해 바닥은 생성하지 않았습니다.',
    if (invalidSources.isNotEmpty)
      '비정상 geometry ${invalidSources.length}건을 제외했습니다: '
          '${invalidSources.take(5).join(', ')}'
          '${invalidSources.length > 5 ? ' 외 ${invalidSources.length - 5}건' : ''}',
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
