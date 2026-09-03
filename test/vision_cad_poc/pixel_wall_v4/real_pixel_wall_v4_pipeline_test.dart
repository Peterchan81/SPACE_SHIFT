// SPACE SHIFT — PC1 CONTINUE: FLOOR DOMAIN FIRST + PHYSICAL ROOM / SEMANTIC
// ZONE SPLIT.
// 실제 이미지 2 + 실제로 캡처된 GPT semantic 응답(base call 1회)으로
// 전체 파이프라인(추출 → false-positive cleanup → wall consolidation →
// FloorDomain → PhysicalRoom/SemanticZone 매칭 → TopologyValidator)을
// 있는 그대로 실행해 정직한 수치를 기록한다. "13/13 닫힌 물리 공간"을
// 목표로 하지 않는다 — 열린 구조는 SemanticZone으로 남는 것이 정상이다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/gpt_semantic_schema.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/semantic_zone_mapper.dart';

const _capturePath = 'lib/vision_cad_poc/pixel_wall_v4/captured/semantic_v4.json';

void main() {
  test('실제 이미지 2 + 실제 GPT 의미 지도 — 전체 파이프라인 정직 리포트', () {
    final bytes = loadRealImage2Bytes();
    if (bytes == null || !File(_capturePath).existsSync()) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 또는 캡처된 semantic_v4.json 없음');
      return;
    }
    final json = jsonDecode(File(_capturePath).readAsStringSync()) as Map<String, dynamic>;
    final semantic = GptSemanticResponse.fromJson(json);

    final result = runPixelWallPipeline(imageBytes: bytes, semantic: semantic);

    // ignore: avoid_print
    print('''
=== 실제 이미지 2 — FLOOR DOMAIN FIRST + PHYSICAL ROOM / SEMANTIC ZONE ===
Pixel wall candidates: ${result.extraction.candidates.length} (구조=${result.extraction.structuralCount}, 검토필요=${result.extraction.reviewNeededCount})
  HIGH=${result.extraction.highCount} MEDIUM=${result.extraction.mediumCount} LOW=${result.extraction.lowCount}
  외벽 분류: ${result.extraction.candidates.where((c) => c.isExterior).length}
Noise 분류: text=${result.extraction.candidates.where((c) => c.noiseCategory.name == 'text').length} '
  furniture=${result.extraction.candidates.where((c) => c.noiseCategory.name == 'furniture').length} '
  fixture=${result.extraction.candidates.where((c) => c.noiseCategory.name == 'fixture').length} '
  doorArc=${result.extraction.candidates.where((c) => c.noiseCategory.name == 'doorArc').length} '
  windowDetail=${result.extraction.candidates.where((c) => c.noiseCategory.name == 'windowDetail').length} '
  unknown=${result.extraction.candidates.where((c) => c.noiseCategory.name == 'unknown').length}
최종 CANONICAL 벽 개수(노이즈 제외): ${result.model.walls.length}
PhysicalRoom(flood-fill): ${result.physicalRooms.length}
FloorDomain: ${result.floorDomainClosed ? "VALID" : "INVALID(${result.floorDomainFailureReason})"}
  virtualBoundaries=${result.floorDomain.virtualBoundaries.length} unresolvedGaps=${result.floorDomain.unresolvedGaps.length}
TopologyValidator 경고: ${result.model.warnings.length}
Semantic 13개 매핑: physicalRoom=${result.matchedPhysicalRoomCount}, semanticZone=${result.semanticZoneCount}, 미매칭=${result.unmatchedGptSpaceCount}
UNKNOWN PHYSICAL ROOM(라벨 없는 pixel room): ${result.unmatchedPhysicalRoomCount}
''');
    for (final s in result.spaceSemantics) {
      // ignore: avoid_print
      print('  ${s.id} label=${s.label} kind=${s.kind.name} reviewNeeded=${s.reviewNeeded} physicalRoomId=${s.physicalRoomId}');
    }

    expect(result.extraction.isSuccess, isTrue);
    // "13/13 닫힌 물리 공간"은 더 이상 목표가 아니다 — 13개 GPT 라벨이
    // 전부 physicalRoom 또는 semanticZone 중 하나로 "보존"됐는지만 확인.
    expect(result.spaceSemantics, hasLength(13));
    for (final s in result.spaceSemantics) {
      expect(s.kind == SpaceSemanticKind.physicalRoom || s.kind == SpaceSemanticKind.semanticZone, isTrue);
    }
  });
}
