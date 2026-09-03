// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
// 합성 도면 + 가짜(합성) GPT 의미 지도로 파이프라인 전체(추출 → 라벨
// 매칭 → FloorDomain 체인 → TopologyValidator)가 크래시 없이 정상
// 동작하는지 검증한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/pixel_wall_v4/gpt_semantic_schema.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';

Uint8List _twoRoomFloorPlan() {
  // 300x200, 가운데(x=150)에서 좌우 두 방으로 나뉘는 합성 도면.
  final image = img.Image(width: 300, height: 200);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  void thickLine(int x1, int y1, int x2, int y2) {
    for (var t = -3; t <= 3; t++) {
      if (y1 == y2) {
        img.drawLine(image, x1: x1, y1: y1 + t, x2: x2, y2: y2 + t, color: img.ColorRgb8(0, 0, 0));
      } else {
        img.drawLine(image, x1: x1 + t, y1: y1, x2: x2 + t, y2: y2, color: img.ColorRgb8(0, 0, 0));
      }
    }
  }

  thickLine(30, 30, 270, 30);
  thickLine(30, 170, 270, 170);
  thickLine(30, 30, 30, 170);
  thickLine(270, 30, 270, 170);
  thickLine(150, 30, 150, 170);

  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('두 방 + GPT 의미 지도(가짜) — 매칭/FloorDomain/TopologyValidator까지 안전하게 통과', () {
    final bytes = _twoRoomFloorPlan();
    final semantic = GptSemanticResponse(
      spaces: [
        const GptSemanticSpace(
          id: 's1',
          label: '방1',
          semanticType: 'bedroom',
          approxRegion: GptApproxRegion(x0: 0.09, y0: 0.14, x1: 0.49, y1: 0.87),
          neighborSpaceIds: ['s2'],
          exteriorSides: ['top', 'left', 'bottom'],
        ),
        const GptSemanticSpace(
          id: 's2',
          label: '방2',
          semanticType: 'livingRoom',
          approxRegion: GptApproxRegion(x0: 0.51, y0: 0.14, x1: 0.91, y1: 0.87),
          neighborSpaceIds: ['s1'],
          exteriorSides: ['top', 'right', 'bottom'],
        ),
      ],
    );

    final result = runPixelWallPipeline(imageBytes: bytes, semantic: semantic);

    expect(result.extraction.isSuccess, isTrue);
    expect(result.model.spaces, hasLength(2));
    expect(result.matchedSpaceCount, 2);
    expect(result.unmatchedGptSpaceCount, 0);
    for (final space in result.model.spaces) {
      expect(space.polygon, isNotEmpty, reason: '${space.id}는 실제 pixel 방과 매칭돼야 한다');
      expect(space.label, isNotNull);
    }
    // FloorDomain은 pixel 외벽 체인에서만 나온다 — GPT가 좌표를 준 적이
    // 없으므로 이게 닫혔다면 순수 pixel 근거로 닫힌 것이다.
    expect(result.floorDomainClosed, isTrue, reason: result.floorDomainFailureReason ?? '');
    expect(() => result.model, returnsNormally);
  });

  test('GPT 응답이 없으면(semantic=null) 크래시 없이 라벨 없는 geometry-only 결과를 만든다', () {
    final bytes = _twoRoomFloorPlan();
    final result = runPixelWallPipeline(imageBytes: bytes, semantic: null);
    expect(result.extraction.isSuccess, isTrue);
    expect(result.model.spaces, isNotEmpty);
    for (final space in result.model.spaces) {
      expect(space.label, isNull);
      expect(space.reviewNeeded, isTrue); // UNKNOWN REGION 취급.
    }
  });
}
