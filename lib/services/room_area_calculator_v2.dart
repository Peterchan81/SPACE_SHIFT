import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';

/// SpaceScene V2 — 면적 재정의(WO 5번): 면적은 반드시 실제 CAD
/// geometry(room polygon)에서 mm 단위로 계산한다. 원본 이미지의 픽셀
/// 면적 비율([CadRoom.areaNormalized])을 그대로 쓰지 않고, polygon 자체를
/// mm 좌표로 옮긴 뒤 신발끈 공식(shoelace)으로 다시 계산한다 — 픽셀
/// 면적 비율과 "실제 polygon 재계산" 면적은 폴리곤이 오목하거나 정리
/// (dedupe/collinear 제거)가 필요한 경우 미묘하게 달라질 수 있는데, 이제
/// 후자만 신뢰한다.

/// [polygon]에서 연속 중복점을 제거한다(같은 점이 반복되면 삼각분할이
/// 0-넓이 삼각형을 만든다).
List<Point2> _dedupeConsecutive(List<Point2> polygon) {
  if (polygon.isEmpty) return polygon;
  const eps = 1e-9;
  final out = <Point2>[];
  for (final p in polygon) {
    if (out.isEmpty ||
        (out.last.x - p.x).abs() > eps ||
        (out.last.y - p.y).abs() > eps) {
      out.add(p);
    }
  }
  if (out.length > 1 &&
      (out.first.x - out.last.x).abs() < eps &&
      (out.first.y - out.last.y).abs() < eps) {
    out.removeLast();
  }
  return out;
}

/// 세 점이 거의 일직선이면 가운데 점을 제거한다(collinear 정리) — ear
/// clipping 자체는 collinear에서도 동작하지만, 0-넓이에 가까운 ear를
/// 만들어 불필요하게 실패하는 경우를 줄인다.
List<Point2> _removeCollinear(List<Point2> polygon) {
  final n = polygon.length;
  if (n < 3) return polygon;
  final out = <Point2>[];
  for (var i = 0; i < n; i++) {
    final prev = polygon[(i - 1 + n) % n];
    final cur = polygon[i];
    final next = polygon[(i + 1) % n];
    final cross =
        (cur.x - prev.x) * (next.y - prev.y) -
        (cur.y - prev.y) * (next.x - prev.x);
    if (cross.abs() > 1e-12) out.add(cur);
  }
  return out.length >= 3 ? out : polygon;
}

/// 단순 다각형인지(자기교차 없음) 확인한다 — [space_scene_builder.dart]의
/// `_isSelfIntersecting`과 같은 판정이지만, V2는 그 파일에 의존하지 않고
/// 독립적으로 갖는다(WO — "기존 3D 구현에 patch를 추가하지 않는다",
/// 병렬 pipeline은 서로의 내부 함수를 공유하지 않는다).
bool isSimplePolygonV2(List<Point2> polygon) {
  final n = polygon.length;
  if (n < 3) return false;
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
      if (j == (i + 1) % n || (j + 1) % n == i) continue;
      if (segmentsIntersect(a1, a2, polygon[j], polygon[(j + 1) % n])) {
        return false;
      }
    }
  }
  return true;
}

/// [polygon](정규화 좌표)을 정리(dedupe + collinear 제거)한 결과 —
/// 삼각분할/면적 계산 전에 항상 이 함수를 먼저 거친다(WO 12번, "floor
/// polygon: duplicate point 제거 / collinear 정리 / self-intersection
/// 검증 / winding 정규화 / ear clipping").
List<Point2> cleanPolygonV2(List<Point2> polygon) {
  return _removeCollinear(_dedupeConsecutive(polygon));
}

/// 신발끈 공식으로 [polygon](정규화 좌표)의 signed area를 구해 winding을
/// 판정한다. 양수면 CCW(수학적 y-up 기준) — 이 프로젝트 좌표는 y가
/// 아래로 갈수록 커지는 이미지 좌표라 화면상으로는 CW로 보이지만, 셰이더/
/// 삼각분할은 부호만 일관되면 되므로 이름은 신경 쓰지 않는다.
double _signedArea(List<Point2> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum / 2;
}

