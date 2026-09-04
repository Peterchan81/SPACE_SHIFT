// SPACE SHIFT — PC2 CONTINUE: PLANAR GRAPH → PRODUCTION FLOOR DOMAIN
// INTEGRATION.
//
// buildFloorDomainFromPlanarGraph()가 옛 endpoint-only chain walker
// (buildFloorDomain, floor_domain_builder.dart 안에 격리된 채로 남아 있음)
// 대신 실제로 PlanarGraph의 half-edge/DCEL face 추출을 거쳐 FloorDomain을
// 만드는지 candidate 레벨에서 직접 검증한다(pixel 추출 없이 — 위상 자체의
// 정확성만 본다, planar_wall_graph_test.dart와 같은 스타일).

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
  PixelWallOrientation? orientation,
  bool isExterior = false,
  double thicknessPx = 6,
  double confidence = 0.8,
}) {
  final o = orientation ?? (y1 == y2 ? PixelWallOrientation.horizontal : PixelWallOrientation.vertical);
  return PixelWallCandidate(
    id: id,
    start: Point2(x1 / w, y1 / h),
    end: Point2(x2 / w, y2 / h),
    thicknessNormalized: thicknessPx / (o == PixelWallOrientation.horizontal ? h : w),
    orientation: o,
    isExterior: isExterior,
    baseConfidence: confidence,
    junctionSupport: 2,
    confidenceTier: PixelWallConfidenceTier.high,
    category: PixelWallCategory.structural,
    sourceSegmentIds: [id],
  );
}

void main() {
  group('buildFloorDomainFromPlanarGraph — production integration', () {
    test('닫힌 사각형 + 내부 파티션 — 내부 파티션은 outer loop로 승격되지 않는다', () {
      final candidates = [
        _seg(id: 'top', x1: 0, y1: 0, x2: 200, y2: 0, isExterior: true),
        _seg(id: 'bottom', x1: 0, y1: 100, x2: 200, y2: 100, isExterior: true),
        _seg(id: 'left', x1: 0, y1: 0, x2: 0, y2: 100, isExterior: true),
        _seg(id: 'right', x1: 200, y1: 0, x2: 200, y2: 100, isExterior: true),
        // 내부 파티션 — 두 T-junction을 만든다. isExterior=false인데도 옛
        // chain walker와 달리 이 값이 outer 판정에 전혀 관여하지 않는다.
        _seg(id: 'partition', x1: 100, y1: 0, x2: 100, y2: 100),
      ];

      final result = buildFloorDomainFromPlanarGraph(candidates: candidates, w: w, h: h);

      expect(result.isValid, isTrue, reason: result.failureReason ?? '');
      expect(result.sourceEvidenceLimited, isFalse);
      expect(result.graphVertexCount, greaterThan(0));
      expect(result.graphEdgeCount, greaterThan(0));
      // outer 1 + partition으로 나뉜 안쪽 방 2개 = face 3개.
      expect(result.graphFaceCount, 3);
      // partition이 top/bottom 두 벽의 body에 닿는 지점 = T-junction 2곳.
      expect(result.tJunctionCount, 2);

      final loop = result.loop!;
      final xs = loop.map((p) => p.x * w).toList();
      final ys = loop.map((p) => p.y * h).toList();
      // outer loop는 전체 bounding box(0..200, 0..100)와 일치해야 한다 —
      // partition의 x=100 선이 섞여 들어가면 안 된다.
      expect(xs.reduce((a, b) => a < b ? a : b), closeTo(0, 1));
      expect(xs.reduce((a, b) => a > b ? a : b), closeTo(200, 1));
      expect(ys.reduce((a, b) => a < b ? a : b), closeTo(0, 1));
      expect(ys.reduce((a, b) => a > b ? a : b), closeTo(100, 1));
    });

    test('열린(막다른) 내부 스텁 벽은 pruning되어 outer loop 폐합을 막지 않는다', () {
      final candidates = [
        _seg(id: 'top', x1: 0, y1: 0, x2: 200, y2: 0, isExterior: true),
        _seg(id: 'bottom', x1: 0, y1: 100, x2: 200, y2: 100, isExterior: true),
        _seg(id: 'left', x1: 0, y1: 0, x2: 0, y2: 100, isExterior: true),
        _seg(id: 'right', x1: 200, y1: 0, x2: 200, y2: 100, isExterior: true),
        // top 벽 중간에서 아래로 반만 내려오는 막다른 벽(T-junction +
        // dangling 끝) — 방을 나누지 않는 반쪽 칸막이.
        _seg(id: 'stub', x1: 100, y1: 0, x2: 100, y2: 50),
      ];

      final result = buildFloorDomainFromPlanarGraph(candidates: candidates, w: w, h: h);

      expect(result.isValid, isTrue, reason: result.failureReason ?? '');
      expect(result.sourceEvidenceLimited, isFalse);
      final loop = result.loop!;
      final xs = loop.map((p) => p.x * w).toList();
      final ys = loop.map((p) => p.y * h).toList();
      expect(xs.reduce((a, b) => a > b ? a : b), closeTo(200, 1));
      expect(ys.reduce((a, b) => a > b ? a : b), closeTo(100, 1));
      // 막다른 stub는 어떤 닫힌 face에도 속하지 못해 pruning된다 — 진단용
      // dangling edge로 보고되지만 outer 판정 자체는 막지 않는다.
      expect(result.unresolvedGaps, isNotEmpty);
    });

    test('서로 이어지지 않는 두 성분 — 가짜로 잇지 않고 GRAPH_VALID + SOURCE_EVIDENCE_LIMITED로 보고한다', () {
      final candidates = [
        _seg(id: 'top', x1: 0, y1: 0, x2: 200, y2: 0, isExterior: true),
        _seg(id: 'left', x1: 0, y1: 0, x2: 0, y2: 100, isExterior: true),
        _seg(id: 'bottom', x1: 0, y1: 100, x2: 200, y2: 100, isExterior: true),
        // right 벽 없음 — 대신 완전히 동떨어진(안 닿는) 벽 조각 하나만 존재.
        _seg(id: 'island', x1: 260, y1: 20, x2: 260, y2: 80, isExterior: true),
      ];

      final result = buildFloorDomainFromPlanarGraph(candidates: candidates, w: w, h: h);

      expect(result.isValid, isFalse, reason: 'evidence가 없는데 bbox/convex hull로 억지 폐합하면 안 된다');
      expect(result.sourceEvidenceLimited, isTrue);
      expect(result.failureReason, isNotNull);
      expect(result.graphVertexCount, greaterThan(0), reason: 'PlanarGraph 자체는 유효(GRAPH_VALID) — vertex/edge는 만들어졌어야 한다');
      expect(result.graphEdgeCount, greaterThan(0));
    });

    test('구조 벽이 하나도 없으면 PlanarGraph 자체가 비어 있다고 정직하게 보고한다', () {
      final result = buildFloorDomainFromPlanarGraph(candidates: const [], w: w, h: h);
      expect(result.isValid, isFalse);
      expect(result.sourceEvidenceLimited, isFalse, reason: '구조 벽 자체가 없는 것은 evidence-limited가 아니라 입력이 없는 것');
      expect(result.graphVertexCount, 0);
      expect(result.graphEdgeCount, 0);
    });
  });
}
