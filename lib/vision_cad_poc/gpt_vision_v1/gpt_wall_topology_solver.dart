import 'gpt_cad_schema.dart';

/// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
///
/// [GptSpace.boundaryWallIds]에서 실제로 닫힌 폴리곤을 유도한다(설계
/// 10번 — "Space의 primary geometry는 bounding rectangle가 아니다").
/// 각 wall의 [GptWall.cornerIds]를 변(edge)들로 풀어, 그 edge들이
/// 정확히 하나의 단순 폐곡선(모든 corner degree=2, 하나의 연결
/// 컴포넌트)을 이루는지 확인하고 그 순서대로 corner id 목록을
/// 돌려준다. 이루지 못하면(끊긴 구간/분기/2개 이상 컴포넌트)
/// 억지로 이어붙이지 않고 실패로 보고한다 — 그 경우 호출부가
/// reviewNeeded로 표시해야 한다.
class SpaceLoopResult {
  const SpaceLoopResult.closed(this.orderedCornerIds)
      : closed = true,
        failureReason = null;

  const SpaceLoopResult.failed(this.failureReason)
      : closed = false,
        orderedCornerIds = const [];

  final List<String> orderedCornerIds;
  final bool closed;
  final String? failureReason;
}

class GptWallTopologySolver {
  const GptWallTopologySolver();

  SpaceLoopResult deriveSpaceLoop(GptSpace space, List<GptWall> allWalls) {
    final wallsById = {for (final w in allWalls) w.id: w};
    final edges = <(String, String)>[];
    for (final wallId in space.boundaryWallIds) {
      final wall = wallsById[wallId];
      if (wall == null) {
        return SpaceLoopResult.failed('space "${space.id}" references wall "$wallId" not found among provided walls');
      }
      for (var i = 0; i < wall.cornerIds.length - 1; i++) {
        edges.add((wall.cornerIds[i], wall.cornerIds[i + 1]));
      }
    }
    if (edges.isEmpty) {
      return SpaceLoopResult.failed('space "${space.id}" has no wall edges to build a boundary from');
    }

    final adjacency = <String, List<String>>{};
    for (final (a, b) in edges) {
      adjacency.putIfAbsent(a, () => []).add(b);
      adjacency.putIfAbsent(b, () => []).add(a);
    }

    for (final entry in adjacency.entries) {
      if (entry.value.length != 2) {
        return SpaceLoopResult.failed(
          'space "${space.id}" boundary is not a simple closed loop — corner "${entry.key}" '
          'has ${entry.value.length} connection(s), expected exactly 2',
        );
      }
    }

    final start = adjacency.keys.first;
    final loop = <String>[start];
    final visited = <String>{start};
    var prev = start;
    var current = adjacency[start]!.first;

    while (current != start) {
      loop.add(current);
      if (!visited.add(current)) {
        return SpaceLoopResult.failed(
          'space "${space.id}" boundary revisits corner "$current" before closing — not a simple loop',
        );
      }
      final neighbors = adjacency[current]!;
      final next = neighbors[0] == prev ? neighbors[1] : neighbors[0];
      prev = current;
      current = next;
    }

    if (loop.length != adjacency.length) {
      return SpaceLoopResult.failed(
        'space "${space.id}" boundary walk (${loop.length} corners) does not cover all referenced '
        'corners (${adjacency.length}) — possible disconnected wall groups',
      );
    }

    return SpaceLoopResult.closed(loop);
  }
}