/// V2 전용 ear-clipping — [space_scene_builder.dart]의 구현과 알고리즘은
/// 같지만(표준 ear-clipping이라 다르게 구현할 이유가 없다) 독립적으로
/// 존재해 V1 파일을 import하지 않는다. winding을 먼저 CCW로 정규화한 뒤
/// (WO 12번 "winding 정규화") 항상 같은 부호 규칙으로 convex corner를
/// 판정한다.
List<List<int>> earClipTriangulateV2(List<Point2> polygon) {
  final n = polygon.length;
  if (n < 3) return const [];
  if (n == 3) {
    return [
      [0, 1, 2],
    ];
  }
  if (!isSimplePolygonV2(polygon)) return const [];

  final ccw = _signedArea(polygon) > 0;
  final pts = ccw ? polygon : polygon.reversed.toList();
  // reversed 다각형에서도 원래 인덱스를 되돌릴 수 있도록 매핑을 둔다.
  final originalIndex = ccw
      ? List<int>.generate(n, (i) => i)
      : List<int>.generate(n, (i) => n - 1 - i);

  bool isConvexCorner(Point2 a, Point2 b, Point2 c) {
    final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    return cross > 0;
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
      final a = pts[prevI], b = pts[curI], c = pts[nextI];
      if (!isConvexCorner(a, b, c)) continue;

      var containsOther = false;
      for (final idx in indices) {
        if (idx == prevI || idx == curI || idx == nextI) continue;
        if (pointInTriangle(pts[idx], a, b, c)) {
          containsOther = true;
          break;
        }
      }
      if (containsOther) continue;

      triangles.add([
        originalIndex[prevI],
        originalIndex[curI],
        originalIndex[nextI],
      ]);
      indices.removeAt(i);
      earFound = true;
      break;
    }
    if (!earFound) break;
  }
  if (indices.length == 3) {
    triangles.add([
      originalIndex[indices[0]],
      originalIndex[indices[1]],
      originalIndex[indices[2]],
    ]);
  }
  return triangles;
}

/// [plan]의 정규화 polygon 한 점을 mm world 좌표(Y=0 평면)로 옮긴다 —
/// WO 21번 좌표계 통일: 2D x → 3D X, 2D y → 3D Z.
Vector3 pointToMm(Point2 p, CadFloorPlan plan, FloorPlanScale scale) {
  return Vector3(
    p.x * plan.sourceWidthPx * scale.mmPerPixel,
    0,
    p.y * plan.sourceHeightPx * scale.mmPerPixel,
  );
}

/// mm 좌표 polygon의 면적(m²) — XZ 평면 신발끈 공식.
double polygonAreaM2(List<Vector3> polygonMm) {
  var sum = 0.0;
  for (var i = 0; i < polygonMm.length; i++) {
    final a = polygonMm[i];
    final b = polygonMm[(i + 1) % polygonMm.length];
    sum += a.x * b.z - b.x * a.z;
  }
  return sum.abs() / 2 / 1e6;
}

Vector3 polygonCentroidMm(List<Vector3> polygonMm) {
  var x = 0.0, z = 0.0;
  for (final p in polygonMm) {
    x += p.x;
    z += p.z;
  }
  final n = polygonMm.length;
  return Vector3(x / n, 0, z / n);
}

/// room false-positive 필터(WO 6번)가 어떤 구조적 문제로 이 공간을
/// 전체 합계에서 제외했는지 — 실제 화면에는 짧은 한글 이유로 노출된다.
/// 빈 문자열이면(=null) 제외되지 않았다는 뜻이다.
///
/// 절대 room 자체를 목록/3D에서 삭제하지 않는다(WO 6번 "confidence 기반
/// 처리, 임의 삭제 금지") — 오직 [RoomAreaV2.includedInTotal]과
/// [RoomAreaV2.confidence]만 낮춘다. 작은 화장실/팬트리처럼 실제로
/// 존재하는 좁은 공간까지 걸러내지 않도록 임계값을 보수적으로 낮게
/// 잡는다.
const double kMinRoomAreaM2 = 0.36; // 0.6m x 0.6m 미만은 방으로 보기 어렵다.
const double kMinRoomDimensionM = 0.28; // 벽 틈/샤프트 폭 수준.
const double kExtremeAspectRatio = 12.0;
const double kDuplicateOverlapRatio = 0.6;

