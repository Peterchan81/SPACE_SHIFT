// SPACE SHIFT — CANONICAL 2D CONFIRMATION → 3D PIPELINE WO §4 검증.
//
// "구조 확인/보정" 편집 도구(벽 추가/문·창 추가/문·창 이동)가 의존하는
// 순수 모델 헬퍼 — [CadWall.projectPoint], [nearestCadWall],
// [CadFloorPlan.normalizedLengthFromMm], [CadOpening.copyWith] — 를
// 화면 위젯 없이 직접 검증한다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';

const _scale = FloorPlanScale(
  mmPerPixel: 5.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 5000,
  source: ScaleSource.measured,
);

CadWall _horizontalWall() => const CadWall(
  id: 'w1',
  start: Point2(0.1, 0.5),
  end: Point2(0.9, 0.5),
  thicknessNormalized: 0.01,
  wallType: CadWallType.interior,
  confidence: 0.9,
);

void main() {
  group('CadWall.projectPoint', () {
    test('벽 중간 위(정확히 centerline)로 투영하면 t=0.5, 같은 점을 돌려준다', () {
      final wall = _horizontalWall();
      final result = wall.projectPoint(const Point2(0.5, 0.5));
      expect(result.t, closeTo(0.5, 1e-9));
      expect(result.point.x, closeTo(0.5, 1e-9));
      expect(result.point.y, closeTo(0.5, 1e-9));
    });

    test('벽에서 수직으로 떨어진 점은 가장 가까운 centerline 위 점으로 투영된다', () {
      final wall = _horizontalWall();
      final result = wall.projectPoint(const Point2(0.3, 0.6));
      expect(result.point.x, closeTo(0.3, 1e-9));
      expect(result.point.y, closeTo(0.5, 1e-9));
    });

    test('벽 시작점보다 이전 위치는 t=0(시작점)으로 clamp된다', () {
      final wall = _horizontalWall();
      final result = wall.projectPoint(const Point2(-0.5, 0.5));
      expect(result.t, 0.0);
      expect(result.point.x, closeTo(0.1, 1e-9));
    });

    test('벽 끝점보다 이후 위치는 t=1(끝점)으로 clamp된다', () {
      final wall = _horizontalWall();
      final result = wall.projectPoint(const Point2(1.5, 0.5));
      expect(result.t, 1.0);
      expect(result.point.x, closeTo(0.9, 1e-9));
    });
  });

  group('nearestCadWall', () {
    test('tolerance 이내의 가장 가까운 벽을 찾는다', () {
      final near = _horizontalWall();
      final far = const CadWall(
        id: 'w2',
        start: Point2(0.1, 0.9),
        end: Point2(0.9, 0.9),
        thicknessNormalized: 0.01,
        wallType: CadWallType.interior,
        confidence: 0.9,
      );
      final plan = CadFloorPlan(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: [near, far],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      final found = nearestCadWall(plan, const Point2(0.5, 0.51), tolerance: 0.05);
      expect(found?.id, 'w1');
    });

    test('tolerance 밖이면 아무 벽도 찾지 못한다(근거 없는 위치에는 아무 것도 만들지 않는다)', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: [_horizontalWall()],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      final found = nearestCadWall(plan, const Point2(0.5, 0.9), tolerance: 0.05);
      expect(found, isNull);
    });
  });

  group('CadFloorPlan.normalizedLengthFromMm', () {
    test('scale이 있으면 mm를 정규화 길이로 정확히 역변환한다(realMmForNormalizedLength의 역함수)', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: const [],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      const normalizedLength = 0.1;
      final mm = plan.realMmForNormalizedLength(normalizedLength, _scale)!;
      final roundTripped = plan.normalizedLengthFromMm(mm, _scale)!;
      expect(roundTripped, closeTo(normalizedLength, 1e-9));
    });

    test('scale이 없으면 임의로 값을 지어내지 않고 null을 돌려준다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: const [],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      expect(plan.normalizedLengthFromMm(900, null), isNull);
    });
  });

  group('CadOpening.copyWith', () {
    test('center/wallId/source/edited만 바꾸고 나머지 필드는 그대로 유지한다', () {
      const original = CadOpening(
        id: 'o1',
        type: OpeningType.door,
        center: Point2(0.5, 0.5),
        widthNormalized: 0.02,
        confidence: 0.8,
        wallId: 'w1',
        source: CadElementSource.aiSuggested,
      );
      final moved = original.copyWith(
        center: const Point2(0.6, 0.5),
        edited: true,
        source: CadElementSource.userEdited,
      );
      expect(moved.id, original.id);
      expect(moved.type, original.type);
      expect(moved.widthNormalized, original.widthNormalized);
      expect(moved.confidence, original.confidence);
      expect(moved.wallId, original.wallId);
      expect(moved.center.x, 0.6);
      expect(moved.edited, isTrue);
      expect(moved.source, CadElementSource.userEdited);
      // 원본은 불변으로 남는다.
      expect(original.center.x, 0.5);
      expect(original.edited, isFalse);
    });
  });
}
