// SPACE SHIFT — PC1 FINALIZE: PLANAR HALF-EDGE GRAPH.
// endpoint-to-body(T-junction)/L/X junction과 face 추출을 합성 데이터로
// 검증한다. "확정 exterior 두 지점을 잇는 벽은 승격" 같은 위상 규칙은
// 쓰지 않는다 — 대신 전체 구조 벽으로 실제 planar graph를 만들고,
// 그래프 스스로 만들어내는 "바깥쪽 face"가 곧 외곽이라는 것만 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/planar_wall_graph.dart';

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
  group('junction detection + splitting', () {
    test('TEST 1: 수평 body 중앙에 세로 endpoint가 닿는 T-junction — 수평 segment가 split된다', () {
      final candidates = [
        _seg(id: 'horiz', x1: 0, y1: 50, x2: 100, y2: 50),
        _seg(id: 'vert-down', x1: 50, y1: 50, x2: 50, y2: 100),
      ];
      final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
      // horiz(0-100)가 x=50에서 split돼 2개 edge(0-50, 50-100)가 되고,
      // vert-down과 함께 그 지점에서 3개 edge가 만나는 vertex가 있어야 한다.
      final splitPoint = graph.vertices.firstWhere((v) => (v.xPx - 50).abs() < 2 && (v.yPx - 50).abs() < 2);
      expect(graph.adjacency[splitPoint.id]!.length, 3, reason: 'T-junction vertex에는 3개 edge(좌/우/아래)가 모여야 한다');
    });

    test('TEST 2: 반대 방향 T-junction(세로 endpoint가 위에서 닿음)도 동일하게 처리된다', () {
      final candidates = [
        _seg(id: 'horiz', x1: 0, y1: 50, x2: 100, y2: 50),
        _seg(id: 'vert-up', x1: 50, y1: 0, x2: 50, y2: 50),
      ];
      final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
      final splitPoint = graph.vertices.firstWhere((v) => (v.xPx - 50).abs() < 2 && (v.yPx - 50).abs() < 2);
      expect(graph.adjacency[splitPoint.id]!.length, 3);
    });

    test('TEST 3: L-junction(endpoint-endpoint)은 split 없이 그대로 연결된다', () {
      final candidates = [
        _seg(id: 'h', x1: 0, y1: 0, x2: 100, y2: 0),
        _seg(id: 'v', x1: 100, y1: 0, x2: 100, y2: 100),
      ];
      final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
      expect(graph.edges, hasLength(2));
      final corner = graph.vertices.firstWhere((v) => (v.xPx - 100).abs() < 2 && (v.yPx - 0).abs() < 2);
      expect(graph.adjacency[corner.id]!.length, 2);
    });

    test('TEST 4: X-junction(십자 교차) — 두 segment 모두 2개씩 split된다', () {
      final candidates = [
        _seg(id: 'h', x1: 0, y1: 50, x2: 100, y2: 50),
        _seg(id: 'v', x1: 50, y1: 0, x2: 50, y2: 100),
      ];
      final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
      final center = graph.vertices.firstWhere((v) => (v.xPx - 50).abs() < 2 && (v.yPx - 50).abs() < 2);
      expect(graph.adjacency[center.id]!.length, 4, reason: 'X-junction에는 4방향 edge가 모여야 한다');
      expect(graph.edges, hasLength(4));
    });

    test('TEST 5: 가까워 보이지만 실제로 안 닿는 두 segment는 연결되지 않는다', () {
      final candidates = [
        _seg(id: 'h', x1: 0, y1: 50, x2: 100, y2: 50),
        // body와 40px 떨어진(허용오차 10px 초과) endpoint.
        _seg(id: 'v-far', x1: 50, y1: 90, x2: 50, y2: 150),
      ];
      final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
      // horiz는 split되지 않아야 하고(자기 두 끝점만), 두 segment는 서로 다른 vertex를 쓴다.
      expect(graph.edges, hasLength(2));
      final horizEdge = graph.edges.firstWhere((e) => e.sourceCandidateId == 'h');
      final vFarEdge = graph.edges.firstWhere((e) => e.sourceCandidateId == 'v-far');
      final sharedVertex = {horizEdge.v1, horizEdge.v2}.intersection({vFarEdge.v1, vFarEdge.v2});
      expect(sharedVertex, isEmpty, reason: '실제로 안 닿는 segment는 vertex를 공유하면 안 된다');
    });

    test('TEST 6: reviewNeeded(화살표/텍스트 등 비구조) candidate는 phantom junction을 만들지 않는다', () {
      final reviewNeededArrow = PixelWallCandidate(
        id: 'arrow',
        start: Point2(50 / w, 20 / h),
        end: Point2(50 / w, 50 / h),
        thicknessNormalized: 3 / w,
        orientation: PixelWallOrientation.vertical,
        isExterior: true, // 화살표가 잘못 exterior로 태깅된 경우를 흉내.
        baseConfidence: 0.3,
        junctionSupport: 0,
        confidenceTier: PixelWallConfidenceTier.low,
        category: PixelWallCategory.reviewNeeded, // 구조 벽 아님으로 이미 분류됨.
        sourceSegmentIds: const ['arrow'],
      );
      final candidates = [
        _seg(id: 'horiz', x1: 0, y1: 50, x2: 100, y2: 50),
        reviewNeededArrow,
      ];
      final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
      // reviewNeeded는 애초에 graph 입력에서 제외돼야 한다 — horiz가
      // split되지 않고 원래 2개 끝점 그대로여야 한다.
      final horizEdges = graph.edges.where((e) => e.sourceCandidateId == 'horiz');
      expect(horizEdges, hasLength(1), reason: 'reviewNeeded candidate 때문에 구조 벽이 split되면 안 된다');
    });

    test('TEST 7: junction split 후 provenance/confidence/두께가 그대로 유지된다', () {
      final candidates = [
        _seg(id: 'horiz', x1: 0, y1: 50, x2: 100, y2: 50, thicknessPx: 12, confidence: 0.77),
        _seg(id: 'vert-down', x1: 50, y1: 50, x2: 50, y2: 100),
      ];
      final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
      final horizPieces = graph.edges.where((e) => e.sourceCandidateId == 'horiz').toList();
      expect(horizPieces, hasLength(2), reason: 'horiz는 T-junction에서 2조각으로 split돼야 한다');
      for (final piece in horizPieces) {
        expect(piece.thicknessPx, closeTo(12, 0.01));
        expect(piece.confidence, closeTo(0.77, 0.01));
      }
    });
  });

  group('face extraction', () {
    test('TEST 8: 닫힌 사각형 + 내부 T 파티션 — 바깥쪽 face 하나 + 안쪽 face 2개가 나온다', () {
      final candidates = [
        _seg(id: 'top', x1: 0, y1: 0, x2: 200, y2: 0),
        _seg(id: 'bottom', x1: 0, y1: 100, x2: 200, y2: 100),
        _seg(id: 'left', x1: 0, y1: 0, x2: 0, y2: 100),
        _seg(id: 'right', x1: 200, y1: 0, x2: 200, y2: 100),
        _seg(id: 'partition', x1: 100, y1: 0, x2: 100, y2: 100), // 위아래 벽을 가로지르는 내부 칸막이(T-junction 2곳).
      ];
      final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
      final faces = extractFaces(graph);
      // 바깥쪽 face 1개(신호 반대 부호, 소수) + 안쪽 face 2개(같은 부호, 다수).
      final outer = findOuterFaces(faces);
      expect(outer, hasLength(1));
      // 바깥쪽 face의 절대 면적이 전체 bounding box(200*100=20000)와 일치해야 한다.
      expect(outer.first.signedArea.abs(), closeTo(20000, 1));

      final inner = faces.where((f) => !outer.contains(f)).toList();
      expect(inner, hasLength(2), reason: '파티션으로 나뉜 왼쪽/오른쪽 방 2개가 안쪽 face로 나와야 한다');
      for (final f in inner) {
        expect(f.signedArea.abs(), closeTo(10000, 1), reason: '각 방은 100x100=10000이어야 한다');
      }
    });

    test('TEST 9: 열려 있는(닫히지 않은) 경계는 억지로 닫힌 outer face로 판정되지 않는다', () {
      final candidates = [
        _seg(id: 'top', x1: 0, y1: 0, x2: 200, y2: 0),
        _seg(id: 'left', x1: 0, y1: 0, x2: 0, y2: 100),
        // bottom/right 없음 — 열린 경계.
      ];
      final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
      final faces = extractFaces(graph);
      // 닫힌 3점 이상의 진짜 polygon face가 없어야 한다(단순 dangling
      // edge 왕복만 존재 — 최소 3개 vertex 요구 조건에 걸려 제외됨).
      expect(faces, isEmpty, reason: '열린 경계에서 가짜로 닫힌 face를 만들면 안 된다');
    });
  });
}
