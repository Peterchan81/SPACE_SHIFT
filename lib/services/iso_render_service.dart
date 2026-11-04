/// SS015 — 3D ISO 최종 렌더링 엔진. 기존 [buildIsoEditorScene](SS013 — CAD 구조+SS013/14 재질/가구/
/// 조명/설비를 전부 반영해 완성된 ISO 모델을 만드는 순수 함수, 기존 [buildSpaceSceneV2]를 그대로
/// 감싼다)를 그대로 재사용하고, 이 클래스는 "이미지 품질 처리 → 재질/조명 적용 → 공간 분위기 렌더링
/// → 최종 이미지 생성 → 3D 아이소 모델 반영" 순서로 단계를 알리는 오케스트레이션과 ISO Orbit 카메라
/// 보존만 더한다 — 3D geometry/재질 엔진을 새로 만들지 않는다(§구현 원칙, [IsoConversionService]와
/// 같은 패턴).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../core/ss_iso_render_step.dart';
import '../models/iso_render_result.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_iso_camera_state.dart';
import '../models/ss_iso_design_extras.dart';
import 'iso_conversion_service.dart' show kIsoDefaultCeilingHeightMm;
import 'ss_iso_editor_scene_builder.dart' show buildIsoEditorScene;

class IsoRenderService {
  const IsoRenderService({this.stepDelay = const Duration(milliseconds: 250)});

  /// 각 단계 사이 지연(사용자가 진행을 체감할 수 있게 — [IsoConversionService]와 같은 패턴). 테스트
  /// 에서는 Duration.zero로 줄인다. [SsIsoRenderQuality.preview] 요청은 사용자가 즉시 확인하려는
  /// 의도이므로 이 지연을 쓰지 않는다(§구현 범위 "미리보기 렌더링과 최종 렌더링을 구분할 수 있는 구조").
  final Duration stepDelay;

  /// [onStep]은 각 단계가 시작될 때 한 번씩, 순서대로 불린다. [previousCamera]가 있으면(재생성 — 3D
  /// 디자인이 바뀌어 다시 렌더링하는 경우) 사용자가 이미 돌려본 Orbit 시점을 그대로 보존한다(§완료조건
  /// "사용자 디자인 데이터를 소실하지 않는다") — 없으면(처음 렌더링) scene 기준 기본값을 새로 계산한다.
  Future<IsoRenderResult> render(
    SsCadScene cad, {
    SsIsoDesignExtras extras = SsIsoDesignExtras.empty,
    SsIsoCameraState? previousCamera,
    SsIsoRenderQuality quality = SsIsoRenderQuality.full,
    void Function(SsIsoRenderStep step)? onStep,
  }) async {
    try {
      final effectiveDelay = quality == SsIsoRenderQuality.preview ? Duration.zero : stepDelay;
      Future<void> tick(SsIsoRenderStep step) async {
        onStep?.call(step);
        if (effectiveDelay > Duration.zero) await Future<void>.delayed(effectiveDelay);
      }

      await tick(SsIsoRenderStep.imageQualityProcessing);

      final plan = cad.plan;
      if (plan.walls.isEmpty && plan.rooms.isEmpty) {
        throw const IsoRenderInputError('렌더링할 3D ISO 디자인이 없습니다. 먼저 3D 디자인을 완료해 주세요.');
      }

      await tick(SsIsoRenderStep.materialLighting);
      final scene = buildIsoEditorScene(cad: cad, extras: extras, ceilingHeightMm: kIsoDefaultCeilingHeightMm);
      if (scene.isEmpty) {
        throw const IsoRenderInputError('3D 구조를 렌더링하지 못했습니다. 3D 디자인 화면에서 벽이나 공간을 확인해 주세요.');
      }

      await tick(SsIsoRenderStep.atmosphereRendering);

      await tick(SsIsoRenderStep.finalImageGeneration);
      final camera = previousCamera ?? SsIsoCameraState.defaultForScene(scene);

      await tick(SsIsoRenderStep.applyToIsoModel);

      return IsoRenderResult(scene: scene, camera: camera, quality: quality, warnings: scene.warnings);
    } catch (e, st) {
      // 실패 원인을 다른 것(예: 네트워크 오류 — 이 서비스는 네트워크를 전혀 쓰지 않는다)으로 둔갑시키지
      // 않는다 — 실제 타입/메시지는 로그로 남기고, 원래 타입 그대로 다시 던져 호출한 쪽([SsAiTask] 또는
      // [IsoRenderInputError] 전용 처리)이 올바르게 구분해서 보여주게 한다.
      debugPrint('IsoRenderService.render 실패 (${e.runtimeType}): $e\n$st');
      rethrow;
    }
  }
}
