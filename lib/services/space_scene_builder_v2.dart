import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart' show OpeningType, Point2;
import '../models/space_scene_v2.dart';
import '../models/ss_spatial_model.dart' show SSRoomType;
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

// GPT FLOORPLAN → STRUCTURED 2D → REAL 3D ISO FLOW WO §11 — V1 기본 재질.
// 고정된 최종 결과가 아니라 DEFAULT다: [CadWall.materialOverride]/
// [CadRoom.materialOverride](사용자가 "작업/재질/마감재"에서 고른 색)가
// 있으면 이 값보다 항상 우선한다(아래 [_wallColor]/[_floorColor] 참고).
// PC2 FINAL ISO VISUAL PASS — "회백색 CAD extrusion"처럼 벽/바닥/벽
// 상단이 서로 섞이던 문제를 없애기 위해, 외벽/내벽을 하나의 뚜렷한
// warm white로 통일하고(외벽만 살짝 더 짙게 구분하던 이전 베이지색은
// 제거 — 이번 시각 언어의 목표는 "벽=흰색"이지 "외벽/내벽 구분"이
// 아니다) 바닥 우드 톤을 흰 벽과 명확히 대비되도록 더 진하게 만든다.
const Color _exteriorWallColorV2 = Color(0xFFF5F4F0);
const Color _interiorWallColorV2 = Color(0xFFF5F4F0); // 일반 내부 벽: warm white.
const Color _bathroomWallColorV2 = Color(0xFFD8E2E4); // bathroom wall: tile.
const Color _woodFloorColorV2 = Color(0xFFC7A06C); // 일반 공간 바닥: 흰 벽과 뚜렷이 대비되는 light wood.
const Color _bathroomFloorColorV2 = Color(0xFFD3DEE1); // bathroom floor: tile.

// WO092 §4 — 천장 기본색(백색 페인트). 방 종류와 무관하게 항상 이
// 하나의 기본값에서 시작한다(§4 "천장은 구조상 존재하도록 한다"가
// "천장 재질을 방 종류로 자동 분기한다"를 요구하지는 않는다 — 벽/바닥과
// 달리 천장은 욕실이라고 타일로 바뀌어야 한다는 요구가 없었다).
const Color _ceilingColorV2 = Color(0xFFF5F3EE);

/// WO099 §6 — 벽의 옆면(실내 마감)과 윗면(단면/천장 접합부)을 시각적으로
/// 구분한다. 별도 재질 시스템을 새로 만들지 않고, 옆면 색을 살짝
/// 어둡게 섞는 고정 비율 하나로 "단면은 마감이 아니라 두께가 잘린
/// 부분"이라는 인상을 준다 — 방 종류/벽 종류에 관계없이 항상 같은
/// 비율로만 적용되는 단순 규칙이라 wall-hide류 알고리즘과 무관하다.
///
/// PC2 FINAL ISO VISUAL PASS — 기본 Dollhouse bird's-eye 카메라는 벽
/// 옆면보다 이 top face를 훨씬 많이 보여준다. WO099의 16% 어둡게는
/// 벽이 아직 베이지색이던 시절 값이라, 벽을 warm white로 바꾼 지금
/// 그대로 두면 top face가 실측 화면에서 "흰 벽"이 아니라 "회색
/// 지붕처럼" 보인다(§3.A가 명시적으로 피하라는 바로 그 모습). 그래서
/// top face 어둡게를 최소치로 줄인다 — 벽 구조 자체는 §3.C의 검정
/// architectural edge line이 표현하고, 이 색 차이는 아주 옅은 깊이
/// 힌트로만 남긴다.
Color _wallTopColor(Color base) {
  const darken = 0.04;
  return Color.fromARGB(
    255,
    (base.r * 255 * (1 - darken)).round().clamp(0, 255),
    (base.g * 255 * (1 - darken)).round().clamp(0, 255),
    (base.b * 255 * (1 - darken)).round().clamp(0, 255),
  );
}

// WO099 §8 — Phase A 최소 가구 3종(sofa/table/bed) 색상. 최종 마감재
// 추천이 아니라 "여기 가구가 있다"를 즉시 알아볼 수 있는 임시 톤이다.
const Color _furnitureSofaColor = Color(0xFF8C6B52);
const Color _furnitureSofaAccentColor = Color(0xFF6E5340);
const Color _furnitureTableTopColor = Color(0xFF7A5B3E);
const Color _furnitureTableLegColor = Color(0xFF4A3826);
const Color _furnitureBedFrameColor = Color(0xFF6E5340);
const Color _furnitureBedMattressColor = Color(0xFFEDE6DA);

/// WO097 — door opening을 실제 벽 geometry에서 잘라낼 때 쓰는 문 높이
/// 가정. [CadOpening]은 문의 실측 "폭"만 가지고 있고(evidence 기반,
/// [CadFloorPlan.realMmForNormalizedLength]로 실제 mm 변환), 높이는 어느
/// 분석 단계에서도 측정되지 않는다 — 그래서 [kAssumedDoorWidthMm]
/// (cad_floor_plan.dart, 축척 역산 전용)와 같은 성격의 "실측이 아닌 통상
/// 가정값"이 하나 더 필요하다. 국내 아파트 실내문의 통상 문틀 높이
/// (약 2000mm) 기준 — 기본 천장고([kDefaultCeilingHeightMm] = 2400mm)
/// 아래에서 문 위 상인방(§WO097 요구사항 5 "문 위쪽 벽은 유지")이 항상
/// 자연스러운 두께로 남는다.
const double kAssumedDoorOpeningHeightMm = 2000;

/// WO102 §5 — window sill/head 높이 가정. [CadOpening](window)에는 폭만
/// 있고 수직 위치(sill/head)는 어떤 분석 단계에서도 측정되지 않는다 —
/// [kAssumedDoorOpeningHeightMm]와 같은 성격의 "실측이 아닌 통상 가정값"
/// 이다. 국내 아파트 거실/침실 창 통상 치수(바닥에서 창턱까지 약
/// 900mm, 창 높이 약 1200mm) 기준. 실제 sill/head 실측 데이터가 들어오면
/// (§5 "향후 SS CAD TEST에서 실제 데이터가 들어오면 교체") 이 두 상수
/// 대신 그 값을 써야 한다 — 지금은 이 두 상수를 참조하는 자리가 이
/// 파일의 window 처리 로직 한 곳뿐이라 교체 지점이 명확하다.
const double kAssumedWindowSillHeightMm = 900;
const double kAssumedWindowHeightMm = 1200;

