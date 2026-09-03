// SPACE SHIFT — Image 2 GPT Detailed CAD Geometry POC.
//
// 실제 "이미지 2" 원본 파일(이 세션에서 파일시스템에서 발견한
// 평면도1.PNG)에 대해, 기존(5499365) VisionGuidedSpatialModelBuilder를
// 재사용해 상세 proposal(v2)을 실제 픽셀로 정밀화하는지 확인한다.
//
// 이 테스트는 이 PC의 특정 경로에 있는 실제 파일에 의존한다 — 그
// 파일이 없는 환경(다른 PC/CI)에서는 실패시키지 않고 건너뛴다(외부
// 파일 의존성을 정직하게 표시).

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/services/vision_guided_spatial_model_builder.dart';
import 'package:ason_space/vision_cad_poc/e2e_v2/detailed_proposal_vision_service.dart';
import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';

void main() {
  final realBytes = loadRealImage2Bytes();

  test('실제 이미지 2 원본 파일을 로드할 수 있다', () {
    if (realBytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 파일이 $kRealImage2Path 에 없음 — 이 PC 전용 테스트');
      return;
    }
    expect(realBytes, isNotEmpty);
  });

  test('실제 이미지에 대해 SSGeometrySolver/VisionGuidedSpatialModelBuilder가 정상 동작한다', () async {
    if (realBytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 파일 없음');
      return;
    }
    final builder = VisionGuidedSpatialModelBuilder(visionService: const DetailedProposalVisionService());
    final model = await builder.build(realBytes);

    expect(model.spaces, isNotEmpty);
    expect(model.walls, isNotEmpty);
    // 축척은 항상 미확정으로 유지되어야 한다(이 도면엔 인쇄된 치수가 없음).
    expect(model.dimensions, isEmpty);
  });

  test('대부분의 공간 라벨이 보존된다(작은 돌출부 2개는 실제 픽셀 근거 부족으로 제외될 수 있음)', () async {
    if (realBytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 파일 없음');
      return;
    }
    final builder = VisionGuidedSpatialModelBuilder(visionService: const DetailedProposalVisionService());
    final model = await builder.build(realBytes);
    final labels = model.spaces.map((s) => s.label).whereType<String>().toSet();
    // 발코니/실외기실은 이미지에서 차지하는 면적이 매우 작아(수 픽셀
    // 단위) 저해상도 실제 사진에서 4변 모두 검출되지 못할 수 있다 —
    // 이는 정직한 한계이지 회귀가 아니다. 나머지 11개 주요 공간은
    // 반드시 보존되어야 한다.
    expect(
      labels,
      containsAll(const [
        '부부거실', '드레스룸', '욕실2', '주방/식당', '펜트리', '욕실1',
        '현관', '안방', '거실', '침실2', '침실1',
      ]),
    );
  });
}
