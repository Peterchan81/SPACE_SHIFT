/// SS010 — CAD 자동 변환 엔진([CadConversionService])의 결과값. 기존 [CadFloorPlan]/
/// [FloorPlanScale]/[SSSpatialModel]을 그대로 담아 돌려줄 뿐, 새 geometry 모델을 만들지 않는다
/// (§구현 원칙 "기존 엔진 재사용").
library;

import 'cad_floor_plan.dart';
import 'ss_spatial_model.dart';

class CadConversionResult {
  const CadConversionResult({
    required this.plan,
    required this.scale,
    required this.dxfContent,
    required this.isScaled,
    required this.validatedModel,
  });

  /// Geometry Validation을 거친 뒤 만든 최종 CAD geometry.
  final CadFloorPlan plan;

  /// 이 변환에 실제로 쓰인 축척(직접 그리기처럼 실측이면 [FloorPlanScale.source]가
  /// [ScaleSource.measured]).
  final FloorPlanScale scale;

  /// [plan]/[scale]로 만든 DXF 텍스트([E2eDxfExporter.export] 결과).
  final String dxfContent;

  /// [scale]이 신뢰할 수 있는 실측값이었는지([ScaleSourceX.isReliable]).
  final bool isScaled;

  /// Geometry Validation([TopologyValidator])을 거친 뒤의 [SSSpatialModel] — 저장 칸(cadData)에
  /// 다음 Work Order(SS011)가 그대로 이어받을 수 있도록 함께 보존한다.
  final SSSpatialModel validatedModel;
}

/// SS010 — 변환할 벽/공간이 전혀 없는 등 "입력 자체가 비어 있거나 잘못됐다"는 사실을 일반(엔진) 오류와
/// 구분해 알리기 위한 전용 예외. 사용자는 SS009(평면도 확인·보정)나 SS005(직접 그리기)로 돌아가
/// 입력을 고쳐야 한다 — 같은 입력을 그대로 "다시 시도"해도 결과가 달라지지 않으므로 재시도 대상이
/// 아니다(SsAiStatus.inputFixNeeded로만 다룬다).
class CadConversionInputError implements Exception {
  const CadConversionInputError(this.message);

  final String message;

  @override
  String toString() => message;
}