/// WO102 §5 — window frame이 glass보다 얼마나 더 넓게 보이는지(테두리
/// 두께). frame/glass 모두 opening 전체를 채우는 상자 하나씩으로
/// 만들고, glass만 사방으로 이 값만큼 더 작게 안쪽에 넣는다(§8 가구의
/// frame+mattress 인셋 패턴과 같은 방식 — 새 geometry 원리를 만들지
/// 않고 이미 검증된 [addWallBox]를 그대로 재사용한다).
const double kWindowFrameMarginMm = 60;

const Color _windowFrameColor = Color(0xFF3A3A3A); // charcoal.
// WO102 §5 — 실제 유리 투명도(alpha blending)는 도입하지 않는다: three_js
// 투명 재질은 렌더 순서(depth sorting)를 새로 맞춰야 해서 "렌더링 튜닝
// 반복 금지"(§0/§16)에 해당하는 위험을 새로 만든다. 대신 불투명한 밝은
// 청회색만으로 "여기는 벽이 아니라 유리다"를 색으로 충분히 구분한다.
const Color _windowGlassColor = Color(0xFFAEC6D6);

/// 개구부 없는 벽과 동일한 경계 지점([RawRunBand] 아님 — CAD 구조).
/// [t0]/[t1]은 벽 중심선(start=0, end=1) 위 fraction이다.
typedef _WallAlongInterval = ({double t0, double t1});

/// WO102 §4/§5 — 벽 하나에 실제로 뚫린 opening 구간 하나(door 또는
/// window). [gapBottomMm]/[gapTopMm]는 바닥 기준 절대 mm다 — door는
/// gapBottomMm=0(바닥까지 완전 개방), window는 gapBottomMm=sill height로
/// 표현해, "문(바닥부터)"과 "창(허리 높이부터)"을 같은 벽-절단 로직
/// 하나로 다룬다(중복 코드를 만들지 않는다, §3 code audit 결론).
typedef _WallOpeningSpan = ({double t0, double t1, double gapBottomMm, double gapTopMm});

/// [wall] 중심선(start→end, mm 2D) 위로 [point]를 투영해 along-fraction
/// t를 구한다(t=0 at start, t=1 at end). 벽 길이가 0이면 null. 이미지
/// 원본이 정사각형이 아닐 수 있어([CadFloorPlan.sourceWidthPx] !=
/// [sourceHeightPx]) x/y가 서로 다른 배율로 mm 변환되므로, 정규화 좌표가
/// 아니라 항상 mm 변환 후(anisotropic 배율이 반영된 실제 공간)에
/// 투영해야 정확하다.
double? _projectAlongWallT({
  required Point2 wallStart,
  required Point2 wallEnd,
  required Point2 point,
  required CadFloorPlan plan,
  required FloorPlanScale scale,
}) {
  final a = pointToMm(wallStart, plan, scale);
  final b = pointToMm(wallEnd, plan, scale);
  final p = pointToMm(point, plan, scale);
  final dx = b.x - a.x, dz = b.z - a.z;
  final lenSq = dx * dx + dz * dz;
  if (lenSq <= 0) return null;
  return ((p.x - a.x) * dx + (p.z - a.z) * dz) / lenSq;
}

/// WO097 §2/§7(WO102 §5에서 window에도 재사용) — [opening]이 [wall] 위
/// 어디에서 벽을 가로지르는지 along-fraction 구간으로 계산한다.
/// [wall.boundaryPolygon] 범위를 벗어나 거의 전부 밀려나거나(데이터
/// 불일치로 실제로는 이 벽에 속하지 않는 경우), 폭이 0 이하이거나, 벽
/// 길이 자체가 0이면 null — 존재하지 않는 구조를 지어내지 않기 위해
/// 조용히 제외한다(호출부가 그 이유를 정직하게 카운트해 warnings로
/// 알린다). door/window 모두 "중심점 + 폭"이라는 같은 모양의 evidence를
/// 쓰므로 opening 종류와 무관한 이 계산 하나만 있으면 된다(§3 code
/// audit — window도 position/width 데이터 자체는 CadOpening에 이미
/// 있다).
_WallAlongInterval? _openingIntervalOnWall({
  required CadWall wall,
  required CadOpening opening,
  required CadFloorPlan plan,
  required FloorPlanScale scale,
}) {
  final wallLengthMm = plan.realMmBetween(wall.start, wall.end, scale);
  if (wallLengthMm == null || wallLengthMm <= 0) return null;
  final t = _projectAlongWallT(
    wallStart: wall.start,
    wallEnd: wall.end,
    point: opening.center,
    plan: plan,
    scale: scale,
  );
  if (t == null) return null;
  final widthMm = plan.realMmForNormalizedLength(opening.widthNormalized, scale);
  if (widthMm == null || widthMm <= 0) return null;

  final centerAlongMm = t * wallLengthMm;
  final halfWidthMm = widthMm / 2;
  final startAlongMm = (centerAlongMm - halfWidthMm).clamp(0.0, wallLengthMm);
  final endAlongMm = (centerAlongMm + halfWidthMm).clamp(0.0, wallLengthMm);
  // 벽 범위로 clamp한 뒤 남은 폭이 실질적인 문 하나로 보기에 너무
  // 작으면(예: 문 중심이 벽 끝 훨씬 밖으로 투영되는 wallId 오연결) 실제
  // evidence로 보지 않는다 — 정상적인 어떤 문도 몇 cm보다는 넓다.
  const minMeaningfulOpeningMm = 50.0;
  if (endAlongMm - startAlongMm < minMeaningfulOpeningMm) return null;
  return (t0: startAlongMm / wallLengthMm, t1: endAlongMm / wallLengthMm);
}

