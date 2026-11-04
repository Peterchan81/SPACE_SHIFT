/// SS015 — 3D ISO 최종 렌더링 엔진([IsoRenderService])의 결과값. SS013이 이미 만든
/// [buildIsoEditorScene] 결과([SpaceSceneV2] — 구조+재질+가구+조명+설비가 전부 반영된 완성된 ISO
/// 모델)와 ISO Orbit 카메라 보존값([SsIsoCameraState])을 그대로 담는다. 새 3D geometry 모델을
/// 만들지 않는다(§구현 원칙 "기존 엔진 재사용", [IsoConversionResult]와 같은 생각).
library;

import 'space_scene_v2.dart';
import 'ss_iso_camera_state.dart';

/// 미리보기 렌더링과 최종 렌더링을 구분하는 값(§구현 범위 "미리보기 렌더링과 최종 렌더링을 구분할
/// 수 있는 구조") — [IsoRenderService.render]가 어떤 요청이었는지 결과에 그대로 남겨, 저장된
/// payload만 보고도 어떤 렌더링이었는지 알 수 있다.
enum SsIsoRenderQuality {
  preview('미리보기'),
  full('최종');

  const SsIsoRenderQuality(this.label);
  final String label;
}

class IsoRenderResult {
  const IsoRenderResult({
    required this.scene,
    required this.camera,
    this.quality = SsIsoRenderQuality.full,
    this.warnings = const [],
  });

  /// 렌더링해 만든 최종 3D ISO 모델(벽/문/창/바닥/천장/가구/조명/설비 — [buildIsoEditorScene] 결과 그대로).
  final SpaceSceneV2 scene;

  /// ISO Orbit에 쓸 카메라 기본값(또는 재생성 시 보존된 이전 값).
  final SsIsoCameraState camera;

  /// 이 결과가 미리보기였는지 최종 렌더링이었는지.
  final SsIsoRenderQuality quality;

  /// [SpaceSceneV2.warnings] 그대로(문/창 미반영 등 정직한 안내 — 지어내지 않는다).
  final List<String> warnings;
}

/// SS015 — 렌더링할 3D ISO 디자인이 전혀 없다는 사실을 일반(엔진) 오류와 구분해 알리기 위한 전용
/// 예외([IsoConversionInputError]와 같은 역할). 사용자는 3D 디자인 화면(SS013/SS014)으로 돌아가
/// 벽/공간을 먼저 만들어야 한다 — 같은 입력을 그대로 "다시 시도"해도 결과가 달라지지 않으므로
/// 재시도 대상이 아니다([SsAiStatus.inputFixNeeded]로만 다룬다).
class IsoRenderInputError implements Exception {
  const IsoRenderInputError(this.message);

  final String message;

  @override
  String toString() => message;
}
