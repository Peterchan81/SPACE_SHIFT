// SPACE SHIFT — WO088-1 IMAGE 2 COORDINATE-BASED 2D STRUCTURE POC.
//
// §14 Image 2 regression test — 실제 이미지 2에서 만들어진 좌표 구조를
// 정직하게 기록한다. §10의 명시적 지시대로, 기존(잘못된 부분이 있다고
// 이미 확인된) pixel_wall_v4/CAD 수치(walls=59, rooms=9 등)를 "정답"으로
// 삼아 비교하지 않는다 — 이 테스트는 그 숫자들과의 일치 여부가 아니라,
// 이 새 경로 자체가 WallSystem/PlanarGraph/FloorDomain 없이도 안정적으로
// 동작하고, source evidence가 있는 그대로(조용히 삭제되지 않고) 보존되는지
// 만 확인한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/coord_structure_v1/coord_structure_model.dart';
import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/gpt_semantic_schema.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_classifier.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

const _capturePath = 'lib/vision_cad_poc/pixel_wall_v4/captured/semantic_v4.json';

void main() {
  test('실제 이미지 2 — 좌표 구조가 FloorDomain 없이도 안정적으로 만들어진다(정직한 기록)', () {
    final bytes = loadRealImage2Bytes();
    if (bytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2를 찾을 수 없음');
      return;
    }

    GptSemanticResponse? semantic;
    if (File(_capturePath).existsSync()) {
      semantic = GptSemanticResponse.fromJson(jsonDecode(File(_capturePath).readAsStringSync()) as Map<String, dynamic>);
    }

    final extraction = extractPixelWalls(bytes);
    final model = buildCoordStructureFromExtraction(extraction, semantic: semantic);

    // ignore: avoid_print
    print('''
=== 실제 이미지 2 — WO088-1 COORDINATE STRUCTURE(FloorDomain 미사용) ===
walls: ${model.walls.length} (exterior=${model.walls.where((w) => w.isExterior).length}, reviewNeeded=${model.walls.where((w) => w.reviewNeeded).length})
corners: ${model.corners.length}
openings: ${model.openings.length} (semanticHint=${model.openings.where((o) => o.source == CoordEvidenceSource.semanticHint).length})
regions: ${model.regions.length}
''');

    // §8 — FloorDomain INVALID여도(이 경로는 FloorDomain을 아예 계산하지
    // 않는다) 구조 자체는 만들어져야 한다.
    expect(model.walls, isNotEmpty);
    expect(model.corners, isNotEmpty);
    expect(model.regions, isNotEmpty);

    // 정규화 좌표는 항상 [0,1] 범위여야 한다(이미지 해상도와 무관).
    for (final w in model.walls) {
      expect(w.start.x, inInclusiveRange(0.0, 1.0));
      expect(w.start.y, inInclusiveRange(0.0, 1.0));
      expect(w.end.x, inInclusiveRange(0.0, 1.0));
      expect(w.end.y, inInclusiveRange(0.0, 1.0));
    }

    // buildCoordStructureFromExtraction이 정확히
    // classifyNoiseCategories+applyTextHeuristic이 확정 비-벽으로 표시한
    // 것만 제외해야 한다 — 근사치가 아니라 같은 공개 함수를 그대로 다시
    // 호출해 정확한 기대값을 계산한다(매직 넘버 금지). semantic==null인
    // 경우도 함께 확인한다 — classifyNoiseCategories는 semantic이 없으면
    // candidates를 그대로 반환하지만, applyTextHeuristic은 순수 두께/
    // 길이 근거만으로도(semantic 없이) text를 걸러낼 수 있다 — "semantic이
    // 없으면 전혀 안 걸러진다"는 잘못된 가정을 하지 않는다.
    int expectedConfirmedNonWallCount(GptSemanticResponse? s) {
      var classified = classifyNoiseCategories(candidates: extraction.candidates, semantic: s);
      classified = applyTextHeuristic(candidates: classified, analysisWidthPx: extraction.analysisWidthPx, analysisHeightPx: extraction.analysisHeightPx);
      return classified
          .where(
            (c) =>
                c.noiseCategory == PixelWallNoiseCategory.text ||
                c.noiseCategory == PixelWallNoiseCategory.furniture ||
                c.noiseCategory == PixelWallNoiseCategory.fixture ||
                c.noiseCategory == PixelWallNoiseCategory.doorArc ||
                c.noiseCategory == PixelWallNoiseCategory.windowDetail,
          )
          .length;
    }

    final noSemanticModel = buildCoordStructureFromExtraction(extraction);
    expect(noSemanticModel.walls.length, extraction.candidates.length - expectedConfirmedNonWallCount(null));
    expect(model.walls.length, extraction.candidates.length - expectedConfirmedNonWallCount(semantic));
  });
}
