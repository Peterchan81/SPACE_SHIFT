// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
// 실제 이미지 2 + 실제로 캡처된 GPT semantic 응답(1회 호출, base call)으로
// 전체 파이프라인(추출 → 라벨 매칭 → FloorDomain → TopologyValidator)을
// 있는 그대로 실행해 정직한 수치를 기록한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/gpt_semantic_schema.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';

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

    final reviewSpaces = result.model.spaces.where((s) => s.reviewNeeded).toList();
    final reviewWalls = result.model.walls.where((w) => w.reviewNeeded).toList();

    // ignore: avoid_print
    print('''
=== 실제 이미지 2 — PIXEL WALL PIPELINE (semantic 1회 호출 반영) ===
Pixel wall candidates: ${result.extraction.candidates.length} (구조=${result.extraction.structuralCount}, 검토필요=${result.extraction.reviewNeededCount})
  HIGH=${result.extraction.highCount} MEDIUM=${result.extraction.mediumCount} LOW=${result.extraction.lowCount}
RoomCandidate(flood-fill): ${result.extraction.rooms.length}
Spaces: ${result.model.spaces.length}/13, matched=${result.matchedSpaceCount}, GPT공간 미매칭=${result.unmatchedGptSpaceCount}, UNKNOWN REGION=${result.unmatchedRoomCount}
FloorDomain: ${result.floorDomainClosed ? "VALID" : "INVALID(${result.floorDomainFailureReason})"}
TopologyValidator 경고: ${result.model.warnings.length}
Review needed spaces: ${reviewSpaces.map((s) => '${s.id}(${s.label})').join(', ')}
Review needed walls: ${reviewWalls.length}
''');
    for (final s in result.model.spaces) {
      // ignore: avoid_print
      print('  ${s.id} label=${s.label} closed=${s.closed} area=${s.areaNormalized.toStringAsFixed(3)} reviewNeeded=${s.reviewNeeded}');
    }

    expect(result.extraction.isSuccess, isTrue);
    // GPT가 준 13개 라벨 공간 + pixel만으로 검출됐지만 라벨과 매칭되지
    // 않은 UNKNOWN REGION까지 합친 개수라 13보다 클 수 있다 — 여기서는
    // "적어도 13개 라벨 공간은 전부 보존됐는가"만 안전성 차원에서 확인한다.
    final labeledSpaces = result.model.spaces.where((s) => s.label != null).toList();
    expect(labeledSpaces, hasLength(13));
  });
}
