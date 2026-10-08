// SS CAD TEST — Hybrid Geometry Recovery WO.
//
// [buildHybridCadFloorPlan]은 GPT가 준 대략의 벽 목록을 pixel_wall_v4의
// 이미 검증된 planar graph 엔진(endpoint snap/T-junction split/닫힌 방
// 추출)에 통과시킨다. 실제 평면도(평면도.PNG)는 GPT가 벽을 너무 적게
// (9~14개) 검출해 전체 outline이 닫히지 않는 것으로 확인됐다 — 이는
// "이 코드가 틀렸다"가 아니라 "입력 벽 목록이 성기다"는 뜻이므로, 이
// 테스트는 합성(synthetic) 데이터로 메커니즘 자체가 실제로 올바르게
// 동작하는지(닫힌 사각형 → 방 1개, T-junction → 분할, 근접 끝점 →
// 스냅, 대각선 → 제외, 진짜 분리 → 정직하게 미해결 보고)를 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/hybrid_wall_topology_builder.dart';

void main() {
  const w = 1000;
  const h = 1000;

  test('닫힌 사각형 4개 벽 -> 연결된 topology + 방 1개', () {
    const walls = [
      CadWall(id: 'top', start: Point2(0.1, 0.1), end: Point2(0.5, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'right', start: Point2(0.5, 0.1), end: Point2(0.5, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'bottom', start: Point2(0.5, 0.5), end: Point2(0.1, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'left', start: Point2(0.1, 0.5), end: Point2(0.1, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
    ];
    final result = buildHybridCadFloorPlan(
      sourceWidthPx: w,
      sourceHeightPx: h,
      gptWalls: walls,
      gptOpenings: const [],
      gptRooms: const [],
    );

    expect(result.connectedComponents, 1);
    expect(result.danglingEdgeCount, 0);
    expect(result.floorDomainClosed, isTrue);
    expect(result.innerRoomCount, 1);
    expect(result.cadFloorPlan.rooms, hasLength(1));
    expect(result.cadFloorPlan.rooms.single.polygon, hasLength(4));
    expect(result.excludedNonAxisCount, 0);
    // 4개 벽이 그대로 4개 edge로 나와야 한다(중간에 아무것도 안 지나므로
    // 분할되지 않음).
    expect(result.outputWallCount, 4);
  });

  test('내부 벽이 사각형을 가로지르면 T-junction에서 분할되고 방이 2개가 된다', () {
    const walls = [
      CadWall(id: 'top', start: Point2(0.1, 0.1), end: Point2(0.5, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'right', start: Point2(0.5, 0.1), end: Point2(0.5, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'bottom', start: Point2(0.5, 0.5), end: Point2(0.1, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'left', start: Point2(0.1, 0.5), end: Point2(0.1, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      // 가운데를 세로로 가로지르는 칸막이 — top/bottom의 "중간"에 T로 닿는다.
      CadWall(id: 'divider', start: Point2(0.3, 0.1), end: Point2(0.3, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.interior, confidence: 1.0),
    ];
    final result = buildHybridCadFloorPlan(
      sourceWidthPx: w,
      sourceHeightPx: h,
      gptWalls: walls,
      gptOpenings: const [],
      gptRooms: const [],
    );

    expect(result.floorDomainClosed, isTrue);
    expect(result.connectedComponents, 1);
    expect(result.innerRoomCount, 2, reason: 'divider가 사각형을 좌우 방 2개로 나눠야 한다');
    // top/bottom이 divider와 만나는 지점에서 각각 2조각으로 잘려야 하므로
    // 4(외벽 그대로 top/bottom은 분할, right/left는 안 잘림) + 1(divider) 이상.
    expect(result.outputWallCount, greaterThan(walls.length));
    expect(result.tJunctionCount, greaterThanOrEqualTo(2));
  });

  test('끝점이 정확히 일치하지 않아도(작은 오차) endpoint snap으로 여전히 닫힌다', () {
    const walls = [
      CadWall(id: 'top', start: Point2(0.1, 0.1), end: Point2(0.5, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      // right의 시작점이 top의 끝점(0.5,0.1)과 정확히 안 맞고 살짝 어긋남(1px 미만).
      CadWall(id: 'right', start: Point2(0.5005, 0.1005), end: Point2(0.5, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'bottom', start: Point2(0.5, 0.5), end: Point2(0.1, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'left', start: Point2(0.1, 0.5), end: Point2(0.0995, 0.0995), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
    ];
    final result = buildHybridCadFloorPlan(
      sourceWidthPx: w,
      sourceHeightPx: h,
      gptWalls: walls,
      gptOpenings: const [],
      gptRooms: const [],
    );

    expect(result.floorDomainClosed, isTrue, reason: '실측 오차 수준의 끝점 어긋남은 endpoint snap으로 흡수되어야 한다');
    expect(result.connectedComponents, 1);
    expect(result.innerRoomCount, 1);
  });

  test('서로 안 닿는 두 벽 그룹은 정직하게 2개 성분/미해결로 보고된다(억지로 잇지 않음)', () {
    const walls = [
      CadWall(id: 'a1', start: Point2(0.1, 0.1), end: Point2(0.3, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'a2', start: Point2(0.3, 0.1), end: Point2(0.3, 0.3), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      // 완전히 동떨어진 벽(위 두 벽과 몇백 px 떨어짐 — 절대 door 크기 gap이 아니다).
      CadWall(id: 'b1', start: Point2(0.7, 0.7), end: Point2(0.9, 0.7), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
    ];
    final result = buildHybridCadFloorPlan(
      sourceWidthPx: w,
      sourceHeightPx: h,
      gptWalls: walls,
      gptOpenings: const [],
      gptRooms: const [],
    );

    expect(result.connectedComponents, 2);
    expect(result.floorDomainClosed, isFalse);
    expect(result.cadFloorPlan.warnings, isNotEmpty);
    // 벽을 지어내거나 삭제하지 않는다 — 전부 그대로 출력에 남아 있어야 한다.
    expect(result.outputWallCount, walls.length);
  });

  test('대각선 벽은 topology 재구성에서 제외되고 reviewNeeded로 원본 좌표 그대로 남는다', () {
    const walls = [
      CadWall(id: 'top', start: Point2(0.1, 0.1), end: Point2(0.5, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'right', start: Point2(0.5, 0.1), end: Point2(0.5, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'bottom', start: Point2(0.5, 0.5), end: Point2(0.1, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'left', start: Point2(0.1, 0.5), end: Point2(0.1, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      // 45도 대각선 — 실제 건축 도면에 흔치 않은 값, 축 정규화 대상이 아니다.
      CadWall(id: 'diagonal', start: Point2(0.15, 0.15), end: Point2(0.45, 0.45), thicknessNormalized: 0.01, wallType: CadWallType.interior, confidence: 1.0),
    ];
    final result = buildHybridCadFloorPlan(
      sourceWidthPx: w,
      sourceHeightPx: h,
      gptWalls: walls,
      gptOpenings: const [],
      gptRooms: const [],
    );

    expect(result.excludedNonAxisCount, 1);
    expect(result.axisNormalizedCount, 4);
    final diagonalOut = result.cadFloorPlan.walls.firstWhere((wall) => wall.id == 'diagonal');
    expect(diagonalOut.reviewNeeded, isTrue);
    expect(diagonalOut.start, const Point2(0.15, 0.15), reason: '원본 좌표를 임의로 바꾸지 않는다');
    expect(diagonalOut.end, const Point2(0.45, 0.45));
    // 나머지 사각형 4개는 정상적으로 닫혀야 한다(대각선 제외가 나머지를 망가뜨리지 않음).
    expect(result.floorDomainClosed, isTrue);
  });

  test('닫힌 사각형의 4700mm 기준 벽으로 scale을 적용하면 재측정해도 정확히 4700mm다', () {
    const walls = [
      CadWall(id: 'top', start: Point2(0.1, 0.1), end: Point2(0.5, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'right', start: Point2(0.5, 0.1), end: Point2(0.5, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'bottom', start: Point2(0.5, 0.5), end: Point2(0.1, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
      CadWall(id: 'left', start: Point2(0.1, 0.5), end: Point2(0.1, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0),
    ];
    final result = buildHybridCadFloorPlan(
      sourceWidthPx: w,
      sourceHeightPx: h,
      gptWalls: walls,
      gptOpenings: const [],
      gptRooms: const [],
    );
    final leftWall = result.cadFloorPlan.walls.firstWhere((wall) => wall.start.x < 0.15 && wall.end.x < 0.15);
    final pxLen = result.cadFloorPlan.pixelDistance(leftWall.start, leftWall.end);
    // left 벽 pxLen = 0.4 * 1000 = 400px 이어야 한다(스냅으로 크게 안 변함).
    expect(pxLen, closeTo(400.0, 1.0));
    const mmPerPixel = 4700 / 400.0;
    final lengthMm = pxLen * mmPerPixel;
    expect(lengthMm, closeTo(4700.0, 15.0), reason: 'snap으로 인한 px 오차가 mm에도 비례 반영되는 정도까지만 허용');
  });
}