/// 겹치거나 맞닿은 구간을 하나로 합친다(한 벽에 문이 여러 개 겹쳐
/// 잡히는 드문 경우, 서로 다른 header/segment geometry가 겹치지 않게
/// 한다).
List<_WallAlongInterval> _mergeAlongIntervals(List<_WallAlongInterval> intervals) {
  if (intervals.isEmpty) return const [];
  final sorted = [...intervals]..sort((a, b) => a.t0.compareTo(b.t0));
  final merged = <_WallAlongInterval>[];
  var current = sorted.first;
  for (final next in sorted.skip(1)) {
    if (next.t0 <= current.t1) {
      current = (t0: current.t0, t1: math.max(current.t1, next.t1));
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}

/// [wall]의 실제 렌더 색 — 사용자 override가 있으면 항상 우선한다. 없으면
/// 외벽은 고정색, 내벽은 "이 벽이 욕실과 맞닿아 있는가"([_wallTouchesBathroom])
/// 로 white/tile을 가른다.
Color _wallColor(CadWall wall, List<CadRoom> rooms) {
  final override = wall.materialOverride;
  if (override != null) return override;
  if (wall.wallType == CadWallType.exterior) return _exteriorWallColorV2;
  return _wallTouchesBathroom(wall, rooms) ? _bathroomWallColorV2 : _interiorWallColorV2;
}

/// [room]의 실제 렌더 바닥색 — 사용자 override가 있으면 항상 우선한다.
/// 없으면 [CadRoom.roomType]으로 우드/타일을 가른다.
Color _floorColor(CadRoom room) {
  return room.materialOverride ??
      (room.roomType == SSRoomType.bathroom ? _bathroomFloorColorV2 : _woodFloorColorV2);
}

/// [room]의 실제 렌더 천장색 — 사용자 override가 있으면 항상 우선한다.
/// 없으면 항상 [_ceilingColorV2](§4).
Color _ceilingColor(CadRoom room) => room.ceilingMaterialOverride ?? _ceilingColorV2;

/// [wall]의 중심점에서 벽에 수직인 양쪽으로 살짝 들어간 두 점 중 하나라도
/// 욕실 [CadRoom] 폴리곤 안에 있으면 true. 벽 자체는 어느 방에 속하는지
/// 직접 알지 못하므로(WallEdge/adjacency 데이터가 아직 없음), 기존
/// [CadRoom.containsPoint]를 재사용한 기하학적 근접 판정으로 실제
/// renderer에 반영 가능한 최소 구현을 만든다 — 가짜로 항상 false를
/// 반환하지 않는다.
bool _wallTouchesBathroom(CadWall wall, List<CadRoom> rooms) {
  final bathrooms = rooms.where((r) => r.roomType == SSRoomType.bathroom);
  if (bathrooms.isEmpty) return false;
  final dx = wall.end.x - wall.start.x;
  final dy = wall.end.y - wall.start.y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return false;
  final midX = (wall.start.x + wall.end.x) / 2;
  final midY = (wall.start.y + wall.end.y) / 2;
  final nx = -dy / len;
  final ny = dx / len;
  final probe = wall.thicknessNormalized + 0.01;
  final sideA = Point2(midX + nx * probe, midY + ny * probe);
  final sideB = Point2(midX - nx * probe, midY - ny * probe);
  return bathrooms.any((r) => r.containsPoint(sideA) || r.containsPoint(sideB));
}

bool _isFiniteVec3(Vector3 v) => v.x.isFinite && v.y.isFinite && v.z.isFinite;

/// WO094 PC1 실기 재검증 FAIL 구조 조사 — 실제 분석된 방 polygon이
/// 자기교차 등으로 [computeRoomAreasV2]/[earClipTriangulateV2]를 통과하지
/// 못하면 그 방은 지금까지 바닥/천장이 통째로 생성되지 않았다(경고도
/// 없이 조용히 스킵됨). 벽은 [CadWall]에서 방과 무관하게 독립적으로
/// 생성되므로 그대로 남아, 실기에서 "검정 배경 + 벽 골격만 남고 방
/// 내부가 안 보임"으로 보이는 것과 정확히 일치한다.
///
/// 방을 목록에서 절대 삭제하지 않는 것(§6 "confidence 기반 처리, 임의
/// 삭제 금지")과 같은 원칙으로, 바닥도 포기하는 대신 원본 점들의 convex
/// hull로 근사한다 — hull은 실제로 관측된 점만으로 계산되므로 "존재하지
/// 않는 구조를 지어내는 것"이 아니다(오목한 부분이 뭉개지는 근사치임을
/// [SpaceSceneV2.warnings]로 정직하게 알린다). Andrew's monotone chain,
/// O(n log n), 입력 winding에 무관하게 항상 유효한 단순 다각형을 만든다.
List<Vector3> _convexHullXZ(List<Vector3> points) {
  final unique = <String, Vector3>{};
  for (final p in points) {
    unique['${p.x.toStringAsFixed(3)}:${p.z.toStringAsFixed(3)}'] = p;
  }
  final sorted = unique.values.toList()
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.z.compareTo(b.z));
  if (sorted.length < 3) return const [];

  double cross(Vector3 o, Vector3 a, Vector3 b) =>
      (a.x - o.x) * (b.z - o.z) - (a.z - o.z) * (b.x - o.x);

  final lower = <Vector3>[];
  for (final p in sorted) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Vector3>[];
  for (final p in sorted.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  final hull = [...lower, ...upper];
  return hull.length >= 3 ? hull : const [];
}

/// convex 다각형(꼭짓점 [n]개, 순서대로 볼록함이 보장됨) 전용 fan
/// triangulation — [_convexHullXZ]의 결과 전용이라 [earClipTriangulateV2]
/// 같은 오목 판정이 필요 없다.
List<List<int>> _fanTriangulateConvex(int n) {
  if (n < 3) return const [];
  return [for (var i = 1; i < n - 1; i++) [0, i, i + 1]];
}

/// [buildSpaceSceneV2] 내부의 `addQuad` 클로저 시그니처 — 가구 builder들이
/// 그 클로저를 그대로 전달받아 쓰도록 이름을 붙여 둔다(NaN/거대 edge
/// 검증을 가구 geometry에도 동일하게 적용하기 위해 새로 만들지 않고
/// 재사용한다).
typedef _AddQuadFn = void Function(
  List<SpaceTriangleV2> into,
  Vector3 p0,
  Vector3 p1,
  Vector3 p2,
  Vector3 p3,
  Color color,
  String debugSourceLabel,
);

/// [polygonMm]의 XZ 평면 bounding box 크기(mm) — 가구를 방 크기에 맞춰
/// 축소할지 판단하는 데만 쓴다(정밀한 방 형태 분석이 아니라 "가구가
/// 벽을 심하게 뚫고 나가지 않게"하는 최소한의 안전장치).
(double widthMm, double depthMm) _boundingSizeXZ(List<Vector3> polygonMm) {
  if (polygonMm.isEmpty) return (double.infinity, double.infinity);
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

/// [nominalWidthMm]/[nominalDepthMm] 크기의 가구가 [roomWidthMm]/
/// [roomDepthMm] 방에 비해 너무 크면(방 크기의 70% 초과) 균일하게
/// 줄이는 배율. 방 형태를 실제로 분석하지 않는 최소 안전장치일 뿐,
/// 정교한 배치 알고리즘이 아니다(§8 — 이번 WO 범위 아님).
double _furnitureFitScale({
  required double roomWidthMm,
  required double roomDepthMm,
  required double nominalWidthMm,
  required double nominalDepthMm,
}) {
  if (!roomWidthMm.isFinite || !roomDepthMm.isFinite) return 1.0;
  const maxFraction = 0.7;
  final scaleW = nominalWidthMm > 0 ? (roomWidthMm * maxFraction) / nominalWidthMm : 1.0;
  final scaleD = nominalDepthMm > 0 ? (roomDepthMm * maxFraction) / nominalDepthMm : 1.0;
  return math.min(1.0, math.min(scaleW, scaleD));
}

/// 축정렬 상자 하나(top/bottom/4측면, 6면 12 triangle) — 가구는 실제
/// CAD 벽처럼 얇은 shell일 필요가 없어 가장 단순한 닫힌 형태로 만든다.
void _addFurnitureBox(
  List<SpaceTriangleV2> triangles,
  _AddQuadFn addQuad,
  Vector3 min,
  Vector3 max,
  Color color,
  String debugSourceLabel,
) {
  final p000 = Vector3(min.x, min.y, min.z);
  final p100 = Vector3(max.x, min.y, min.z);
  final p110 = Vector3(max.x, max.y, min.z);
  final p010 = Vector3(min.x, max.y, min.z);
  final p001 = Vector3(min.x, min.y, max.z);
  final p101 = Vector3(max.x, min.y, max.z);
  final p111 = Vector3(max.x, max.y, max.z);
  final p011 = Vector3(min.x, max.y, max.z);
  addQuad(triangles, p000, p100, p101, p001, color, debugSourceLabel);
  addQuad(triangles, p010, p011, p111, p110, color, debugSourceLabel);
  addQuad(triangles, p000, p001, p011, p010, color, debugSourceLabel);
  addQuad(triangles, p100, p110, p111, p101, color, debugSourceLabel);
  addQuad(triangles, p000, p010, p110, p100, color, debugSourceLabel);
  addQuad(triangles, p001, p101, p111, p011, color, debugSourceLabel);
}

/// WO099 §8 — bed: box(frame) + box(mattress). 실측 표준 침대 크기(퀸,
/// 1600x2000mm)를 기준값으로 쓰고, 방이 작으면 [_furnitureFitScale]로
/// 줄인다.
List<SpaceTriangleV2> _bedTriangles(
  _AddQuadFn addQuad,
  Vector3 centerMm,
  (double widthMm, double depthMm) roomSize,
) {
  const nominalW = 1600.0, nominalD = 2000.0;
  final s = _furnitureFitScale(
    roomWidthMm: roomSize.$1,
    roomDepthMm: roomSize.$2,
    nominalWidthMm: nominalW,
    nominalDepthMm: nominalD,
  );
  final halfW = nominalW * s / 2, halfD = nominalD * s / 2;
  const frameH = 300.0, mattressH = 180.0, inset = 60.0;
  final tris = <SpaceTriangleV2>[];
  _addFurnitureBox(
    tris,
    addQuad,
    Vector3(centerMm.x - halfW, 0, centerMm.z - halfD),
    Vector3(centerMm.x + halfW, frameH, centerMm.z + halfD),
    _furnitureBedFrameColor,
    'furniture:bed:frame',
  );
  final insetScaled = inset * s;
  _addFurnitureBox(
    tris,
    addQuad,
    Vector3(centerMm.x - halfW + insetScaled, frameH, centerMm.z - halfD + insetScaled),
    Vector3(centerMm.x + halfW - insetScaled, frameH + mattressH, centerMm.z + halfD - insetScaled),
    _furnitureBedMattressColor,
    'furniture:bed:mattress',
  );
  return tris;
}

/// WO099 §8 — sofa: seat + back + arm(양쪽) box 조합. 실측 표준 3인용
/// 소파 크기(900x1800mm)를 기준값으로 쓴다.
List<SpaceTriangleV2> _sofaTriangles(
  _AddQuadFn addQuad,
  Vector3 centerMm,
  (double widthMm, double depthMm) roomSize,
) {
  const nominalW = 1800.0, nominalD = 900.0;
  final s = _furnitureFitScale(
    roomWidthMm: roomSize.$1,
    roomDepthMm: roomSize.$2,
    nominalWidthMm: nominalW,
    nominalDepthMm: nominalD,
  );
  final halfW = nominalW * s / 2, halfD = nominalD * s / 2;
  final seatH = 420.0 * s, backH = 800.0 * s, armH = 600.0 * s;
  final armW = math.max(60.0, 100.0 * s), backThickness = math.max(60.0, 150.0 * s);
  final tris = <SpaceTriangleV2>[];
  _addFurnitureBox(
    tris,
    addQuad,
    Vector3(centerMm.x - halfW, 0, centerMm.z - halfD),
    Vector3(centerMm.x + halfW, seatH, centerMm.z + halfD),
    _furnitureSofaColor,
    'furniture:sofa:seat',
  );
  _addFurnitureBox(
    tris,
    addQuad,
    Vector3(centerMm.x - halfW, seatH, centerMm.z + halfD - backThickness),
    Vector3(centerMm.x + halfW, backH, centerMm.z + halfD),
    _furnitureSofaAccentColor,
    'furniture:sofa:back',
  );
  _addFurnitureBox(
    tris,
    addQuad,
    Vector3(centerMm.x - halfW, seatH, centerMm.z - halfD),
    Vector3(centerMm.x - halfW + armW, armH, centerMm.z + halfD),
    _furnitureSofaAccentColor,
    'furniture:sofa:armLeft',
  );
  _addFurnitureBox(
    tris,
    addQuad,
    Vector3(centerMm.x + halfW - armW, seatH, centerMm.z - halfD),
    Vector3(centerMm.x + halfW, armH, centerMm.z + halfD),
    _furnitureSofaAccentColor,
    'furniture:sofa:armRight',
  );
  return tris;
}

/// WO099 §8 — table: top + 4 legs box 조합. 실측 표준 식탁 크기
/// (700x1200mm)를 기준값으로 쓴다.
List<SpaceTriangleV2> _tableTriangles(
  _AddQuadFn addQuad,
  Vector3 centerMm,
  (double widthMm, double depthMm) roomSize,
) {
  const nominalW = 1200.0, nominalD = 700.0;
  final s = _furnitureFitScale(
    roomWidthMm: roomSize.$1,
    roomDepthMm: roomSize.$2,
    nominalWidthMm: nominalW,
    nominalDepthMm: nominalD,
  );
  final halfW = nominalW * s / 2, halfD = nominalD * s / 2;
  const topH = 750.0, topThickness = 40.0;
  final legSize = math.max(30.0, 60.0 * s);
  final tris = <SpaceTriangleV2>[];
  _addFurnitureBox(
    tris,
    addQuad,
    Vector3(centerMm.x - halfW, topH - topThickness, centerMm.z - halfD),
    Vector3(centerMm.x + halfW, topH, centerMm.z + halfD),
    _furnitureTableTopColor,
    'furniture:table:top',
  );
  for (final dx in [-1, 1]) {
    for (final dz in [-1, 1]) {
      final legX = centerMm.x + dx * (halfW - legSize / 2);
      final legZ = centerMm.z + dz * (halfD - legSize / 2);
      _addFurnitureBox(
        tris,
        addQuad,
        Vector3(legX - legSize / 2, 0, legZ - legSize / 2),
        Vector3(legX + legSize / 2, topH - topThickness, legZ + legSize / 2),
        _furnitureTableLegColor,
        'furniture:table:leg',
      );
    }
  }
  return tris;
}

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

  /// WO097 — [footprintFull](wall.boundaryPolygon, 순서: [start+n, end+n,
  /// end-n, start-n])의 along-fraction [t0]..[t1] 부분구간을 [yBottom]..
  /// [yTop] 높이의 상자(top면 + 옆면 4개, 필요하면 밑면까지)로 만든다.
  /// [t0]=0,[t1]=1,[yBottom]=0인 호출은 기존(개구부 없는 벽) geometry와
  /// 정확히 동일한 8-vertex/10-triangle 직육면체를 만든다(§7 "opening
  /// 없는 벽은 변경하지 않는다") — top면 다음에 4개 옆면을 순서대로 만드는
  /// 기존 로직 그대로다. [includeBottomCap]은 바닥에 닿지 않는 조각(문
  /// 위 상인방처럼 공중에 떠 있는 부분)의 밑면을 닫을 때만 true로 준다 —
  /// 바닥에 닿는 조각은 기존과 마찬가지로 밑면을 그리지 않는다(안 보이는
  /// 면이라 원래도 없었다).
  void addWallBox(
    List<SpaceTriangleV2> triangles,
    List<Point2> footprintFull,
    double t0,
    double t1,
    double yBottom,
    double yTop,
    Color color,
    String debugSourceLabel, {
    bool includeBottomCap = false,
    // WO099 §6 — top면(단면/천장 접합부)만 [_wallTopColor]로 살짝 어둡게.
    // 생략하면 기존과 동일하게 [color]를 그대로 쓴다(§7 "opening 없는
    // 벽 geometry는 변경하지 않는다"와 같은 원칙 — 호출부가 명시적으로
    // 넘기지 않는 한 이전 동작을 그대로 보존한다).
    Color? topColor,
  }) {
    Point2 lerp(Point2 a, Point2 b, double t) =>
        Point2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
    final sub = [
      lerp(footprintFull[0], footprintFull[1], t0),
      lerp(footprintFull[0], footprintFull[1], t1),
      lerp(footprintFull[3], footprintFull[2], t1),
      lerp(footprintFull[3], footprintFull[2], t0),
    ];
    final footprintMm = [for (final p in sub) pointToMm(p, plan, scale)];
    final bottom = [for (final p in footprintMm) Vector3(p.x, yBottom, p.z)];
    final top = [for (final p in footprintMm) Vector3(p.x, yTop, p.z)];

    addQuad(triangles, top[0], top[1], top[2], top[3], topColor ?? color, debugSourceLabel);
    if (includeBottomCap) {
      addQuad(triangles, bottom[0], bottom[3], bottom[2], bottom[1], color, debugSourceLabel);
    }
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      addQuad(triangles, bottom[i], bottom[j], top[j], top[i], color, debugSourceLabel);
    }
  }

  // ---- 벽(WO 9번 — 항상 CadWall에서 직접 만든 안정적인 직육면체) ----
  // WO097/WO102 — door/window opening 반영 통계(warnings 보고용, §13
  // "무엇을 왜 반영 못했는지 정직하게, 실제 개수로 보고한다").
  final wallIds = plan.walls.map((w) => w.id).toSet();
  var doorsCutTotal = 0;
  var doorsSkippedDegenerate = 0;
  var windowsCutTotal = 0;
  var windowsSkippedDegenerate = 0;
  var windowsSkippedNoRoomForSillHead = 0;
  final wallMeshes = <SpaceWallMeshV2>[];
  final windowMeshes = <SpaceWindowMeshV2>[];
  for (final wall in plan.walls) {
    final heightMm = wall.heightMm ?? ceilingHeightMm;
    if (heightMm <= 0) continue;
    // CadWall.boundaryPolygon이 이미 "두께를 그 축의 정규화 단위로 정확히
    // 오프셋"하도록 검증된 유일한 벽 footprint 계산이라(3D 근본 수정 WO),
    // 여기서 다시 구현하지 않고 CAD source of truth를 그대로 재사용한다
    // (WO 8번 — "3D의 source of truth는 CadWall이다").
    final footprint = wall.boundaryPolygon;
    if (footprint.length != 4) continue;
    // startMm/endMm(아래 SpaceWallMeshV2)은 opening 분할과 무관하게 항상
    // 벽 전체 footprint 기준이어야 한다(§7 — opening 유무와 관계없이
    // 기존과 동일해야 하는 값).
    final fullFootprintMm = [for (final p in footprint) pointToMm(p, plan, scale)];
    final wallLengthMm = plan.realMmBetween(wall.start, wall.end, scale);

    final isExterior = wall.wallType == CadWallType.exterior;
    final color = _wallColor(wall, plan.rooms);
    final triangles = <SpaceTriangleV2>[];

    // WO097 §2/§3(WO102 §5 — window도 같은 방식으로 확장) — 이 벽
    // (wallId)에 연결된 door/window opening만 실제 geometry로 반영한다.
    // unknown-type opening은 이번 WO에서도 다루지 않는다(door/window
    // 어느 쪽인지조차 확정되지 않은 evidence를 지어내지 않는다).
    final doorIntervals = <_WallAlongInterval>[];
    final windowIntervals = <_WallAlongInterval>[];
    for (final opening in plan.openings) {
      if (opening.wallId != wall.id) continue;
      if (opening.type == OpeningType.door) {
        final interval = _openingIntervalOnWall(wall: wall, opening: opening, plan: plan, scale: scale);
        if (interval == null) {
          doorsSkippedDegenerate++;
        } else {
          doorIntervals.add(interval);
        }
      } else if (opening.type == OpeningType.window) {
        final interval = _openingIntervalOnWall(wall: wall, opening: opening, plan: plan, scale: scale);
        if (interval == null) {
          windowsSkippedDegenerate++;
        } else {
          windowIntervals.add(interval);
        }
      }
    }
    final mergedDoors = _mergeAlongIntervals(doorIntervals);
    final mergedWindows = _mergeAlongIntervals(windowIntervals);
    doorsCutTotal += mergedDoors.length;

    // WO102 §5 — window의 sill/head는 항상 가정값(§ 위 상수)이다. 이
    // 벽의 실제 높이보다 head가 높으면(비정상: 천장고가 아주 낮은 벽에
    // 표준 창 크기를 억지로 끼워 맞추는 셈) 존재하지 않는 치수를 지어
    // 내지 않고 그 window는 건너뛴다.
    final headHeightMm = kAssumedWindowSillHeightMm + kAssumedWindowHeightMm;
    final windowsFitThisWall = headHeightMm < heightMm - 1e-6;
    if (!windowsFitThisWall) {
      windowsSkippedNoRoomForSillHead += mergedWindows.length;
    }
    windowsCutTotal += windowsFitThisWall ? mergedWindows.length : 0;

    // WO102 §4/§5 — door(바닥부터 열림)와 window(허리 높이부터 열림)를
    // "이 구간은 gapBottomMm~gapTopMm만큼 벽을 비운다"는 같은 모양의
    // span으로 합쳐 하나의 절단 로직으로 처리한다(중복 로직 금지, §3).
    final allSpans = <_WallOpeningSpan>[
      for (final d in mergedDoors) (t0: d.t0, t1: d.t1, gapBottomMm: 0, gapTopMm: kAssumedDoorOpeningHeightMm),
      if (windowsFitThisWall)
        for (final w in mergedWindows)
          (t0: w.t0, t1: w.t1, gapBottomMm: kAssumedWindowSillHeightMm, gapTopMm: headHeightMm),
    ]..sort((a, b) => a.t0.compareTo(b.t0));

    // WO099 §6 — 벽 옆면과 다르게, 단면(top면)만 살짝 어둡게(§ 위
    // [_wallTopColor]). 문/창 위 상인방·창 아래 허리벽도 결국 "벽
    // 단면"이므로 같은 색을 쓴다.
    final topColor = _wallTopColor(color);
    if (allSpans.isEmpty) {
      // §7 — 기존과 완전히 동일한 경로/결과(단일 전체 높이 직육면체).
      addWallBox(triangles, footprint, 0, 1, 0, heightMm, color, 'wall:${wall.id}', topColor: topColor);
    } else {
      // 모든 span의 along-구간을 뺀 나머지만 바닥부터 전체 높이로
      // 세운다(문/창 좌우 벽 + 벽 없는 wall 양 끝 처리 모두 이 한
      // 규칙으로 자연히 해결된다) — WO097의 door 전용 로직을 일반화했다.
      var cursor = 0.0;
      for (final span in allSpans) {
        if (span.t0 > cursor) {
          addWallBox(triangles, footprint, cursor, span.t0, 0, heightMm, color, 'wall:${wall.id}', topColor: topColor);
        }
        cursor = math.max(cursor, span.t1);
      }
      if (cursor < 1.0) {
        addWallBox(triangles, footprint, cursor, 1.0, 0, heightMm, color, 'wall:${wall.id}', topColor: topColor);
      }
      for (final span in allSpans) {
        // 허리벽(window sill 아래) — door는 gapBottomMm=0이라 항상 건너뛴다.
        if (span.gapBottomMm > 1e-6) {
          addWallBox(
            triangles,
            footprint,
            span.t0,
            span.t1,
            0,
            span.gapBottomMm,
            color,
            'wall:${wall.id}',
            topColor: topColor,
          );
        }
        // 상인방(opening 위쪽 벽) — 천장고가 가정 head height보다 낮은
        // 극단적 경우만 건너뛴다(존재하지 않는 두께를 지어내지 않는다).
        if (span.gapTopMm < heightMm - 1e-6) {
          addWallBox(
            triangles,
            footprint,
            span.t0,
            span.t1,
            span.gapTopMm,
            heightMm,
            color,
            'wall:${wall.id}',
            includeBottomCap: true,
            topColor: topColor,
          );
        }
      }
    }
    if (triangles.isEmpty) continue;

    // WO102 §5 — window frame/glass geometry. [addWallBox]를 그대로
    // 재사용해 opening 전체를 채우는 frame 상자 하나, 그 안에 사방으로
    // [kWindowFrameMarginMm]만큼 더 작은 glass 상자 하나를 만든다(§8
    // 가구의 frame+mattress 인셋과 같은 패턴 — 새 geometry 방식을 만들지
    // 않는다).
    if (windowsFitThisWall && wallLengthMm != null && wallLengthMm > 0) {
      final marginT = kWindowFrameMarginMm / wallLengthMm;
      for (var i = 0; i < mergedWindows.length; i++) {
        final w = mergedWindows[i];
        final frameTriangles = <SpaceTriangleV2>[];
        addWallBox(
          frameTriangles,
          footprint,
          w.t0,
          w.t1,
          kAssumedWindowSillHeightMm,
          headHeightMm,
          _windowFrameColor,
          'window:${wall.id}:$i:frame',
          includeBottomCap: true,
          topColor: _windowFrameColor,
        );
        if (frameTriangles.isEmpty) continue;

        final glassT0 = w.t0 + marginT, glassT1 = w.t1 - marginT;
        final glassSillMm = kAssumedWindowSillHeightMm + kWindowFrameMarginMm;
        final glassHeadMm = headHeightMm - kWindowFrameMarginMm;
        final glassTriangles = <SpaceTriangleV2>[];
        if (glassT0 < glassT1 && glassSillMm < glassHeadMm) {
          addWallBox(
            glassTriangles,
            footprint,
            glassT0,
            glassT1,
            glassSillMm,
            glassHeadMm,
            _windowGlassColor,
            'window:${wall.id}:$i:glass',
            includeBottomCap: true,
            topColor: _windowGlassColor,
          );
        }

        final centerT = (w.t0 + w.t1) / 2;
        final centerPoint = Point2(
          footprint[0].x + (footprint[1].x - footprint[0].x) * centerT,
          footprint[0].y + (footprint[1].y - footprint[0].y) * centerT,
        );
        final centerMm = pointToMm(centerPoint, plan, scale);
        final windowObjectId = 'window:${wall.id}:$i';
        windowMeshes.add(
          SpaceWindowMeshV2(
            frameIdentity: SpaceObjectIdentityV2(
              objectId: '$windowObjectId:frame',
              sourceKind: SpaceElementKindV2.opening,
              sourceId: windowObjectId,
              wallId: wall.id,
              color: _windowFrameColor,
            ),
            frameTriangles: frameTriangles,
            glassIdentity: SpaceObjectIdentityV2(
              objectId: '$windowObjectId:glass',
              sourceKind: SpaceElementKindV2.opening,
              sourceId: windowObjectId,
              wallId: wall.id,
              color: _windowGlassColor,
            ),
            glassTriangles: glassTriangles,
            wallId: wall.id,
            centerMm: Vector3(centerMm.x, (kAssumedWindowSillHeightMm + headHeightMm) / 2, centerMm.z),
            widthMm: (w.t1 - w.t0) * wallLengthMm,
          ),
        );
      }
    }

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
        startMm: fullFootprintMm[0],
        endMm: fullFootprintMm[1],
        isExterior: isExterior,
      ),
    );
  }

  // ---- 바닥(WO 11/12번 — 벽과 완전히 분리, 실패해도 벽에 영향 없음) ----
  final areaSummary = computeRoomAreasV2(plan: plan, scale: scale);
  final areaById = {for (final r in areaSummary.rooms) r.id: r};
  final floorMeshes = <SpaceFloorMeshV2>[];
  final ceilingMeshes = <SpaceFloorMeshV2>[];
  var floorTriangulationFailures = 0;
  var approximatedFloorCount = 0;
  for (final room in plan.rooms) {
    final area = areaById[room.id];
    List<Vector3> pts;
    List<List<int>> earTriangles;
    final exactPts = area?.polygonMm;
    final exactTriangles = (exactPts != null && exactPts.isNotEmpty)
        ? earClipTriangulateV2(cleanPolygonV2(room.polygon))
        : const <List<int>>[];
    if (exactPts != null && exactPts.isNotEmpty && exactTriangles.isNotEmpty) {
      pts = exactPts;
      earTriangles = exactTriangles;
    } else {
      // WO094 PC1 실기 재검증 FAIL — 원본 polygon이 자기교차 등으로
      // 유효하지 않거나(area == null) ear-clipping이 실패한 드문
      // 부동소수점 경계 케이스. 바닥을 완전히 포기하는 대신 원본 점의
      // convex hull로 근사한다([_convexHullXZ] 참고).
      final rawMm = [for (final p in room.polygon) pointToMm(p, plan, scale)];
      final hull = _convexHullXZ(rawMm);
      if (hull.length < 3) {
        if (exactPts != null && exactPts.isNotEmpty) floorTriangulationFailures++;
        continue;
      }
      pts = hull;
      earTriangles = _fanTriangulateConvex(hull.length);
      approximatedFloorCount++;
    }
    final floorColor = _floorColor(room);
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
      final t = makeTriangle(a, b, c, floorColor, 'floor:${room.id}');
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
          color: floorColor,
        ),
        triangles: triangles,
        polygonMm: pts,
      ),
    );

    // ---- 천장(WO092 §4/§5 — 바닥과 같은 polygon을 천장고 높이로 올리고
    // normal을 반대(-Y)로 뒤집는다). 벽 상단 면(top face, 항상 벽 색)과는
    // 별개로, 방 폴리곤 전체를 덮는 진짜 천장 평면이다. normal이 -Y(방
    // 안쪽을 향함)라 [Space3DViewGpuV2]가 FrontSide 재질로 그리면 위에서
    // 내려다보는 기본 아이소 카메라에는 backface로 컬링되어 보이지
    // 않는다(기존 "천장 없는 dollhouse" 시야를 그대로 유지) — 카메라가
    // 천장고 아래로 내려가 위를 올려다보면(3D 투시 등) 정상적으로
    // 보인다.
    final ceilingHeightPoint = ceilingHeightMm;
    final ceilingPts = [for (final p in pts) Vector3(p.x, ceilingHeightPoint, p.z)];
    final ceilingColor = _ceilingColor(room);
    final ceilingTriangles = <SpaceTriangleV2>[];
    for (final tri in earTriangles) {
      final a = ceilingPts[tri[0]];
      var b = ceilingPts[tri[1]];
      var c = ceilingPts[tri[2]];
      if ((b - a).cross(c - a).y > 0) {
        final tmp = b;
        b = c;
        c = tmp;
      }
      final t = makeTriangle(a, b, c, ceilingColor, 'ceiling:${room.id}');
      if (t != null) ceilingTriangles.add(t);
    }
    if (ceilingTriangles.isNotEmpty) {
      ceilingMeshes.add(
        SpaceFloorMeshV2(
          identity: SpaceObjectIdentityV2(
            objectId: 'ceiling:${room.id}',
            sourceKind: SpaceElementKindV2.ceiling,
            sourceId: room.id,
            roomId: room.id,
            color: ceilingColor,
          ),
          triangles: ceilingTriangles,
          polygonMm: ceilingPts,
        ),
      );
    }
  }

  // ---- WO099 §8 — Phase A 최소 가구 3종(sofa/table/bed) ----
  // [SSRoomType]은 아직 bathroom/other뿐이라(침실/거실 구분 데이터 없음)
  // "이 방이 침실이다" 같은 판단을 지어내지 않는다 — 대신 유일하게 실제
  // 있는 신호인 면적으로만 순위를 매긴다: 가장 넓은 방(공용 공간일
  // 가능성이 높다는 일반적 가정만)에 sofa+table을, 그다음으로 넓은 방에
  // bed를 둔다. 이건 "이 방의 용도를 안다"는 주장이 아니라 §8이 요구한
  // "가구가 실제 공간 안에 있다는 공간감"만 만들기 위한 배치다(방이 1개
  // 뿐이면 같은 방에 전부 배치).
  final furnitureMeshes = <SpaceFurnitureMeshV2>[];
  final rankedRooms = [...areaSummary.rooms]
    ..sort((a, b) => b.areaM2.compareTo(a.areaM2));
  if (rankedRooms.isNotEmpty) {
    final primaryRoom = rankedRooms.first;
    final secondaryRoom = rankedRooms.length > 1 ? rankedRooms[1] : rankedRooms.first;

    void addFurniture(
      String idSuffix,
      SpaceFurnitureType type,
      RoomAreaV2 room,
      List<SpaceTriangleV2> tris,
      Vector3 centerMm,
    ) {
      if (tris.isEmpty) return;
      furnitureMeshes.add(
        SpaceFurnitureMeshV2(
          identity: SpaceObjectIdentityV2(
            objectId: 'furniture:$idSuffix',
            sourceKind: SpaceElementKindV2.furniture,
            sourceId: idSuffix,
            roomId: room.id,
            color: switch (type) {
              SpaceFurnitureType.sofa => _furnitureSofaColor,
              SpaceFurnitureType.table => _furnitureTableTopColor,
              SpaceFurnitureType.bed => _furnitureBedFrameColor,
            },
          ),
          triangles: tris,
          furnitureType: type,
          centerMm: centerMm,
          roomId: room.id,
        ),
      );
    }

    final primarySize = _boundingSizeXZ(primaryRoom.polygonMm);
    final primaryCenter = primaryRoom.centroidMm;
    // 소파와 테이블이 겹치지 않도록 방 중심에서 좌우로 살짝 떨어뜨려
    // 배치한다(정확한 방 형태를 분석하지 않는 단순 배치 — §8 "정교한
    // 배치 시스템 검증이 목적이 아니다").
    final sofaCenter = Vector3(primaryCenter.x - 550, 0, primaryCenter.z);
    final tableCenter = Vector3(primaryCenter.x + 650, 0, primaryCenter.z);
    addFurniture(
      'sofa-1',
      SpaceFurnitureType.sofa,
      primaryRoom,
      _sofaTriangles(addQuad, sofaCenter, primarySize),
      sofaCenter,
    );
    addFurniture(
      'table-1',
      SpaceFurnitureType.table,
      primaryRoom,
      _tableTriangles(addQuad, tableCenter, primarySize),
      tableCenter,
    );

    final secondarySize = _boundingSizeXZ(secondaryRoom.polygonMm);
    final bedCenter = secondaryRoom.centroidMm;
    addFurniture(
      'bed-1',
      SpaceFurnitureType.bed,
      secondaryRoom,
      _bedTriangles(addQuad, bedCenter, secondarySize),
      bedCenter,
    );
  }

  // ---- opening identity(WO 19번 시작, WO097 — door는 위 벽 loop에서
  // 이미 geometry로 반영됨. 이 목록은 door 포함 모든 opening의 식별자/
  // 위치 메타데이터로, 3D 선택/작업 연결 등에서 계속 쓰인다) ----
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
  // WO097/WO102 — door/window 모두 이제 실제로 반영되므로(§5) 반영/
  // 미반영을 종류별로 정직하게 나눠 보고한다(§13 "실제 데이터 개수로
  // 보고한다").
  final unknownOpeningsCount = plan.openings
      .where((o) => o.type == OpeningType.unknown)
      .length;
  final doorsWithNoMatchingWall = plan.openings
      .where((o) => o.type == OpeningType.door && !wallIds.contains(o.wallId))
      .length;
  final windowsWithNoMatchingWall = plan.openings
      .where((o) => o.type == OpeningType.window && !wallIds.contains(o.wallId))
      .length;
  final warnings = <String>[
    if (doorsCutTotal > 0)
      '문 개구부 $doorsCutTotal개를 실제 3D 벽 geometry에 반영했습니다(문 높이는 '
          '실측값이 없어 통상값 ${kAssumedDoorOpeningHeightMm.toStringAsFixed(0)}mm를 '
          '가정합니다).',
    if (doorsWithNoMatchingWall > 0 || doorsSkippedDegenerate > 0)
      '문 개구부 ${doorsWithNoMatchingWall + doorsSkippedDegenerate}개는 벽에 반영하지 '
          '못했습니다(벽 연결 정보 없음/불일치 $doorsWithNoMatchingWall건, 벽 범위를 '
          '벗어난 위치·폭 $doorsSkippedDegenerate건) — 해당 위치는 기존처럼 막힌 벽으로 '
          '표시됩니다.',
    if (windowsCutTotal > 0)
      '창 개구부 $windowsCutTotal개를 실제 3D 벽 geometry(frame+glass)에 '
          '반영했습니다(창턱/창 높이는 실측값이 없어 통상값 '
          '${kAssumedWindowSillHeightMm.toStringAsFixed(0)}~'
          '${(kAssumedWindowSillHeightMm + kAssumedWindowHeightMm).toStringAsFixed(0)}mm를 '
          '가정합니다 — 실제 데이터가 들어오면 교체될 자리입니다).',
    if (windowsWithNoMatchingWall > 0 || windowsSkippedDegenerate > 0 || windowsSkippedNoRoomForSillHead > 0)
      '창 개구부 ${windowsWithNoMatchingWall + windowsSkippedDegenerate + windowsSkippedNoRoomForSillHead}개는 '
          '벽에 반영하지 못했습니다(벽 연결 정보 없음/불일치 $windowsWithNoMatchingWall건, 벽 '
          '범위를 벗어난 위치·폭 $windowsSkippedDegenerate건, 벽 높이가 가정 창 높이보다 낮음 '
          '$windowsSkippedNoRoomForSillHead건) — 해당 위치는 기존처럼 막힌 벽으로 표시됩니다.',
    if (unknownOpeningsCount > 0)
      '문/창 종류가 확정되지 않은 개구부 $unknownOpeningsCount개는 벽에 반영하지 않았습니다 '
          '— 어느 쪽으로도 단정하지 않습니다.',
    if (floorMeshes.isEmpty && wallMeshes.isNotEmpty)
      '공간(방)을 인식하지 못해 바닥은 생성하지 않았습니다.',
    if (floorTriangulationFailures > 0)
      '$floorTriangulationFailures개 공간의 바닥 polygon을 삼각분할하지 못해 그 공간만 '
          '바닥 없이 표시됩니다(벽은 정상 표시).',
    if (approximatedFloorCount > 0)
      '$approximatedFloorCount개 공간은 원본 바닥 polygon이 자기교차 등으로 정확하지 '
          '않아 convex hull로 근사한 바닥/천장을 대신 표시합니다 — 오목한 부분의 '
          '모양이 실제와 다를 수 있습니다.',
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
      furnitureMeshes: const [],
      windowMeshes: const [],
      openings: openings,
      minBounds: Vector3.zero(),
      maxBounds: Vector3.zero(),
      warnings: warnings,
    );
  }

  return SpaceSceneV2(
    wallMeshes: wallMeshes,
    floorMeshes: floorMeshes,
    ceilingMeshes: ceilingMeshes,
    furnitureMeshes: furnitureMeshes,
    windowMeshes: windowMeshes,
    openings: openings,
    minBounds: Vector3(minX, minY, minZ),
    maxBounds: Vector3(maxX, maxY, maxZ),
    warnings: warnings,
  );
}
