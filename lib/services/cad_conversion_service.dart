/// SS010 — CAD 자동 변환 엔진. 기존 [TopologyValidator](Geometry Validation)·
/// [buildCadFloorPlanFromSpatialModel]·[resolveAutoScale]·[E2eDxfExporter](CAD/DXF 생성)를 그대로
/// 재사용하고, 이 클래스는 "전처리 → 공간 구조 분석 → 벽/문/창 기하학 처리 → Geometry Validation →
/// 치수/Scale → CAD/DXF 생성" 순서로 단계를 알리는 오케스트레이션만 더한다 — 어느 엔진도 새로
/// 다시 구현하지 않는다(§구현 원칙).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../core/ss_cad_conversion_step.dart';
import '../models/cad_conversion_result.dart';
import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/ss_spatial_model.dart';
import 'e2e_dxf_exporter.dart';
import 'topology_validator.dart';

class CadConversionService {
  const CadConversionService({this.stepDelay = const Duration(milliseconds: 250), this.validator = const TopologyValidator()});

  /// 각 단계 사이 지연(사용자가 진행을 체감할 수 있게 — SsPhotoRenderService와 같은 패턴). 테스트에서는
  /// Duration.zero로 줄인다.
  final Duration stepDelay;

  /// Geometry Validation — 기존 [TopologyValidator]를 그대로 재사용한다(새로 만들지 않는다).
  final TopologyValidator validator;

  /// [onStep]은 각 단계가 시작될 때 한 번씩, 순서대로 불린다. [knownScale]이 있으면(직접 그리기처럼
  /// 실제 mm 단위가 이미 확정된 경우) 그 축척을 그대로 쓰고, 없으면(평면도 업로드/AI 인식 경로)
  /// [resolveAutoScale]로 추정한다.
  Future<CadConversionResult> convert(
    SSSpatialModel model, {
    FloorPlanScale? knownScale,
    void Function(SsCadConversionStep step)? onStep,
  }) async {
    try {
      Future<void> tick(SsCadConversionStep step) async {
        onStep?.call(step);
        if (stepDelay > Duration.zero) await Future<void>.delayed(stepDelay);
      }

      await tick(SsCadConversionStep.preprocessing);
      await tick(SsCadConversionStep.spatialAnalysis);
      await tick(SsCadConversionStep.wallOpeningGeometry);

      // Geometry Validation(기존 TopologyValidator 재사용) — 벽/문/창 처리 직후, 치수 계산 전
      // (§ 처리 단계: ... 벽/문/창 기하학 처리 → Geometry Validation → 치수/Scale ...).
      final validated = validator.validate(model);
      if (validated.walls.isEmpty && validated.spaces.isEmpty) {
        throw const CadConversionInputError(
          '변환할 벽이나 공간을 찾지 못했습니다. 이전 단계로 돌아가 평면도를 다시 확인해 주세요.',
        );
      }

      await tick(SsCadConversionStep.dimensionScale);
      final plan = buildCadFloorPlanFromSpatialModel(validated);
      final scale = knownScale ?? resolveAutoScale(plan, null);

      await tick(SsCadConversionStep.cadGeneration);
      final dxf = const E2eDxfExporter().export(plan, scale: scale);

      return CadConversionResult(plan: plan, scale: scale, dxfContent: dxf.dxfContent, isScaled: dxf.isScaled, validatedModel: validated);
    } catch (e, st) {
      // 실패 원인을 다른 것(예: 네트워크 오류 — 이 서비스는 네트워크를 전혀 쓰지 않는다)으로 둔갑시키지
      // 않는다 — 실제 타입/메시지는 로그로 남기고, 원래 타입 그대로 다시 던져 호출한 쪽([SsAiTask] 또는
      // [CadConversionInputError] 전용 처리)이 올바르게 구분해서 보여주게 한다.
      debugPrint('CadConversionService.convert 실패 (${e.runtimeType}): $e\n$st');
      rethrow;
    }
  }
}
