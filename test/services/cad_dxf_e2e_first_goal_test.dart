// SS CAD TEST WorkOrder(1차 CAD/DXF E2E) §11 — "최소 실제 평면도 샘플
// 1개는: 이미지 → AI → CAD → 사용자 치수 입력 → DXF → DXF Import까지
// 하나의 E2E로 검증한다."
//
// 실제 OpenAI 계정이 이 시점(§3 재검증에서 확인)에 429(rate/quota)로
// 막혀 있어, 이 테스트는 실제 사진의 자리에 이 저장소가 이미 실측
// 검증에 써 온 합성 평면도(image2 fixture, vision_guided_spatial_model_
// builder_test.dart/production_cad_adapter_image2_test.dart와 동일한
// 이미지)를 쓰고, GPT 응답 자리에는 그 이미지에 맞게 이미 검증된
// MockVisionInterpretationService를 쓴다 — pixel_wall_v4/LiveSemanticProvider
// /CadFloorPlan/E2eDxfExporter/DxfImportService는 전부 실제 production
// 코드 그대로다. OpenAI 계정이 복구되면 MockVisionInterpretationService
// 자리만 실제 서비스로 바뀌고 나머지 파이프라인은 이미 이 테스트로
// 검증된 그대로 동작한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/services/cad_editing_ops.dart';
import 'package:ason_space/services/dxf_import_service.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';
import 'package:ason_space/services/mock_vision_interpretation_service.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/live_semantic_provider.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/semantic_provider.dart';
import 'package:ason_space/vision_cad_poc/sample_image2_fixture.dart';

void main() {
  test(
    '1차 목표 E2E: 이미지 -> AI 구조 이해(semantic) + SS geometry -> CadFloorPlan '
    '-> 사용자 치수 입력(scale 확정 + 벽 길이 수정) -> DXF export -> DXF re-import',
    () async {
      final imageBytes = buildImage2Png();

      // 1) 이미지 -> AI 구조 이해 + SS geometry 검증/보정.
      final pipelineResult = await runPixelWallPipelineWithSemanticProvider(
        imageBytes: imageBytes,
        provider: const LiveSemanticProvider(MockVisionInterpretationService()),
      );
      expect(
        pipelineResult.semanticStatus,
        SemanticProviderStatus.success,
        reason: 'AI 의미 판별이 실제로 pixel_wall_v4에 연결되어야 한다(geometry-only 폴백이 아니라)',
      );

      // 2) SSSpatialModel -> CadFloorPlan(화면/DXF가 공유하는 단일 데이터).
      final cadFromAi = buildCadFloorPlanFromSpatialModel(pipelineResult.model);
      expect(cadFromAi.walls, isNotEmpty, reason: '실제 구조화 CAD 결과에 벽이 있어야 한다');
      // ignore: avoid_print
      print(
        '1) AI+SS 결과: walls=${cadFromAi.walls.length} openings=${cadFromAi.openings.length} '
        'rooms=${cadFromAi.rooms.length} reviewNeeded walls='
        '${cadFromAi.walls.where((w) => w.reviewNeeded).length}',
      );

      // 3) 사용자 확인/치수 수정 — 실측 스케일 확정(치수 보정) + 개별 벽
      //    길이 직접 수정. 두 개념을 섞지 않는다(§8).
      final referenceWall = cadFromAi.walls.first;
      final pxLen = cadFromAi.pixelDistance(referenceWall.start, referenceWall.end);
      expect(pxLen, greaterThan(0));
      // 3a) 전체 scale 확정 — "이 벽이 실제로는 3000mm다".
      final userScale = FloorPlanScale(
        mmPerPixel: 3000 / pxLen,
        referenceStart: referenceWall.start,
        referenceEnd: referenceWall.end,
        referenceLengthMm: 3000,
        source: ScaleSource.measured,
      );
      // 3b) 개별 벽 길이 수정 — 다른 벽 하나를 사용자가 4200mm로 정정.
      final wallToEdit = cadFromAi.walls.length > 1 ? cadFromAi.walls[1] : cadFromAi.walls.first;
      final editedWall = wallWithLengthMm(cadFromAi, wallToEdit, 4200, userScale);
      expect(editedWall.source, CadElementSource.userEdited);
      final userConfirmedPlan = cadFromAi.copyWithWalls([
        for (final w in cadFromAi.walls) if (w.id == wallToEdit.id) editedWall else w,
      ]);
      final confirmedLengthMm =
          userConfirmedPlan.pixelDistance(editedWall.start, editedWall.end) * userScale.mmPerPixel;
      expect(confirmedLengthMm, closeTo(4200.0, 1e-6));

      // 4) DXF export — 화면과 같은 CadFloorPlan, 같은 scale.
      final exported = const E2eDxfExporter().export(userConfirmedPlan, scale: userScale);
      expect(exported.isScaled, isTrue, reason: '사용자가 실측값을 입력했으므로 DXF는 실제 mm여야 한다');
      // ignore: avoid_print
      print('4) DXF export: bytes=${exported.dxfContent.length} notice=${exported.notice}');

      // 5) DXF 재-import 검증 — 벽 개수/길이/문창/scale이 보존되는지.
      final reimported = importDxf(exported.dxfContent);
      expect(reimported.success, isTrue, reason: reimported.failureMessage);
      expect(reimported.unsupportedEntityCount, 0);
      expect(reimported.unsupportedLayerCount, 0);
      expect(reimported.plan!.walls.length, userConfirmedPlan.walls.length);
      expect(reimported.plan!.openings.length, userConfirmedPlan.openings.length);
      expect(reimported.scale, isNotNull);
      // 재-import된 scale은 "직접 측정"이 아니라 "도면에 이미 찍힌 실제
      // mm 좌표를 읽음"이므로 ScaleSource.drawingDimension이 된다 —
      // measured와 마찬가지로 신뢰 가능한 실측 축척이라는 점만 확인한다.
      expect(reimported.scale!.source.isReliable, isTrue);

      // 사용자가 4200mm로 확정한 벽이 재-import 후에도 4200mm로 남아야
      // 한다 — id는 새로 부여되므로 길이로 역추적한다(round-trip 관례).
      final reimportedLengthsMm = reimported.plan!.walls
          .map((w) => reimported.plan!.pixelDistance(w.start, w.end) * reimported.scale!.mmPerPixel)
          .toList();
      expect(
        reimportedLengthsMm.any((mm) => (mm - 4200.0).abs() < 1.0),
        isTrue,
        reason: '사용자가 확정한 4200mm 벽이 DXF 재-import 후에도 그대로 남아야 한다',
      );
      // ignore: avoid_print
      print(
        '5) DXF re-import: walls=${reimported.plan!.walls.length} '
        'openings=${reimported.plan!.openings.length} scale=${reimported.scale!.mmPerPixel}mm/px',
      );
    },
  );
}
