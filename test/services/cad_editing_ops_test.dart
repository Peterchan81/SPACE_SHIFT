// SS CAD TEST — CAD Editor WO. cad_editing_ops.dart의 순수 계산 검증.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/cad_editing_ops.dart';

void main() {
  const sourceWidthPx = 1000;
  const sourceHeightPx = 1000;
  const scale = FloorPlanScale(
    mmPerPixel: 10.0, // 1px = 10mm, 계산을 손으로 검산하기 쉬운 값.
    referenceStart: Point2(0, 0),
    referenceEnd: Point2(1, 0),
    referenceLengthMm: 10000,
  );

  CadFloorPlan planWith(List<CadWall> walls, {List<CadOpening> openings = const []}) {
    return CadFloorPlan(
      sourceWidthPx: sourceWidthPx,
      sourceHeightPx: sourceHeightPx,
      walls: walls,
      openings: openings,
      rooms: const [],
      warnings: const [],
    );
  }

  group('wallWithLengthMm', () {
    test('AI 결과 4500mm -> 사용자 4830mm 입력 -> 실제 길이가 정확히 4830mm가 된다', () {
      // 수평 벽, 450px(=4500mm) 길이.
      const wall = CadWall(
        id: 'w1',
        start: Point2(0.1, 0.1),
        end: Point2(0.55, 0.1),
        thicknessNormalized: 0.01,
        wallType: CadWallType.exterior,
        confidence: 0.9,
      );
      final plan = planWith([wall]);
      expect(plan.pixelDistance(wall.start, wall.end) * scale.mmPerPixel, closeTo(4500, 1e-6));

      final edited = wallWithLengthMm(plan, wall, 4830, scale);
      final newLenMm = plan.pixelDistance(edited.start, edited.end) * scale.mmPerPixel;
      expect(newLenMm, closeTo(4830, 1e-6));
      expect(edited.start, wall.start, reason: '시작점은 그대로 유지되어야 한다');
      expect(edited.source, CadElementSource.userEdited);
      expect(edited.edited, isTrue);
    });

    test('대각선 벽도 방향을 유지하며 길이만 바뀐다', () {
      const wall = CadWall(
        id: 'w1',
        start: Point2(0.1, 0.1),
        end: Point2(0.4, 0.4),
        thicknessNormalized: 0.01,
        wallType: CadWallType.interior,
        confidence: 0.9,
      );
      final plan = planWith([wall]);
      final originalDx = wall.end.x - wall.start.x;
      final originalDy = wall.end.y - wall.start.y;
      final originalAngle = originalDy / originalDx;

      final edited = wallWithLengthMm(plan, wall, 5000, scale);
      final newDx = edited.end.x - edited.start.x;
      final newDy = edited.end.y - edited.start.y;
      expect(newDy / newDx, closeTo(originalAngle, 1e-9), reason: '방향(기울기)이 바뀌면 안 된다');
      expect(plan.pixelDistance(edited.start, edited.end) * scale.mmPerPixel, closeTo(5000, 1e-6));
    });

    test('길이 0인 벽은 방향을 알 수 없어 그대로 반환한다(임의 방향 지어내지 않음)', () {
      const wall = CadWall(
        id: 'w1',
        start: Point2(0.5, 0.5),
        end: Point2(0.5, 0.5),
        thicknessNormalized: 0.01,
        wallType: CadWallType.interior,
        confidence: 0.9,
      );
      final plan = planWith([wall]);
      final result = wallWithLengthMm(plan, wall, 3000, scale);
      expect(result.start, wall.start);
      expect(result.end, wall.end);
    });
  });

  group('openingWithWidthMm', () {
    test('문 폭을 900mm로 바꾸면 재계산한 폭이 정확히 900mm다', () {
      const opening = CadOpening(
        id: 'o1',
        type: OpeningType.door,
        center: Point2(0.5, 0.5),
        widthNormalized: 0.01,
        confidence: 0.8,
        wallId: 'w1',
      );
      final plan = planWith(const []);
      final edited = openingWithWidthMm(plan, opening, 900, scale);
      final widthMm = edited.widthNormalized * plan.diagonalPx * scale.mmPerPixel;
      expect(widthMm, closeTo(900, 1e-6));
      expect(edited.center, opening.center, reason: '중심은 유지되어야 한다');
      expect(edited.source, CadElementSource.userEdited);
    });
  });

  group('snapToNearbyEndpoint', () {
    test('가까운(허용 오차 이내) 다른 벽의 끝점으로 스냅한다', () {
      const wallA = CadWall(id: 'a', start: Point2(0.1, 0.1), end: Point2(0.3, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      const wallB = CadWall(id: 'b', start: Point2(0.5, 0.5), end: Point2(0.7, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      final plan = planWith([wallA, wallB]);
      // wallA.end(0.3,0.1)에서 5px 이내(정규화 0.005 = 5px, sourceWidthPx=1000).
      final target = const Point2(0.3, 0.1).copyWith(x: 0.3 + 0.003);
      final snapped = snapToNearbyEndpoint(plan, target, excludeWallId: 'b');
      expect(snapped, wallA.end);
    });

    test('먼 벽은 임의로 잇지 않는다 — 허용 오차 밖이면 원래 좌표 그대로', () {
      const wallA = CadWall(id: 'a', start: Point2(0.1, 0.1), end: Point2(0.3, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      final plan = planWith([wallA]);
      const target = Point2(0.8, 0.8);
      final snapped = snapToNearbyEndpoint(plan, target);
      expect(snapped, target);
    });

    test('자기 자신의 벽은 스냅 후보에서 제외된다', () {
      const wallA = CadWall(id: 'a', start: Point2(0.1, 0.1), end: Point2(0.3, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      final plan = planWith([wallA]);
      final target = const Point2(0.3, 0.1).copyWith(x: 0.301);
      final snapped = snapToNearbyEndpoint(plan, target, excludeWallId: 'a');
      expect(snapped, target, reason: '유일한 후보가 자기 자신뿐이면 스냅되지 않아야 한다');
    });
  });

  group('createDefaultWall / createOpeningOnWall', () {
    test('새 벽은 사용자 생성(userCreated)으로 표시되고 id가 겹치지 않는다', () {
      const existing = CadWall(id: 'user-wall-0', start: Point2(0, 0), end: Point2(1, 0), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      final plan = planWith([existing]);
      final created = createDefaultWall(plan, isExterior: false);
      expect(created.source, CadElementSource.userCreated);
      expect(created.id, isNot('user-wall-0'));
      expect(created.wallType, CadWallType.interior);
    });

    test('새 문은 선택된 벽 중앙에 anchor되고 900mm 기본폭을 갖는다', () {
      const wall = CadWall(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.55, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      final plan = planWith([wall]);
      final opening = createOpeningOnWall(plan, wall, type: OpeningType.door, scale: scale);
      expect(opening.wallId, 'w1');
      expect(opening.center.x, closeTo((0.1 + 0.55) / 2, 1e-9));
      final widthMm = opening.widthNormalized * plan.diagonalPx * scale.mmPerPixel;
      expect(widthMm, closeTo(900, 1e-6));
      expect(opening.source, CadElementSource.userCreated);
    });

    test('scale이 없으면 mm를 지어내지 않고 작은 fallback 비율만 쓴다', () {
      const wall = CadWall(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.55, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      final plan = planWith([wall]);
      final opening = createOpeningOnWall(plan, wall, type: OpeningType.window, scale: null);
      expect(opening.widthNormalized, 0.03);
    });
  });
}
