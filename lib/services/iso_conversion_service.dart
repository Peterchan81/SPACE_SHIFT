/// SS012 — 3D ISO 변환 엔진. 기존 [buildSpaceSceneV2](CAD→3D geometry — 벽/문/창/바닥/천장을
/// CadWall/CadRoom에서 직접 만들고, 재질/색상도 CadWall.materialOverride/CadRoom.materialOverride를
/// 그대로 반영)를 그대로 재사용하고, 이 클래스는 "전처리 → 공간 구조 분석 → 건축 요소 3D 모델링 →
/// 재질/색상 적용 → ISO 모델 생성" 순서로 단계를 알리는 오케스트레이션과 ISO Orbit 카메라 기본값/
/// 보존만 더한다 — 3D geometry 엔진을 새로 만들지 않는다(§구현 원칙, [CadConversionService]와 같은
/// 패턴).
///
/// 변경 요소 기반 부분 갱신(§작업지시 "가능하면 변경 요소 기반 부분 갱신을 고려하되 안정성을
/// 우선")은 이번 범위에서 채택하지 않는다 — [buildSpaceSceneV2]는 CAD 전체로부터 항상 결정적으로
/// 같은 결과를 만드는 순수 함수라 매번 전체를 다시 만들어도 안전하고 빠르다(이미 다른 화면
/// [FloorPlanWorkspaceScreen]도 매번 다시 호출하는 방식을 쓴다) — CAD 일부만 바뀌었을 때 mesh
/// 일부만 바꾸는 incremental diff는 새 불안정성(부분 갱신 불일치)을 만들 위험이 더 크다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../core/ss_iso_conversion_step.dart';
import '../models/cad_floor_plan.dart' show resolveAutoScale;
import '../models/iso_conversion_result.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_iso_camera_state.dart';
import 'space_scene_builder_v2.dart';

/// 벽/공간에 실측 높이가 없을 때 쓰는 기본 천장고(mm) — [floor_plan_workspace_screen.dart]의
/// `kDefaultCeilingHeightMm`와 같은 통상값이다. 천장고를 사용자가 직접 정하는 화면([CeilingHeightSettings])은
/// 아직 이 신규 MASTER UI FLOW에 연결돼 있지 않아(그 화면이 생기기 전까지), 지금은 이 통상값을 쓴다.
const double kIsoDefaultCeilingHeightMm = 2400;

class IsoConversionService {
  const IsoConversionService({this.stepDelay = const Duration(milliseconds: 250)});

  /// 각 단계 사이 지연(사용자가 진행을 체감할 수 있게 — [CadConversionService]와 같은 패턴). 테스트에서는
  /// Duration.zero로 줄인다.
  final Duration stepDelay;

  /// [onStep]은 각 단계가 시작될 때 한 번씩, 순서대로 불린다. [previousCamera]가 있으면(재생성 — CAD가
  /// 바뀌어 다시 변환하는 경우) 사용자가 이미 돌려본 Orbit 시점을 그대로 보존한다(§완료조건 "사용자
  /// 디자인 데이터를 소실하지 않는다") — 없으면(처음 변환) scene 기준 기본값을 새로 계산한다.
  Future<IsoConversionResult> convert(
    SsCadScene cadScene, {
    SsIsoCameraState? previousCamera,
    void Function(SsIsoConversionStep step)? onStep,
  }) async {
    try {
      Future<void> tick(SsIsoConversionStep step) async {
        onStep?.call(step);
        if (stepDelay > Duration.zero) await Future<void>.delayed(stepDelay);
      }

      await tick(SsIsoConversionStep.preprocessing);

      final plan = cadScene.plan;
      if (plan.walls.isEmpty && plan.rooms.isEmpty) {
        throw const IsoConversionInputError('3D로 변환할 CAD 데이터가 없습니다. CAD 편집 화면에서 벽이나 공간을 먼저 만들어 주세요.');
      }

      await tick(SsIsoConversionStep.spatialAnalysis);
      final scale = cadScene.scale ?? resolveAutoScale(plan, null);

      await tick(SsIsoConversionStep.architecturalModeling);
      final scene = buildSpaceSceneV2(plan: plan, scale: scale, ceilingHeightMm: kIsoDefaultCeilingHeightMm);
      if (scene.isEmpty) {
        throw const IsoConversionInputError('벽/바닥 구조를 3D로 옮기지 못했습니다. CAD 편집 화면에서 벽이나 공간을 확인해 주세요.');
      }

      // 재질/색상은 buildSpaceSceneV2가 이미 CadWall.materialOverride/CadRoom.materialOverride를
      // 반영해 만든다(기존 엔진 재사용) — 이 단계는 진행 안내용 틱일 뿐 별도 계산을 하지 않는다.
      await tick(SsIsoConversionStep.materialColor);

      await tick(SsIsoConversionStep.isoModelGeneration);
      final camera = previousCamera ?? SsIsoCameraState.defaultForScene(scene);

      return IsoConversionResult(scene: scene, camera: camera, furniture: cadScene.furniture, warnings: scene.warnings);
    } catch (e, st) {
      // 실패 원인을 다른 것(예: 네트워크 오류 — 이 서비스는 네트워크를 전혀 쓰지 않는다)으로 둔갑시키지
      // 않는다 — 실제 타입/메시지는 로그로 남기고, 원래 타입 그대로 다시 던져 호출한 쪽([SsAiTask] 또는
      // [IsoConversionInputError] 전용 처리)이 올바르게 구분해서 보여주게 한다.
      debugPrint('IsoConversionService.convert 실패 (${e.runtimeType}): $e\n$st');
      rethrow;
    }
  }
}
