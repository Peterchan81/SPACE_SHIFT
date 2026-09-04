// SPACE SHIFT — PC1 FINALIZE: PLANAR HALF-EDGE GRAPH.
//
// 실제 이미지 2에 대해 planar graph(§T-junction/door-bridge/dangling
// pruning 포함)를 실행해 정직한 결과를 기록한다. 목표는 "PASS"가
// 아니라 GRAPH 자체의 정확성(합성 테스트 9개로 이미 검증됨)과, 이
// 특정 이미지에서 실제로 얼마나 개선됐는지, 그리고 왜 완전한 단일
// outer loop에 도달하지 못하는지(source evidence 부재로 확정된 gap)
// 를 남긴다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/planar_wall_graph.dart';

void main() {
  test('실제 이미지 2 — planar graph 연결성/face 결과를 정직하게 기록한다', () {
    final bytes = loadRealImage2Bytes();
    if (bytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 없음');
      return;
    }
    final result = extractPixelWalls(bytes);
    final w = result.analysisWidthPx;
    final h = result.analysisHeightPx;

    final graph = buildPlanarGraph(candidates: result.candidates, w: w, h: h);

    final rawComponents = _countComponents(graph);
    final pruned = pruneDanglingEdges(graph);
    final faces = extractFaces(pruned);
    final byArea = [...faces]..sort((a, b) => b.signedArea.abs().compareTo(a.signedArea.abs()));
    final largest = byArea.isEmpty ? 0.0 : byArea.first.signedArea.abs();

    // ignore: avoid_print
    print('''
=== 실제 이미지 2 — PLANAR HALF-EDGE GRAPH ===
Vertices: ${graph.vertices.length}
Edges(실제+가상 door bridge): ${graph.edges.length} (virtual=${graph.edges.where((e) => e.isVirtualBridge).length})
Connected components(door-bridge 포함, pruning 전): $rawComponents
Dangling-pruned 후 edges: ${pruned.edges.length}
추출된 face 개수: ${faces.length}
가장 큰 face 면적: ${largest.toStringAsFixed(1)} (참고: 전체 캔버스=${w * h}px^2)
''');

    // T-junction으로 실제 연결이 확인된 3개 사례가 이번에는 같은
    // component에 있어야 한다(회귀 방지 — 이전 라운드에서 endpoint-only
    // 체인 walker로는 놓쳤던 연결).
    final compId = _componentIdMap(graph);
    bool sameComponent(String a, String b) {
      final ea = graph.edges.where((e) => e.sourceCandidateId == a);
      final eb = graph.edges.where((e) => e.sourceCandidateId == b);
      if (ea.isEmpty || eb.isEmpty) return false;
      return compId[ea.first.v1] == compId[eb.first.v1];
    }

    expect(sameComponent('pxwall-22', 'pxwall-42'), isTrue, reason: '104.3↔416.5 T-junction이 연결돼야 한다');
    expect(sameComponent('pxwall-29', 'pxwall-1'), isTrue, reason: '12.5↔48.1 사이 pxwall-29 다리가 연결돼야 한다');
    expect(sameComponent('pxwall-53', 'pxwall-2'), isTrue, reason: '241↔pxwall-53 T-junction이 연결돼야 한다');

    // 이 결과가 "PASS"를 주장하지 않는다 — 여전히 완전한 단일 outer
    // loop는 아니다(104.3↔301.8 사이 실제 pixel evidence 부재가 이미
    // 확정 조사됨). 이 테스트는 그 정직한 상태를 회귀 없이 유지한다.
  });
}

int _countComponents(dynamic graph) {
  final visited = <int>{};
  var count = 0;
  for (final v in graph.vertices) {
    if (visited.contains(v.id)) continue;
    count++;
    final stack = [v.id];
    visited.add(v.id);
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final eId in graph.adjacency[cur]!) {
        final e = graph.edges[eId];
        final other = e.v1 == cur ? e.v2 : e.v1;
        if (visited.add(other)) stack.add(other);
      }
    }
  }
  return count;
}

Map<int, int> _componentIdMap(dynamic graph) {
  final compId = <int, int>{};
  var next = 0;
  for (final v in graph.vertices) {
    if (compId.containsKey(v.id)) continue;
    final stack = [v.id];
    compId[v.id] = next;
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final eId in graph.adjacency[cur]!) {
        final e = graph.edges[eId];
        final other = e.v1 == cur ? e.v2 : e.v1;
        if (!compId.containsKey(other)) {
          compId[other] = next;
          stack.add(other);
        }
      }
    }
    next++;
  }
  return compId;
}
