// SPACE SHIFT — PC1 CONTINUE: FLOOR DOMAIN FIRST.
// 합성 PixelWallCandidate로 wall system 병합/gap 분류/FloorDomain
// virtual-boundary 다리 놓기를 검증한다(실제 이미지 디코딩 불필요).

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/floor_domain_builder.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/wall_system.dart';

const w = 400;
const h = 300;

PixelWallCandidate _c({
  required String id,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  bool isExterior = false,
  PixelWallOrientation orientation = PixelWallOrientation.horizontal,
}) {
  return PixelWallCandidate(
    id: id,
    start: Point2(x1 / w, y1 / h),
    end: Point2(x2 / w, y2 / h),
    thicknessNormalized: 6 / w,
    orientation: orientation,
    isExterior: isExterior,
    baseConfidence: 0.8,
    junctionSupport: 2,
    confidenceTier: PixelWallConfidenceTier.high,
    category: PixelWallCategory.structural,
    sourceSegmentIds: [id],
  );
}

void main() {
  group('classifyGap', () {
    test('아주 작은 gap은 imageBreak', () {
      expect(classifyGap(2, isExterior: true), GapKind.imageBreak);
    });
    test('문 크기 gap은 doorOpening', () {
      expect(classifyGap(30, isExterior: true), GapKind.doorOpening);
      expect(classifyGap(30, isExterior: false), GapKind.doorOpening);
    });
    test('넓은 내부 gap은 openPlan', () {
      expect(classifyGap(120, isExterior: false), GapKind.openPlan);
    });
    test('넓은 외벽 gap은 notConnected(조용히 잇지 않음)', () {
      expect(classifyGap(120, isExterior: true), GapKind.notConnected);
    });
  });

  group('buildWallSystems', () {
    test('같은 축 위 여러 segment가 하나의 system으로 묶이고 gap이 기록된다', () {
      final candidates = [
        _c(id: 'b1', x1: 20, y1: 280, x2: 100, y2: 280, isExterior: true),
        _c(id: 'b2', x1: 130, y1: 280, x2: 250, y2: 280, isExterior: true), // gap=30 → door
      ];
      final systems = buildWallSystems(candidates: candidates, w: w, h: h);
      expect(systems, hasLength(1));
      expect(systems.first.segments, hasLength(2));
      expect(systems.first.gaps, hasLength(1));
      expect(systems.first.gaps.first.kind, GapKind.doorOpening);
    });
  });

  group('buildFloorDomain', () {
    test('문 크기 gap은 virtual boundary로 이어져 FloorDomain이 닫힌다', () {
      final candidates = [
        _c(id: 'top', x1: 20, y1: 20, x2: 220, y2: 20, isExterior: true),
        _c(id: 'left', x1: 20, y1: 20, x2: 20, y2: 220, orientation: PixelWallOrientation.vertical, isExterior: true),
        _c(id: 'right', x1: 220, y1: 20, x2: 220, y2: 220, orientation: PixelWallOrientation.vertical, isExterior: true),
        _c(id: 'bottom1', x1: 20, y1: 220, x2: 100, y2: 220, isExterior: true),
        _c(id: 'bottom2', x1: 130, y1: 220, x2: 220, y2: 220, isExterior: true), // gap=30 → door
      ];
      final systems = buildWallSystems(candidates: candidates, w: w, h: h);
      final result = buildFloorDomain(wallSystems: systems, w: w, h: h);
      expect(result.isValid, isTrue, reason: result.failureReason ?? '');
      expect(result.virtualBoundaries, isNotEmpty);
      expect(result.unresolvedGaps, isEmpty);
    });

    test('외벽에 문 범위를 넘는 gap이 있으면 조용히 잇지 않고 실패로 보고한다', () {
      final candidates = [
        _c(id: 'top', x1: 20, y1: 20, x2: 220, y2: 20, isExterior: true),
        _c(id: 'left', x1: 20, y1: 20, x2: 20, y2: 220, orientation: PixelWallOrientation.vertical, isExterior: true),
        _c(id: 'right', x1: 220, y1: 20, x2: 220, y2: 220, orientation: PixelWallOrientation.vertical, isExterior: true),
        _c(id: 'bottom1', x1: 20, y1: 220, x2: 60, y2: 220, isExterior: true),
        _c(id: 'bottom2', x1: 190, y1: 220, x2: 220, y2: 220, isExterior: true), // gap=130 → notConnected
      ];
      final systems = buildWallSystems(candidates: candidates, w: w, h: h);
      final result = buildFloorDomain(wallSystems: systems, w: w, h: h);
      expect(result.isValid, isFalse);
      expect(result.unresolvedGaps, isNotEmpty);
      expect(result.unresolvedGaps.first.kind, GapKind.notConnected);
    });

    test('첫 run이 체인의 중간(elbow)이어도 양방향으로 걸어 모든 run을 놓치지 않는다(PC1 CONTINUE §22 카테고리 E 회귀 방지)', () {
      // A(수직, 위)-B(수평, 중간)-C(수직, 아래) 순서로 이어지는 열린
      // 사슬. buildWallSystems는 항상 horizontal을 먼저 처리하므로 B가
      // "첫 run"이 된다 — 이전 구현은 forward(끝 방향)로만 걸어
      // C까지만 잇고 A는 "연결 안 됨"으로 잘못 보고했다.
      final candidates = [
        _c(id: 'A', x1: 50, y1: 0, x2: 50, y2: 50, orientation: PixelWallOrientation.vertical, isExterior: true),
        _c(id: 'B', x1: 50, y1: 50, x2: 100, y2: 50, isExterior: true),
        _c(id: 'C', x1: 100, y1: 50, x2: 100, y2: 100, orientation: PixelWallOrientation.vertical, isExterior: true),
      ];
      final systems = buildWallSystems(candidates: candidates, w: w, h: h);
      final result = buildFloorDomain(wallSystems: systems, w: w, h: h);
      // 열린 사슬이라 닫히지는 않지만(의도적으로 loop가 아님), 실패
      // 사유가 "run이 연결되지 않음"이 아니라 "닫히지 않음"이어야 한다
      // — 즉 3개 run 모두 하나의 경로로는 이어졌다는 뜻.
      expect(result.isValid, isFalse);
      expect(result.failureReason, contains('닫히지 않음'), reason: '양방향 연결에 실패하면 여기서 "연결되지 않음"으로 잘못 보고된다');
    });
  });
}
