// SS CAD TEST — Wall Consolidation & Topology Closure WO.
//
// [consolidateWallSystems]는 [buildWallSystems](이미 검증된 코드)가 만든
// 그룹을 door/imageBreak gap만 이어 붙이고, open-plan/notConnected gap은
// 원본에 없는 벽을 지어내지 않기 위해 그대로 끊어 둔다는 원칙을
// 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/wall_system_consolidator.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/wall_system.dart';

const w = 1000;
const h = 1000;

PixelWallCandidate _horizontal(String id, double x1, double x2, double y, {bool isExterior = true}) {
  return PixelWallCandidate(
    id: id,
    start: Point2(x1 / w, y / h),
    end: Point2(x2 / w, y / h),
    thicknessNormalized: 10 / h,
    orientation: PixelWallOrientation.horizontal,
    isExterior: isExterior,
    baseConfidence: 0.9,
    junctionSupport: 0,
    confidenceTier: PixelWallConfidenceTier.high,
    category: PixelWallCategory.structural,
    sourceSegmentIds: [id],
  );
}

void main() {
  test('door 크기 gap(4~65px)은 하나의 연속된 벽으로 병합된다', () {
    // x: 100~300, gap 30px(300~330), 330~500 — 같은 y=100.
    final candidates = [
      _horizontal('a', 100, 300, 100),
      _horizontal('b', 330, 500, 100),
    ];
    final systems = buildWallSystems(candidates: candidates, w: w, h: h);
    expect(systems, hasLength(1));
    expect(systems.single.gaps.single.kind, GapKind.doorOpening);

    final consolidated = consolidateWallSystems(systems, w: w, h: h);
    expect(consolidated, hasLength(1), reason: '문 크기 gap은 하나의 물리 벽으로 이어져야 한다');
    final wall = consolidated.single;
    expect(wall.start.x * w, closeTo(100, 0.1));
    expect(wall.end.x * w, closeTo(500, 0.1));
  });

  test('아주 작은 끊김(imageBreak, <=4px)도 하나로 병합된다', () {
    final candidates = [
      _horizontal('a', 100, 300, 100),
      _horizontal('b', 302, 500, 100),
    ];
    final systems = buildWallSystems(candidates: candidates, w: w, h: h);
    expect(systems.single.gaps.single.kind, GapKind.imageBreak);
    final consolidated = consolidateWallSystems(systems, w: w, h: h);
    expect(consolidated, hasLength(1));
  });

  test('open-plan 크기 gap(내벽, >65px)은 절대 잇지 않고 별도 벽 2개로 남는다', () {
    final candidates = [
      _horizontal('a', 100, 300, 100, isExterior: false),
      _horizontal('b', 500, 700, 100, isExterior: false),
    ];
    final systems = buildWallSystems(candidates: candidates, w: w, h: h);
    expect(systems.single.gaps.single.kind, GapKind.openPlan);
    final consolidated = consolidateWallSystems(systems, w: w, h: h);
    expect(consolidated, hasLength(2), reason: 'open-plan gap을 이으면 원본에 없는 벽을 지어내는 것이다');
    expect(consolidated[0].end.x * w, closeTo(300, 0.1));
    expect(consolidated[1].start.x * w, closeTo(500, 0.1));
  });

  test('notConnected 크기 gap(외벽, >65px)도 절대 잇지 않는다', () {
    final candidates = [
      _horizontal('a', 100, 300, 100),
      _horizontal('b', 500, 700, 100),
    ];
    final systems = buildWallSystems(candidates: candidates, w: w, h: h);
    expect(systems.single.gaps.single.kind, GapKind.notConnected);
    final consolidated = consolidateWallSystems(systems, w: w, h: h);
    expect(consolidated, hasLength(2));
  });

  test('여러 door gap이 섞인 긴 벽은 전체가 하나로 병합된다(중간에 문이 여러 개 있어도)', () {
    final candidates = [
      _horizontal('a', 0, 100, 200),
      _horizontal('b', 130, 250, 200), // door gap(30px).
      _horizontal('c', 280, 400, 200), // door gap(30px).
    ];
    final systems = buildWallSystems(candidates: candidates, w: w, h: h);
    expect(systems.single.gaps.map((g) => g.kind), everyElement(GapKind.doorOpening));
    final consolidated = consolidateWallSystems(systems, w: w, h: h);
    expect(consolidated, hasLength(1));
    expect(consolidated.single.start.x * w, closeTo(0, 0.1));
    expect(consolidated.single.end.x * w, closeTo(400, 0.1));
  });

  test('door gap과 open-plan gap이 섞여 있으면 open-plan 지점에서만 끊긴다', () {
    final candidates = [
      _horizontal('a', 0, 100, 200, isExterior: false),
      _horizontal('b', 130, 250, 200, isExterior: false), // door gap(30px) — 이어짐.
      _horizontal('c', 500, 600, 200, isExterior: false), // open-plan gap(250px) — 끊김.
    ];
    final systems = buildWallSystems(candidates: candidates, w: w, h: h);
    final consolidated = consolidateWallSystems(systems, w: w, h: h);
    expect(consolidated, hasLength(2));
    expect(consolidated[0].start.x * w, closeTo(0, 0.1));
    expect(consolidated[0].end.x * w, closeTo(250, 0.1));
    expect(consolidated[1].start.x * w, closeTo(500, 0.1));
    expect(consolidated[1].end.x * w, closeTo(600, 0.1));
  });

  test('겹치는(overlap) segment 하나는 그대로 하나의 벽이 된다', () {
    final candidates = [_horizontal('a', 100, 400, 100)];
    final systems = buildWallSystems(candidates: candidates, w: w, h: h);
    final consolidated = consolidateWallSystems(systems, w: w, h: h);
    expect(consolidated, hasLength(1));
    expect(consolidated.single.start.x * w, closeTo(100, 0.1));
    expect(consolidated.single.end.x * w, closeTo(400, 0.1));
  });

  test('빈 systems 목록은 빈 벽 목록을 반환한다(예외 없음)', () {
    expect(consolidateWallSystems(const [], w: w, h: h), isEmpty);
  });
}