@immutable
class RoomAreaV2 {
  const RoomAreaV2({
    required this.id,
    required this.polygonMm,
    required this.centroidMm,
    required this.areaM2,
    required this.areaPyeong,
    required this.includedInTotal,
    required this.confidence,
    required this.scaleSource,
    this.exclusionReason,
  });

  final String id;
  final List<Vector3> polygonMm;
  final Vector3 centroidMm;
  final double areaM2;
  final double areaPyeong;
  final bool includedInTotal;
  final double confidence;
  final ScaleSource scaleSource;

  /// null이면 정상 포함 — 아니면 왜 [includedInTotal]이 false인지(WO
  /// 6번, 사용자에게 투명하게 이유를 남긴다).
  final String? exclusionReason;
}

@immutable
class RoomAreaSummaryV2 {
  const RoomAreaSummaryV2({
    required this.rooms,
    required this.totalAreaM2,
    required this.totalAreaPyeong,
  });

  final List<RoomAreaV2> rooms;
  final double totalAreaM2;
  final double totalAreaPyeong;
}

/// 정리된 polygon의 bounding box 크기(mm) — 최소 폭/높이 판정에 쓴다.
(double widthMm, double heightMm) _boundingSizeMm(List<Vector3> polygonMm) {
  var minX = double.infinity, maxX = -double.infinity;
  var minZ = double.infinity, maxZ = -double.infinity;
  for (final p in polygonMm) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.z < minZ) minZ = p.z;
    if (p.z > maxZ) maxZ = p.z;
  }
  return (maxX - minX, maxZ - minZ);
}

/// 두 polygon의 bounding box 기준 대략적인 겹침 비율(0~1, 작은 쪽 면적
/// 대비) — 정확한 polygon boolean 교차가 아니라 저비용 근사치다. 실제
/// 겹침 후보를 놓치지 않는(false negative를 줄이는) 쪽으로 넉넉하게
/// 잡고, 최종 판단은 면적 임계값과 함께 쓰인다.
double _approxOverlapRatio(List<Vector3> a, List<Vector3> b) {
  var aMinX = double.infinity, aMaxX = -double.infinity;
  var aMinZ = double.infinity, aMaxZ = -double.infinity;
  for (final p in a) {
    aMinX = math.min(aMinX, p.x);
    aMaxX = math.max(aMaxX, p.x);
    aMinZ = math.min(aMinZ, p.z);
    aMaxZ = math.max(aMaxZ, p.z);
  }
  var bMinX = double.infinity, bMaxX = -double.infinity;
  var bMinZ = double.infinity, bMaxZ = -double.infinity;
  for (final p in b) {
    bMinX = math.min(bMinX, p.x);
    bMaxX = math.max(bMaxX, p.x);
    bMinZ = math.min(bMinZ, p.z);
    bMaxZ = math.max(bMaxZ, p.z);
  }
  final ix = math.max(0.0, math.min(aMaxX, bMaxX) - math.max(aMinX, bMinX));
  final iz = math.max(0.0, math.min(aMaxZ, bMaxZ) - math.max(aMinZ, bMinZ));
  final interArea = ix * iz;
  if (interArea <= 0) return 0;
  final aArea = (aMaxX - aMinX) * (aMaxZ - aMinZ);
  final bArea = (bMaxX - bMinX) * (bMaxZ - bMinZ);
  final smaller = math.min(aArea, bArea);
  if (smaller <= 0) return 0;
  return interArea / smaller;
}

