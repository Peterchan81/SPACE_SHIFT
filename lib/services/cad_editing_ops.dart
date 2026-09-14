import 'dart:math' as math;

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';

/// SS CAD TEST — CAD Editor WO.
///
/// 화면(위젯) 코드와 분리된 순수 계산 함수만 모아 둔다 — 전부 위젯 없이
/// 단위 테스트할 수 있다. [FloorPlanWorkspaceScreen]은 이 함수들의
/// 결과를 `_mutateCad`(기존 undo 스택 재사용)에 넘기기만 한다.
///
/// 실제 좌표 계산은 항상 픽셀 공간에서 한다 — [CadWall.start]/[end]는
/// 정규화(0~1) 좌표이고 가로/세로 축의 스케일이 서로 다를 수 있으므로
/// (sourceWidthPx != sourceHeightPx), 정규화 좌표에서 직접 방향 벡터를
/// 계산하면 실제 방향이 왜곡된다.

/// 벽 [wall]의 시작점(start)은 그대로 두고, 실제 길이를 [newLengthMm]로
/// 바꾼 새 [CadWall]을 돌려준다. 사용자가 직접 입력한 값이므로
/// `source: userEdited`로 표시해, 이후 AI 재분석이 이 벽을 다시 덮어써도
/// 되는지 판단하는 근거로 삼을 수 있게 한다.
///
/// 벽 길이가 이미 0이면(방향을 알 수 없음) 원본을 그대로 돌려준다 —
/// 임의의 방향을 지어내지 않는다.
CadWall wallWithLengthMm(CadFloorPlan plan, CadWall wall, double newLengthMm, FloorPlanScale scale) {
  final startXPx = wall.start.x * plan.sourceWidthPx;
  final startYPx = wall.start.y * plan.sourceHeightPx;
  final dxPx = wall.end.x * plan.sourceWidthPx - startXPx;
  final dyPx = wall.end.y * plan.sourceHeightPx - startYPx;
  final currentLenPx = math.sqrt(dxPx * dxPx + dyPx * dyPx);
  if (currentLenPx <= 0) return wall;

  final uxPx = dxPx / currentLenPx;
  final uyPx = dyPx / currentLenPx;
  final newLenPx = newLengthMm / scale.mmPerPixel;
  final newEndXPx = startXPx + uxPx * newLenPx;
  final newEndYPx = startYPx + uyPx * newLenPx;

  return wall.copyWith(
    end: Point2(newEndXPx / plan.sourceWidthPx, newEndYPx / plan.sourceHeightPx),
    edited: true,
    source: CadElementSource.userEdited,
  );
}

/// 문/창 [opening]의 중심은 그대로 두고 폭만 [newWidthMm]로 바꾼 새
/// [CadOpening]을 돌려준다.
CadOpening openingWithWidthMm(CadFloorPlan plan, CadOpening opening, double newWidthMm, FloorPlanScale scale) {
  final diagonalPx = plan.diagonalPx;
  if (diagonalPx <= 0) return opening;
  return opening.copyWith(
    widthNormalized: newWidthMm / (scale.mmPerPixel * diagonalPx),
    source: CadElementSource.userEdited,
  );
}

/// [target]에서 [snapRadiusPx](분석 기준 픽셀) 이내에 있는 다른 벽의
/// endpoint가 있으면 그 endpoint로 스냅한 좌표를 돌려준다 — 없으면
/// [target]을 그대로 돌려준다. [excludeWallId]는 지금 옮기고 있는 벽
/// 자신(끝점이 스스로에게 스냅되는 것을 막는다).
///
/// 먼 벽을 임의로 잇지 않는다 — snap은 순수 좌표 이동일 뿐 새 연결
/// topology를 만들지 않는다(§2 "먼 벽을 임의 연결하지 않는다").
Point2 snapToNearbyEndpoint(
  CadFloorPlan plan,
  Point2 target, {
  String? excludeWallId,
  double snapRadiusPx = 12.0,
}) {
  final targetXPx = target.x * plan.sourceWidthPx;
  final targetYPx = target.y * plan.sourceHeightPx;

  Point2? best;
  var bestDistPx = double.infinity;

  void consider(Point2 candidate) {
    final cxPx = candidate.x * plan.sourceWidthPx;
    final cyPx = candidate.y * plan.sourceHeightPx;
    final d = math.sqrt(math.pow(cxPx - targetXPx, 2) + math.pow(cyPx - targetYPx, 2));
    if (d <= snapRadiusPx && d < bestDistPx) {
      bestDistPx = d;
      best = candidate;
    }
  }

  for (final wall in plan.walls) {
    if (wall.id == excludeWallId) continue;
    consider(wall.start);
    consider(wall.end);
  }

  return best ?? target;
}

/// 새 벽을 만든다 — 기존 도면 위 임의의 빈 자리(이미지 중앙 부근)에
/// 짧은 기본 길이로 배치한다. 사용자가 만든 벽이므로 `userCreated`로
/// 표시한다. 실제 좌표는 화면에서 사용자가 끝점을 드래그해 다시
/// 잡는다는 전제다 — "정확한 새 벽"을 자동으로 추정하지 않는다.
CadWall createDefaultWall(CadFloorPlan plan, {required bool isExterior}) {
  final existingIds = plan.walls.map((w) => w.id).toSet();
  var n = plan.walls.length;
  String id;
  do {
    id = 'user-wall-$n';
    n++;
  } while (existingIds.contains(id));

  return CadWall(
    id: id,
    start: const Point2(0.4, 0.4),
    end: const Point2(0.6, 0.4),
    thicknessNormalized: 0.01,
    wallType: isExterior ? CadWallType.exterior : CadWallType.interior,
    confidence: 1.0,
    source: CadElementSource.userCreated,
  );
}

/// 기본 문/창 폭(mm) — 국내 주거용 표준 규격(문 900mm 여닫이/창 1200mm
/// 표준 창호 기준). scale이 있을 때만 실제 mm 폭을 정확히 재현하고,
/// 없으면 정규화 좌표계에서의 임의 비율로만 폴백한다(§9 원칙과 동일 —
/// scale 없이 mm를 지어내지 않는다는 표시로 widthNormalized를 작게 둔다).
const double kDefaultDoorWidthMm = 900;
const double kDefaultWindowWidthMm = 1200;

/// 선택된 벽 [hostWall] 중앙에 새 문/창을 만든다.
CadOpening createOpeningOnWall(
  CadFloorPlan plan,
  CadWall hostWall, {
  required OpeningType type,
  FloorPlanScale? scale,
}) {
  final existingIds = plan.openings.map((o) => o.id).toSet();
  var n = plan.openings.length;
  String id;
  do {
    id = 'user-opening-$n';
    n++;
  } while (existingIds.contains(id));

  final center = Point2(
    (hostWall.start.x + hostWall.end.x) / 2,
    (hostWall.start.y + hostWall.end.y) / 2,
  );

  final diagonalPx = plan.diagonalPx;
  final defaultMm = type == OpeningType.door ? kDefaultDoorWidthMm : kDefaultWindowWidthMm;
  final widthNormalized = (scale != null && diagonalPx > 0)
      ? defaultMm / (scale.mmPerPixel * diagonalPx)
      : 0.03;

  return CadOpening(
    id: id,
    type: type,
    center: center,
    widthNormalized: widthNormalized,
    confidence: 1.0,
    wallId: hostWall.id,
    source: CadElementSource.userCreated,
  );
}
