// SPACE SHIFT — WO088-2 SEMANTIC → COORDINATE → REAL SCALE ARCHITECTURE POC.
//
// §10 Image 2 검증 — 실제 이미지 2에 대해 anchor 없이(scale unknown)와
// 임의 anchor 하나를 적용했을 때의 실제 mm 좌표 안정성을 정직하게
// 기록한다. 실제 Image 2 원본 파일은 이 세션이 기록한 대로 PC1/PC2
// 어디에서도 찾지 못했다(반복 검색하지 않는다) — loadRealImage2Bytes()가
// null이면 SKIP으로 정직하게 남긴다(기존 coord_structure_image2_test.dart
// 와 동일한 관례).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/coord_structure_v1/coord_real_scale.dart';
import 'package:ason_space/vision_cad_poc/coord_structure_v1/coord_structure_model.dart';
import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/gpt_semantic_schema.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/virtual_cad_scale.dart';

const _capturePath = 'lib/vision_cad_poc/pixel_wall_v4/captured/semantic_v4.json';

void main() {
  test('실제 이미지 2 — anchor 적용 전/후 좌표 구조가 정직하게 안정적으로 만들어진다', () {
    final bytes = loadRealImage2Bytes();
    if (bytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2를 찾을 수 없음 — WO088-2 REAL SCALE Image 2 검증 보류(BLOCKED, 반복 검색하지 않음)');
      return;
    }

    GptSemanticResponse? semantic;
    if (File(_capturePath).existsSync()) {
      semantic = GptSemanticResponse.fromJson(jsonDecode(File(_capturePath).readAsStringSync()) as Map<String, dynamic>);
    }

    final extraction = extractPixelWalls(bytes);
    final model = buildCoordStructureFromExtraction(extraction, semantic: semantic);

    // Anchor 없이: 모든 mm 목록이 비어 있어야 한다(§3B 임의 mm 금지).
    final unscaled = buildMetricCoordStructure(model, const RealWorldScale.unknown(), sourceWidthPx: extraction.analysisWidthPx, sourceHeightPx: extraction.analysisHeightPx);
    expect(unscaled.walls, isEmpty);
    expect(unscaled.scale.isCalibrated, isFalse);

    // 임의(가상) anchor 하나 적용 — 실제 사용자 anchor를 흉내(가장 긴 벽
    // 하나를 4200mm로 가정, 실제 값이 아니라 산술 안정성만 검증한다).
    if (model.walls.isEmpty) {
      // ignore: avoid_print
      print('SKIP: 이 이미지에서 wall이 하나도 추출되지 않아 anchor 검증 불가');
      return;
    }
    final longest = [...model.walls]..sort((a, b) {
      double len(CoordWallSegment w) {
        final dx = w.end.x - w.start.x;
        final dy = w.end.y - w.start.y;
        return dx * dx + dy * dy;
      }
      return len(b).compareTo(len(a));
    });
    final anchorWall = longest.first;
    final scale = calibrateCoordScaleFromAnchor(
      a: anchorWall.start,
      b: anchorWall.end,
      realWorldMm: 4200,
      sourceWidthPx: extraction.analysisWidthPx,
      sourceHeightPx: extraction.analysisHeightPx,
      anchorDescription: '가장 긴 벽(${anchorWall.id}) = 4200mm(검증용 가정치, 실측 아님)',
    );
    final scaled = buildMetricCoordStructure(model, scale, sourceWidthPx: extraction.analysisWidthPx, sourceHeightPx: extraction.analysisHeightPx);

    // ignore: avoid_print
    print('''
=== 실제 이미지 2 — WO088-2 REAL SCALE(anchor=${anchorWall.id}=4200mm 가정) ===
scale: 1 unit = ${scale.mmPerVirtualUnit?.toStringAsFixed(3)}mm
walls(mm 변환됨): ${scaled.walls.length} / ${model.walls.length}
가장 긴 벽 길이: ${scaled.walls.firstWhere((w) => w.id == anchorWall.id).lengthMm.toStringAsFixed(1)}mm (anchor 그대로 4200mm여야 함)
''');

    expect(scale.isCalibrated, isTrue);
    // anchor로 쓴 벽 자체는 정확히 4200mm로 되돌아와야 한다(자기 자신
    // 검증 — coord_real_scale_test.dart의 합성 테스트가 이미 증명한
    // 산술이 실제 Image 2 evidence에도 그대로 성립하는지 확인).
    expect(scaled.walls.firstWhere((w) => w.id == anchorWall.id).lengthMm, closeTo(4200, 1e-3));
    // 모든 mm 변환 벽의 길이가 유한하고 양수여야 한다 — NaN/Infinity/음수
    // 길이가 조용히 섞여 들어가면 안 된다.
    for (final w in scaled.walls) {
      expect(w.lengthMm.isFinite, isTrue, reason: '${w.id} 길이가 유한해야 한다');
      expect(w.lengthMm, greaterThan(0));
    }
  });
}
