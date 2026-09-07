// SPACE SHIFT — PC1 CONTINUE: DOOR/WINDOW → PARENT WALL + PARAMETRIC OPENING.
//
// 실제 이미지 2("평면도1.PNG", SHA-256 973c16c1...)에 대해 새 Opening
// 계층이 기존 PlanarGraph/FloorDomain/PhysicalRoom 결과를 전혀 건드리지
// 않는(순수 추가) 것을 확인하고, 실제 door/window/unknown/image-break
// 후보 수를 정직하게 기록한다. "모든 문을 다 찾아내야 한다"가 목표가
// 아니다 — 정확히 미상으로 남는 것이 잘못 분류하는 것보다 낫다(§16).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/gpt_semantic_schema.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';

const _capturePath = 'lib/vision_cad_poc/pixel_wall_v4/captured/semantic_v4.json';

void main() {
  test('실제 이미지 2 — Door/Window Opening 계층 추가 후 회귀 없음 + 정직한 opening 리포트', () {
    final bytes = loadRealImage2Bytes();
    if (bytes == null || !File(_capturePath).existsSync()) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 또는 캡처된 semantic_v4.json 없음');
      return;
    }
    final json = jsonDecode(File(_capturePath).readAsStringSync()) as Map<String, dynamic>;
    final semantic = GptSemanticResponse.fromJson(json);

    final result = runPixelWallPipeline(imageBytes: bytes, semantic: semantic);
    final fd = result.floorDomain;

    // ignore: avoid_print
    print('''
=== 실제 이미지 2 — DOOR/WINDOW OPENING ===
Walls(물리, 노이즈 제외): ${result.model.walls.length}
WallEdges(parent, 문/창 gap 포함 연속 구조 벽): ${result.model.wallEdges.length}
Opening candidates(검증 통과): ${result.openingValidation.valid.length}
Opening candidates(거부): ${result.openingValidation.rejected.length}
  Doors accepted: ${result.doorOpeningCount}
  Windows accepted: ${result.windowOpeningCount}
  Unknown openings: ${result.unknownOpeningCount}
  Image-break-only gaps(Opening 아님): ${result.imageBreakOnlyGapCount}
Parent wall match count: ${result.openingValidation.valid.length}
Unmatched openings(rejected): ${result.openingValidation.rejected.length}
Review required: ${result.openingValidation.valid.where((o) => o.reviewNeeded).length}

=== PLANAR GRAPH / FLOOR DOMAIN 회귀 확인 ===
GRAPH vertices=${fd.graphVertexCount} edges=${fd.graphEdgeCount} faces=${fd.graphFaceCount} tJunctions=${fd.tJunctionCount}
FloorDomain: ${fd.isValid ? "VALID" : "INVALID"} sourceEvidenceLimited=${fd.sourceEvidenceLimited}
PhysicalRooms: ${result.physicalRooms.length}
''');

    // §15 PLANAR GRAPH 회귀 — 지난 세션에서 확정된 실측치와 정확히
    // 같아야 한다(96/105/23). Opening 계층은 이 수치에 전혀 관여하지
    // 않는 순수 추가([wallSystems]/[buildWallOpenings]는 FloorDomain
    // 계산과 독립적으로 같은 candidate 목록을 읽기만 한다).
    expect(fd.graphVertexCount, 96);
    expect(fd.graphEdgeCount, 105);
    expect(fd.tJunctionCount, 23);

    // §16 sourceEvidenceLimited 회귀 — 여전히 GRAPH_VALID + 정직한
    // SOURCE_EVIDENCE_LIMITED 상태여야 한다. 이 pass가 그 상태를 억지로
    // "고치지" 않았는지 확인한다(§14 — 가짜로 닫지 않는다).
    expect(fd.isValid, isFalse);
    expect(fd.sourceEvidenceLimited, isTrue);

    // §14 PhysicalRoom 회귀 — 지난 세션에서 확정된 9개 그대로.
    expect(result.physicalRooms.length, 9);

    // Opening cross-reference — 유효한 opening은 전부 실제 wallEdges를
    // 가리켜야 한다(§10, 조용히 깨지지 않았는지).
    final wallEdgeIds = result.model.wallEdges.map((e) => e.id).toSet();
    for (final o in result.openingValidation.valid) {
      expect(wallEdgeIds, contains(o.parentWallId));
    }

    // 거부된 opening이 있어도 조용히 사라지지 않고 warnings에 남아야 한다.
    if (result.openingValidation.rejected.isNotEmpty) {
      expect(result.model.warnings.any((w) => w.contains('Opening 거부')), isTrue);
    }
  });
}
