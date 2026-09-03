// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
//
// GptWallTopologySolver 단위 테스트 — "Space는 bounding box가 아니라
// wall topology에서 유도된다"는 핵심 요구사항의 알고리즘 자체를
// 검증한다. JSON은 순수 테스트 데이터다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/gpt_vision_v1/gpt_cad_schema.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v1/gpt_wall_topology_solver.dart';

GptWall _wall(String id, List<String> cornerIds) => GptWall(
      id: id,
      type: GptWallType.interior,
      cornerIds: cornerIds,
      confidence: 0.9,
    );

GptSpace _space(String id, List<String> boundaryWallIds) => GptSpace(
      id: id,
      label: 'test',
      semanticType: 'living',
      boundaryWallIds: boundaryWallIds,
      confidence: 0.9,
    );

void main() {
  const solver = GptWallTopologySolver();

  test('사각형 4개 벽이 정확히 닫힌 루프를 이룬다', () {
    final walls = [
      _wall('W1', ['C1', 'C2']),
      _wall('W2', ['C2', 'C3']),
      _wall('W3', ['C3', 'C4']),
      _wall('W4', ['C4', 'C1']),
    ];
    final result = solver.deriveSpaceLoop(_space('S1', ['W1', 'W2', 'W3', 'W4']), walls);
    expect(result.closed, isTrue);
    expect(result.orderedCornerIds, hasLength(4));
    expect(result.orderedCornerIds.toSet(), {'C1', 'C2', 'C3', 'C4'});
  });

  test('L자형(6개 corner, 6개 변)도 하나의 폐곡선으로 정확히 유도된다', () {
    final walls = [
      _wall('W1', ['C1', 'C2']),
      _wall('W2', ['C2', 'C3']),
      _wall('W3', ['C3', 'C4']),
      _wall('W4', ['C4', 'C5']),
      _wall('W5', ['C5', 'C6']),
      _wall('W6', ['C6', 'C1']),
    ];
    final result = solver.deriveSpaceLoop(_space('S1', ['W1', 'W2', 'W3', 'W4', 'W5', 'W6']), walls);
    expect(result.closed, isTrue);
    expect(result.orderedCornerIds, hasLength(6));
  });

  test('여러 corner를 가진 polyline wall(꺾인 벽 하나)도 올바르게 풀린다', () {
    // W1이 C1→C2→C3(꺾인 벽 하나), 나머지가 나머지 두 변.
    final walls = [
      _wall('W1', ['C1', 'C2', 'C3']),
      _wall('W2', ['C3', 'C4']),
      _wall('W3', ['C4', 'C1']),
    ];
    final result = solver.deriveSpaceLoop(_space('S1', ['W1', 'W2', 'W3']), walls);
    expect(result.closed, isTrue);
    expect(result.orderedCornerIds, hasLength(4));
  });

  test('끊긴 구간(열린 경로)은 실패로 보고하고 억지로 잇지 않는다', () {
    final walls = [
      _wall('W1', ['C1', 'C2']),
      _wall('W2', ['C2', 'C3']),
      _wall('W3', ['C3', 'C4']),
      // C4→C1 벽이 없음 — 닫히지 않음.
    ];
    final result = solver.deriveSpaceLoop(_space('S1', ['W1', 'W2', 'W3']), walls);
    expect(result.closed, isFalse);
    expect(result.failureReason, isNotNull);
  });

  test('분기(한 corner에 3개 이상 연결)는 실패로 보고한다', () {
    final walls = [
      _wall('W1', ['C1', 'C2']),
      _wall('W2', ['C2', 'C3']),
      _wall('W3', ['C3', 'C1']),
      _wall('W4', ['C2', 'C4']), // C2에 세 번째 연결 — 분기
    ];
    final result = solver.deriveSpaceLoop(_space('S1', ['W1', 'W2', 'W3', 'W4']), walls);
    expect(result.closed, isFalse);
    expect(result.failureReason, contains('expected exactly 2'));
  });

  test('존재하지 않는 wall을 참조하면 실패로 보고한다', () {
    final walls = [_wall('W1', ['C1', 'C2'])];
    final result = solver.deriveSpaceLoop(_space('S1', ['W1', 'W99']), walls);
    expect(result.closed, isFalse);
    expect(result.failureReason, contains('not found'));
  });

  test('두 개의 분리된 사각형(연결 안 됨)은 실패로 보고한다', () {
    final walls = [
      _wall('W1', ['C1', 'C2']),
      _wall('W2', ['C2', 'C3']),
      _wall('W3', ['C3', 'C4']),
      _wall('W4', ['C4', 'C1']),
      _wall('W5', ['C10', 'C11']),
      _wall('W6', ['C11', 'C12']),
      _wall('W7', ['C12', 'C13']),
      _wall('W8', ['C13', 'C10']),
    ];
    final result = solver.deriveSpaceLoop(
      _space('S1', ['W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7', 'W8']),
      walls,
    );
    expect(result.closed, isFalse);
  });
}
