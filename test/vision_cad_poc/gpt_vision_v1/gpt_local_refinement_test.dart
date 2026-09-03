// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
//
// GptLocalRefinement이 실제 이미지 2 원본에 대해 동작하는지 확인한다.
// 이 PC의 특정 파일에 의존하므로 파일이 없으면 스킵한다. 좌표는
// e2e_v3(6cbd67c)에서 이미 검증된 GPT 축 값(안방|거실 벽 등)을
// 그대로 재사용한다 — 새로 지어낸 값이 아니다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v1/gpt_cad_schema.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v1/gpt_local_refinement.dart';

void main() {
  final realBytes = loadRealImage2Bytes();

  test('실제 이미지 2에서 안방|거실 벽을 몇 px 이내로 정밀화한다', () {
    if (realBytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 파일 없음');
      return;
    }
    const w = 443.0, h = 301.0;
    final proposal = GptCadProposal(
      schemaVersion: 'ss-cad-vision-v1',
      image: const GptImageInfo(widthPx: 443, heightPx: 301, coordinateSystem: 'top-left-pixel', scaleStatus: 'unknown'),
      floorDomain: const GptFloorDomain(orderedCornerIds: ['C1', 'C2'], confidence: 0.9),
      corners: [
        GptCorner(id: 'C1', x: 0.358 * w, y: 0.573 * h, kind: GptCornerKind.interiorJunction, confidence: 0.85),
        GptCorner(id: 'C2', x: 0.358 * w, y: 0.930 * h, kind: GptCornerKind.interiorJunction, confidence: 0.85),
      ],
      walls: [
        GptWall(id: 'W_MASTER_LIVING', type: GptWallType.interior, cornerIds: const ['C1', 'C2'], confidence: 0.85),
      ],
      spaces: const [],
      doors: const [],
      windows: const [],
      openings: const [],
      objects: const [],
      relationships: const [],
      dimensionHints: const [],
      reviewReasons: const [],
    );

    final result = const GptLocalRefinement().refine(proposal, realBytes);
    expect(result.segments, hasLength(1));
    final seg = result.segments.first;
    expect(seg.found, isTrue);
    // e2e_v3에서 midpoint 기준 delta≈2.8px로 확인된 벽. 여기서는 시작
    // corner 기준(T-junction 지점이라 약간 더 클 수 있음)이라 넉넉히 확인.
    expect(seg.deltaPx, lessThan(20));
  });
}
