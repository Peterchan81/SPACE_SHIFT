/// SS012 — 3D ISO 변환 엔진([IsoConversionService])의 결과값. 기존 [SpaceSceneV2](3D geometry,
/// [buildSpaceSceneV2])와 CAD에서 넘어온 [SsCadFurniture](재생성해도 사용자가 CAD에서 배치한 가구를
/// 잃지 않도록 그대로 보존), ISO Orbit 카메라 기본값/보존값([SsIsoCameraState])을 함께 담는다. 새
/// 3D geometry 모델을 만들지 않는다(§구현 원칙 "기존 엔진 재사용", [CadConversionResult]와 같은
/// 생각).
library;

import 'space_scene_v2.dart';
import 'ss_cad_scene.dart' show SsCadFurniture;
import 'ss_iso_camera_state.dart';

class IsoConversionResult {
  const IsoConversionResult({
    required this.scene,
    required this.camera,
    this.furniture = const [],
    this.warnings = const [],
  });

  /// 변환해 만든 3D 건축 모델(벽/문/창/바닥/천장 — [buildSpaceSceneV2] 결과 그대로).
  final SpaceSceneV2 scene;

  /// ISO Orbit에 쓸 카메라 기본값(또는 재생성 시 보존된 이전 값).
  final SsIsoCameraState camera;

  /// CAD(SS011)에서 넘어온 가구 배치 — 이 WO가 직접 다루지 않고(가구 3D 배치는 SS011의 CAD 가구
  /// 배치를 그대로 승계) 그대로 통과시킨다. 재생성해도 소실되지 않는다.
  final List<SsCadFurniture> furniture;

  /// [SpaceSceneV2.warnings] 그대로(문/창 미반영 등 정직한 안내 — 지어내지 않는다).
  final List<String> warnings;
}

/// SS012 — 변환할 CAD 구조가 전혀 없다는 사실을 일반(엔진) 오류와 구분해 알리기 위한 전용 예외
/// ([CadConversionInputError]와 같은 역할). 사용자는 CAD 편집 화면(SS011)으로 돌아가 벽/공간을
/// 먼저 만들어야 한다 — 같은 입력을 그대로 "다시 시도"해도 결과가 달라지지 않으므로 재시도 대상이
/// 아니다([SsAiStatus.inputFixNeeded]로만 다룬다).
class IsoConversionInputError implements Exception {
  const IsoConversionInputError(this.message);

  final String message;

  @override
  String toString() => message;
}
