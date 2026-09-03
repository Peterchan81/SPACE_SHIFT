// SPACE SHIFT — Image 2 GPT Direct CAD Geometry Proposal Benchmark.
//
// v3(GPT가 준 실제 픽셀 축 기반) proposal을 실제 이미지 2 원본에 대해
// 검증한다. 이 PC의 특정 파일에 의존하므로, 파일이 없는 환경에서는
// 스킵한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/services/vision_guided_spatial_model_builder.dart';
import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/e2e_v3/detailed_proposal_vision_service_v3.dart';
import 'package:ason_space/vision_cad_poc/e2e_v3/image2_quality_metrics.dart';
import 'package:ason_space/vision_cad_poc/e2e_v3/vision_cad_proposal_v3.dart';

void main() {
  final realBytes = loadRealImage2Bytes();

  test('v3: 대부분의 공간 라벨이 보존된다', () async {
    if (realBytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 파일 없음');
      return;
    }
    final builder = VisionGuidedSpatialModelBuilder(visionService: const DetailedProposalVisionServiceV3());
    final model = await builder.build(realBytes);
    final labels = model.spaces.map((s) => s.label).whereType<String>().toSet();
    // ignore: avoid_print
    print('v3 spaces preserved: $labels (${labels.length}/13)');
    expect(labels.length, greaterThanOrEqualTo(9));
  });

  test('v3: 품질 지표를 계산할 수 있다', () async {
    if (realBytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 파일 없음');
      return;
    }
    final proposal = buildImage2VisionProposalV3();
    final metrics = const Image2QualityMetricsComputer().compute(proposal, realBytes);
    // ignore: avoid_print
    print('mean delta: ${metrics.meanDeltaPx.toStringAsFixed(1)}px, max delta: ${metrics.maxDeltaPx.toStringAsFixed(1)}px');
    // ignore: avoid_print
    print('HIGH=${metrics.highCount} MEDIUM=${metrics.mediumCount} LOW=${metrics.lowCount} unmatched=${metrics.unmatchedCount}');
    for (final m in metrics.wallMetrics) {
      // ignore: avoid_print
      print('  ${m.boundaryId}: found=${m.found} delta=${m.deltaPx?.toStringAsFixed(1)} conf=${m.geometryConfidence}');
    }
    expect(metrics.wallMetrics, isNotEmpty);
  });
}
