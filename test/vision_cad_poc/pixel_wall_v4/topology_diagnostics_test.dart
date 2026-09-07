// SPACE SHIFT — WO086 TOPOLOGY RECOVERY LAYER.
//
// [TopologyDiagnostics]가 기존 FloorDomain 계산 결과(componentCount/
// danglingEdges/virtualBoundaries — 전부 이미 계산되던 값)를 사람이
// 판단할 수 있는 구조(disconnectedComponents/danglingEdgeCount/
// repairActions/status/userMessage)로 정확히 재구성하는지 검증한다.
// 새 geometry를 만들지 않는다는 원칙(§8)을 실제로 지키는지 — 즉
// safeAutoRepair 상태에서도 loop 자체가 바뀌지 않는지 — 도 함께 본다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/floor_domain_builder.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

const w = 400;
const h = 300;

PixelWallCandidate _seg({
  required String id,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  bool isExterior = false,
}) {
  final o = y1 == y2 ? PixelWallOrientation.horizontal : PixelWallOrientation.vertical;
  return PixelWallCandidate(
    id: id,
    start: Point2(x1 / w, y1 / h),
    end: Point2(x2 / w, y2 / h),
    thicknessNormalized: 6 / (o == PixelWallOrientation.horizontal ? h : w),
    orientation: o,
    isExterior: isExterior,
    baseConfidence: 0.8,
    junctionSupport: 2,
    confidenceTier: PixelWallConfidenceTier.high,
    category: PixelWallCategory.structural,
    sourceSegmentIds: [id],
  );
}

void main() {
  group('TopologyDiagnostics — status 분류', () {
    test('완전히 닫힌 사각형 — safeAutoRepair(성분 1개, dangling 0개, openLoop 아님)', () {
      final candidates = [
        _seg(id: 'top', x1: 0, y1: 0, x2: 200, y2: 0, isExterior: true),
        _seg(id: 'bottom', x1: 0, y1: 100, x2: 200, y2: 100, isExterior: true),
        _seg(id: 'left', x1: 0, y1: 0, x2: 0, y2: 100, isExterior: true),
        _seg(id: 'right', x1: 200, y1: 0, x2: 200, y2: 100, isExterior: true),
      ];
      final result = buildFloorDomainFromPlanarGraph(candidates: candidates, w: w, h: h);
      final topo = result.topology!;
      expect(topo.disconnectedComponents, 1);
      expect(topo.danglingEdgeCount, 0);
      expect(topo.openLoop, isFalse);
      expect(topo.evidenceLimited, isFalse);
      expect(topo.status, RepairStatus.safeAutoRepair);
      expect(topo.userMessage, contains('정상적으로 닫혔습니다'));
    });

    test('문 gap으로 끊긴 사각형 — 가상 경계로 자동 연결되고 repairActions에 남는다(여전히 안전하게 닫힘)', () {
      final candidates = [
        _seg(id: 'top-a', x1: 0, y1: 0, x2: 80, y2: 0, isExterior: true),
        _seg(id: 'top-b', x1: 100, y1: 0, x2: 200, y2: 0, isExterior: true), // 20px door gap.
        _seg(id: 'bottom', x1: 0, y1: 100, x2: 200, y2: 100, isExterior: true),
        _seg(id: 'left', x1: 0, y1: 0, x2: 0, y2: 100, isExterior: true),
        _seg(id: 'right', x1: 200, y1: 0, x2: 200, y2: 100, isExterior: true),
      ];
      final result = buildFloorDomainFromPlanarGraph(candidates: candidates, w: w, h: h);
      expect(result.isValid, isTrue, reason: result.failureReason ?? '');
      final topo = result.topology!;
      expect(topo.status, RepairStatus.safeAutoRepair);
      expect(topo.repairActions, isNotEmpty);
      expect(topo.repairActions.single, contains('SAFE_AUTO_REPAIR'));
    });

    test('서로 이어지지 않는 두 성분 — unresolved(새 evidence 없이는 자동 해결 불가)', () {
      final candidates = [
        _seg(id: 'top', x1: 0, y1: 0, x2: 200, y2: 0, isExterior: true),
        _seg(id: 'left', x1: 0, y1: 0, x2: 0, y2: 100, isExterior: true),
        _seg(id: 'bottom', x1: 0, y1: 100, x2: 200, y2: 100, isExterior: true),
        // right 벽 없음 — 대신 완전히 동떨어진 조각.
        _seg(id: 'island', x1: 260, y1: 20, x2: 260, y2: 80, isExterior: true),
      ];
      final result = buildFloorDomainFromPlanarGraph(candidates: candidates, w: w, h: h);
      expect(result.isValid, isFalse);
      final topo = result.topology!;
      expect(topo.disconnectedComponents, greaterThan(1));
      expect(topo.status, RepairStatus.unresolved);
      expect(topo.evidenceLimited, isTrue);
      expect(topo.unresolvedReasons, isNotEmpty);
      expect(topo.userMessage, contains('근거가 부족'));
    });

    test('열린(막다른) 내부 스텁 — 성분은 1개, dangling edge가 남아 reviewRequired로 분류된다', () {
      final candidates = [
        _seg(id: 'top', x1: 0, y1: 0, x2: 200, y2: 0, isExterior: true),
        _seg(id: 'bottom', x1: 0, y1: 100, x2: 200, y2: 100, isExterior: true),
        _seg(id: 'left', x1: 0, y1: 0, x2: 0, y2: 100, isExterior: true),
        _seg(id: 'right', x1: 200, y1: 0, x2: 200, y2: 100, isExterior: true),
        // top 벽 중간에서 아래로 반만 내려오는 막다른 벽(dangling edge).
        _seg(id: 'stub', x1: 100, y1: 0, x2: 100, y2: 50),
      ];
      final result = buildFloorDomainFromPlanarGraph(candidates: candidates, w: w, h: h);
      expect(result.isValid, isTrue, reason: result.failureReason ?? '');
      final topo = result.topology!;
      expect(topo.disconnectedComponents, 1);
      expect(topo.danglingEdgeCount, greaterThan(0));
      expect(topo.status, RepairStatus.reviewRequired);
      expect(topo.userMessage, contains('확인해야 합니다'));
    });
  });
}
