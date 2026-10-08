// SS CAD TEST — Windows 개발/검증 전용 "OpenAI 직접 호출" 경로(GPT_FLOORPLAN_
// PROVIDER=direct)를 실제 평면도 1장 + 실제 OpenAI API key로 검증한다.
// vision_consolidation_real_image_test.dart(기존 supabase 경로)와 정확히
// 같은 형태 — 단일 호출/3회 통합/DXF 생성까지 실제로 확인하되, 이번에는
// Supabase Edge Function을 전혀 거치지 않는다.
//
// 실행 방법(둘 다 필요):
//   1. 실제 평면도 파일이 C:\Users\user\Desktop\스크린샷\평면도.PNG에 있어야 한다.
//   2. --dart-define=OPENAI_API_KEY=... 없이 실행하면 실제 네트워크 호출
//      없이 안전하게 skip한다. API key는 이 파일에도, 어떤 커밋에도
//      들어가지 않는다.

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
    'direct provider — 실제 평면도 1장을 OpenAI에 직접 호출해 CadFloorPlan/DXF까지 생성한다',
    () async {
      final file = File(kRealFloorplanPath);
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('SKIP: 실제 평면도 파일 없음 ($kRealFloorplanPath)');
        return;
      }
      const apiKey = String.fromEnvironment('OPENAI_API_KEY');
      if (apiKey.isEmpty) {
        // ignore: avoid_print
        print(
          'SKIP: --dart-define=OPENAI_API_KEY 없이는 실제 OpenAI 직접 호출을 시도하지 않는다'
          '(UnavailableVisionInterpretationService로 안전하게 폴백하는 기존 동작과 동일).',
        );
        return;
      }

      final bytes = file.readAsBytesSync();
      final builder = VisionGuidedSpatialModelBuilder(
        visionService: createVisionInterpretationService(
          providerOverride: 'direct',
          apiKeyOverride: apiKey,
        ),
      );

      final single = await builder.buildCad(bytes);
      // ignore: avoid_print
      print(
        '=== [direct] 단일 호출(1회, "전") ===\n'
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
        '=== [direct] 3회 통합("후") ===\n'
        'walls=${consolidated.walls.length} openings=${consolidated.openings.length} rooms=${consolidated.rooms.length}\n'
        'reviewNeeded walls=${consolidated.walls.where((w) => w.reviewNeeded).length}/${consolidated.walls.length}',
      );

      expect(consolidated.walls, isNotEmpty, reason: 'direct 경로로 통합한 결과에 벽이 하나도 없으면 안 된다');

      final scale = resolveAutoScale(consolidated, null);
      final result = const E2eDxfExporter().export(consolidated, scale: scale);
      expect(result.dxfContent, contains('ENTITIES'));
      expect(result.dxfContent.trim(), endsWith('0\nEOF'));

      // ignore: avoid_print
      print('=== [direct] DXF ===\nbytes=${result.dxfContent.length} isScaled=${result.isScaled}');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
