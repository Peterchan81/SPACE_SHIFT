import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/workspace_drawing_entity.dart';

WorkspaceDrawingEntity _entity(WorkspaceDrawingType type, List<Point2> points) {
  final now = DateTime(2026, 1, 1);
  return WorkspaceDrawingEntity(id: 1, type: type, points: points, createdAt: now, updatedAt: now);
}

void main() {
  group('WorkspaceDrawingEntity — line', () {
    test('line creation은 정확히 start/end 2점을 보존한다', () {
      final e = _entity(WorkspaceDrawingType.line, const [Point2(0.1, 0.1), Point2(0.5, 0.5)]);
      expect(e.points, hasLength(2));
      expect(e.points.first, const Point2(0.1, 0.1));
      expect(e.points.last, const Point2(0.5, 0.5));
    });

    test('line hit test — 선분 위/근처 점은 hit, 멀리 떨어진 점은 miss', () {
      final e = _entity(WorkspaceDrawingType.line, const [Point2(0.0, 0.5), Point2(1.0, 0.5)]);
      expect(e.hitTest(const Point2(0.5, 0.5), toleranceNormalized: 0.02), isTrue);
      expect(e.hitTest(const Point2(0.5, 0.505), toleranceNormalized: 0.02), isTrue);
      expect(e.hitTest(const Point2(0.5, 0.9), toleranceNormalized: 0.02), isFalse);
    });
  });

  group('WorkspaceDrawingEntity — curve', () {
    test('curve creation은 정확히 start/control/end 3점을 보존한다', () {
      final e = _entity(WorkspaceDrawingType.curve, const [Point2(0, 0), Point2(0.5, 1.0), Point2(1, 0)]);
      expect(e.points, hasLength(3));
    });

    test('curve hit test — 곡선 중간 근처는 hit, 곡선에서 먼 점은 miss', () {
      final e = _entity(WorkspaceDrawingType.curve, const [Point2(0, 0.5), Point2(0.5, 0.0), Point2(1, 0.5)]);
      // t=0.5 지점의 실제 quadratic bezier 값 = 0.25*start + 0.5*control + 0.25*end.
      const midPoint = Point2(0.5, 0.25);
      expect(e.hitTest(midPoint, toleranceNormalized: 0.02), isTrue);
      expect(e.hitTest(const Point2(0.5, 0.9), toleranceNormalized: 0.02), isFalse);
    });
  });

  group('WorkspaceDrawingEntity — circle', () {
    test('circle creation은 center/edgePoint 2점으로 저장하고 반지름을 파생시킨다', () {
      final e = _entity(WorkspaceDrawingType.circle, const [Point2(0.5, 0.5), Point2(0.6, 0.5)]);
      expect(e.circleCenter, const Point2(0.5, 0.5));
      expect(e.circleRadius, closeTo(0.1, 1e-9));
    });

    test('circle hit test — 원 내부/테두리는 hit, 원 밖 먼 점은 miss', () {
      final e = _entity(WorkspaceDrawingType.circle, const [Point2(0.5, 0.5), Point2(0.6, 0.5)]);
      expect(e.hitTest(const Point2(0.5, 0.5), toleranceNormalized: 0.01), isTrue, reason: '중심점은 내부');
      expect(e.hitTest(const Point2(0.6, 0.5), toleranceNormalized: 0.01), isTrue, reason: '테두리');
      expect(e.hitTest(const Point2(0.9, 0.9), toleranceNormalized: 0.01), isFalse);
    });
  });

  group('WorkspaceDrawingEntity — freeRegion', () {
    test('free region creation은 List<Point2> 전체를 순서대로 보존한다', () {
      final pts = const [Point2(0.1, 0.1), Point2(0.4, 0.1), Point2(0.4, 0.4), Point2(0.1, 0.4)];
      final e = _entity(WorkspaceDrawingType.freeRegion, pts);
      expect(e.points, pts);
    });

    test('free region hit test — 다각형 내부는 hit, 바깥은 miss', () {
      final e = _entity(
        WorkspaceDrawingType.freeRegion,
        const [Point2(0.1, 0.1), Point2(0.4, 0.1), Point2(0.4, 0.4), Point2(0.1, 0.4)],
      );
      expect(e.hitTest(const Point2(0.25, 0.25), toleranceNormalized: 0.01), isTrue, reason: '사각형 내부');
      expect(e.hitTest(const Point2(0.9, 0.9), toleranceNormalized: 0.01), isFalse);
    });
  });

  test('copyWith은 지정하지 않은 필드를 그대로 유지한다(id/type/createdAt 불변)', () {
    final e = _entity(WorkspaceDrawingType.line, const [Point2(0, 0), Point2(1, 1)]);
    final moved = e.copyWith(points: const [Point2(0, 0), Point2(0.5, 0.5)]);
    expect(moved.id, e.id);
    expect(moved.type, e.type);
    expect(moved.createdAt, e.createdAt);
    expect(moved.points.last, const Point2(0.5, 0.5));
  });
}
