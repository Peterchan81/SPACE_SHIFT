// SPACE SHIFT — WO084/085 PRODUCTION WIRING REGRESSION.
//
// [FloorPlanWorkspaceScreen._startAnalysis]가 실제로 호출하는 것과 정확히
// 같은 두 함수 조합([runPixelWallPipeline] → [buildCadFloorPlanFromSpatialModel])
// 을 실제 이미지 2("평면도1.PNG")로 검증한다 — pixel_wall_v4 자체의 회귀는
// wall_opening_image2_e2e_test.dart가 이미 담당하므로, 이 테스트는 그
// 검증된 결과가 production이 쓰는 [CadFloorPlan]으로 넘어갈 때 reviewNeeded/
// source/개수가 조용히 사라지거나 거짓으로 확정되지 않는지만 확인한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';

void main() {
  test(
    '실제 이미지 2 — production 경로(pixel_wall_v4 → CadFloorPlan)가 review-needed를 정직하게 보존한다',
    () {
      final bytes = loadRealImage2Bytes();
      if (bytes == null) {
        // ignore: avoid_print
        print('SKIP: 실제 이미지 2를 찾을 수 없음 — 다른 평면도로 대체하지 않는다.');
        return;
      }

      // production 화면은 GPT 의미 지도 없이 이미지 바이트만으로 이
      // 경로를 호출한다(WO084 — 임의의 사용자 사진에 GPT 캡처 fixture가
      // 있을 수 없으므로).
      final pipelineResult = runPixelWallPipeline(imageBytes: bytes);
      final cad = buildCadFloorPlanFromSpatialModel(pipelineResult.model);

      // §1 WO083 baseline — 물리 벽 59개는 이 어댑터를 거쳐도 그대로다.
      expect(cad.walls.length, 59);

      // §7/§14 PhysicalRoom 9개 — GPT 의미 지도가 없으므로 전부
      // "unknown physical room"(reviewNeeded)으로 정직하게 남아야 한다.
      // 가짜로 "거실"/"침실1" 같은 이름을 지어내지 않는다.
      expect(cad.rooms.length, 9);
      expect(cad.rooms.every((r) => r.reviewNeeded), isTrue);
      expect(cad.rooms.every((r) => r.name == null), isTrue);

      // §14 opening 17개 — GPT 의미 근거가 0건이므로(inferredTopology만
      // 존재) 전부 review 필요 상태를 유지해야 한다. 자동으로 문/창을
      // 확정하지 않는다(WO084 §C 절대 원칙).
      expect(cad.openings.length, 17);
      expect(cad.openings.every((o) => o.reviewNeeded), isTrue);

      // §9 SOURCE_EVIDENCE_LIMITED UI — "일부 영역 확인 필요" 요약이
      // 기존 warnings 표시 UI(floor_plan_preview.dart)에 그대로 얹힌다.
      expect(
        cad.warnings.any((w) => w.contains('일부 영역은 확인이 필요합니다')),
        isTrue,
      );
    },
  );
}