/// [plan]의 모든 room을 실제 mm 단위 polygon으로 재계산하고(WO 5번),
/// false-positive 후보를 구조적 기준으로만 표시한다(WO 6번). room을
/// 목록/3D에서 삭제하지 않는다 — 오직 합계 포함 여부와 신뢰도만 바꾼다.
RoomAreaSummaryV2 computeRoomAreasV2({
  required CadFloorPlan plan,
  required FloorPlanScale scale,
}) {
  final n = plan.rooms.length;
  final results = List<RoomAreaV2?>.filled(n, null);
  final validPolygons = <int, List<Vector3>>{};

  for (var i = 0; i < n; i++) {
    final room = plan.rooms[i];
    final cleaned = cleanPolygonV2(room.polygon);
    if (cleaned.length < 3 || !isSimplePolygonV2(cleaned)) {
      results[i] = RoomAreaV2(
        id: room.id,
        polygonMm: const [],
        centroidMm: Vector3.zero(),
        areaM2: 0,
        areaPyeong: 0,
        includedInTotal: false,
        confidence: 0,
        scaleSource: scale.source,
        exclusionReason: '폴리곤이 유효하지 않음(점 부족 또는 자기교차)',
      );
      continue;
    }
    validPolygons[i] = [for (final p in cleaned) pointToMm(p, plan, scale)];
  }

  // bounding-box 근사 중복 검사는 유효한 polygon끼리만 수행한다.
  final excludedAsDuplicate = <int>{};
  final validIndices = validPolygons.keys.toList();
  for (var a = 0; a < validIndices.length; a++) {
    for (var b = a + 1; b < validIndices.length; b++) {
      final ia = validIndices[a], ib = validIndices[b];
      final overlap = _approxOverlapRatio(
        validPolygons[ia]!,
        validPolygons[ib]!,
      );
      if (overlap >= kDuplicateOverlapRatio) {
        final areaA = polygonAreaM2(validPolygons[ia]!);
        final areaB = polygonAreaM2(validPolygons[ib]!);
        final confA = plan.rooms[ia].confidence;
        final confB = plan.rooms[ib].confidence;
        // 면적이 크거나(진짜 방일 가능성), 같은 면적이면 confidence가 더
        // 높은 쪽을 남긴다.
        final keepA = areaA != areaB ? areaA > areaB : confA >= confB;
        excludedAsDuplicate.add(keepA ? ib : ia);
      }
    }
  }

  var totalM2 = 0.0;
  for (var i = 0; i < n; i++) {
    final polygonMm = validPolygons[i];
    if (polygonMm == null) continue; // invalid — 위에서 이미 채움.

    final room = plan.rooms[i];
    final areaM2 = polygonAreaM2(polygonMm);
    final (widthMm, heightMm) = _boundingSizeMm(polygonMm);
    final widthM = widthMm / 1000, heightM = heightMm / 1000;
    final longer = math.max(widthM, heightM);
    final shorter = math.max(0.001, math.min(widthM, heightM));
    final aspect = longer / shorter;

    String? reason;
    var confidence = room.confidence;
    if (areaM2 < kMinRoomAreaM2) {
      reason = '면적이 너무 작음(${areaM2.toStringAsFixed(2)}㎡) — 벽 틈/구조 노이즈일 수 있음';
    } else if (shorter < kMinRoomDimensionM) {
      reason =
          '폭이 비정상적으로 좁음(${(shorter * 100).toStringAsFixed(0)}cm) — 틈/샤프트일 수 있음';
    } else if (aspect > kExtremeAspectRatio && areaM2 < 3.0) {
      reason = '비정상적으로 가늘고 긴 형태(가로세로비 ${aspect.toStringAsFixed(1)}:1)';
    } else if (excludedAsDuplicate.contains(i)) {
      reason = '다른 공간과 크게 겹침(중복 후보)';
    }

    final included = reason == null;
    if (reason != null) confidence = math.min(confidence, 0.35);
    if (included) totalM2 += areaM2;

    results[i] = RoomAreaV2(
      id: room.id,
      polygonMm: polygonMm,
      centroidMm: polygonCentroidMm(polygonMm),
      areaM2: areaM2,
      areaPyeong: areaM2 / kSquareMetersPerPyeong,
      includedInTotal: included,
      confidence: confidence,
      scaleSource: scale.source,
      exclusionReason: reason,
    );
  }

  return RoomAreaSummaryV2(
    rooms: [for (final r in results) r!],
    totalAreaM2: totalM2,
    totalAreaPyeong: totalM2 / kSquareMetersPerPyeong,
  );
}
