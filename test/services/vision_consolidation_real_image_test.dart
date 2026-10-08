// GPT CAD 핵심 이식 — 실제 평면도 1장으로 반복 분석 전/후 결과를 비교하고
// DXF 생성/재파싱까지 확인한다. 기존 real_image2_source.dart와 같은 원칙
// (실제 파일이 없으면 조용히 skip, 숫자를 미리 예단하지 않고 있는 그대로
// 출력한다)을 따른다 — 이 파일은 CI에서 항상 통과해야 하는 결정적
// assertion 대신, 실제 GPT 결과를 사람이 확인할 수 있게 출력하는 데
// 집중한다(진짜 assertion은 구조적 유효성 — 벽이 하나 이상 있다, DXF가
// 파싱 가능하다 — 로만 제한한다).
//
// 실행 방법(둘 다 필요):
//   1. 실제 평면도 파일이 C:\Users\user\Desktop\스크린샷\평면도.PNG에 있어야 한다.
//   2. --dart-define=GPT_FLOORPLAN_EDGE_FUNCTION_URL=https://mljvgngjmrvoqjwvvyeg.supabase.co/functions/v1/gpt-floorplan-understand
//      없이 실행하면 실제 네트워크 호출 없이 안전하게 skip한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';
import 'package:ason_space/services/gpt_floorplan_vision_service.dart';
import 'package:ason_space/services/vision_consolidation.dart';
import 'package:ason_space/services/vision_guided_spatial_model_builder.dart';

const String kRealFloorplanPath = r'C:\Users\user\Desktop\스크린샷\평면도.PNG';

void main() {
  test(
    '실제 평면도 1장 — 단일 호출 vs 3회 통합 비교 + DXF 생성/재파싱 검증',
    () async {
      final file = File(kRealFloorplanPath);
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('SKIP: 실제 평면도 파일 없음 ($kRealFloorplanPath)');
        return;
      }
      const url = String.fromEnvironment('GPT_FLOORPLAN_EDGE_FUNCTION_URL');
      if (url.isEmpty) {
        // ignore: avoid_print
        print(
          'SKIP: --dart-define=GPT_FLOORPLAN_EDGE_FUNCTION_URL 없이는 실제 GPT 호출을 시도하지 않는다'
          '(UnavailableVisionInterpretationService로 안전하게 폴백하는 기존 동작과 동일).',
        );
        return;
      }

      final bytes = file.readAsBytesSync();
      final builder = VisionGuidedSpatialModelBuilder(
        visionService: createVisionInterpretationService(),
      );

      final single = await builder.buildCad(bytes);
      // ignore: avoid_print
      print(
        '=== 단일 호출(1회, "전") ===\n'
        'walls=${single.walls.length} openings=${single.openings.length} rooms=${single.rooms.length}\n'
        'wall confidences=${single.walls.map((w) => w.confidence.toStringAsFixed(2)).toList()}',
      );

      final consolidated = await buildConsolidatedVisionCadFloorPlan(
        bytes,
        buildOnce: builder.buildCad,
        samples: 3,
      );
      // ignore: avoid_print
      print(
        '=== 3회 통합("후", WO086 이식) ===\n'
        'walls=${consolidated.walls.length} openings=${consolidated.openings.length} rooms=${consolidated.rooms.length}\n'
        'wall confidences=${consolidated.walls.map((w) => w.confidence.toStringAsFixed(2)).toList()}\n'
        'reviewNeeded walls=${consolidated.walls.where((w) => w.reviewNeeded).length}/${consolidated.walls.length}',
      );

      expect(consolidated.walls, isNotEmpty, reason: '통합 결과에 벽이 하나도 없으면 안 된다');

      final scale = resolveAutoScale(consolidated, null);
      final result = const E2eDxfExporter().export(consolidated, scale: scale);
      expect(result.dxfContent, contains('ENTITIES'));
      expect(result.dxfContent.trim(), endsWith('0\nEOF'));

      final lineCount = 'LINE'.allMatches(result.dxfContent).length;
      final wallIds = consolidated.walls.map((w) => w.id).toSet();
      final openingLineCount = consolidated.openings.where((o) => wallIds.contains(o.wallId)).length;
      final roomLineCount = consolidated.rooms.fold<int>(0, (sum, r) => sum + r.polygon.length);
      expect(lineCount, consolidated.walls.length + openingLineCount + roomLineCount);

      // ignore: avoid_print
      print(
        '=== DXF ===\n'
        'bytes=${result.dxfContent.length} isScaled=${result.isScaled} notice=${result.notice}\n'
        'LINE entities=$lineCount (walls=${consolidated.walls.length} + openings=$openingLineCount + roomEdges=$roomLineCount)',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
