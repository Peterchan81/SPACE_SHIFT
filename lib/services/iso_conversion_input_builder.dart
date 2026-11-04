/// SS012 — CAD 편집(SS011, [CadEditorScreen])이 [SsDataSlot.cadData]에 남긴 CAD 데이터를 3D ISO
/// 변환 입력([SsCadScene])으로 통일한다. [CadEditorScreen._sceneFromPayload]와 같은 두 가지 형식
/// (신규 'ssCadScene'과 SS010이 남기는 레거시 {'model': SSSpatialModel JSON})을 모두 읽는다 —
/// private 메서드라 화면 간 공유할 수 없어 같은 파싱 규칙을 여기 한 곳에 다시 둔다. 새 CAD 파싱
/// 로직을 만들지 않고 기존 [SsCadScene.tryFromJson]/[cadFloorPlanFromSpatialModelCompat]를 그대로
/// 재사용한다.
library;

import '../core/ss_project.dart';
import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_spatial_model_json.dart';
import '../screens/cad_floor_plan_from_spatial_model_shim.dart' show cadFloorPlanFromSpatialModelCompat;

/// [project]의 cadData 칸에서 [SsCadScene]을 만든다. 칸이 없거나 알아볼 수 없는 형식이면 null —
/// 호출부는 "CAD 편집을 먼저 완료"로 다뤄야 한다.
SsCadScene? buildIsoConversionInput(SsProject project) {
  final payload = project.data[SsDataSlot.cadData]?.payload;
  if (payload == null) return null;
  return sceneFromCadDataPayload(payload);
}

SsCadScene? sceneFromCadDataPayload(Map<String, Object?> payload) {
  if (payload['kind'] == 'ssCadScene') return SsCadScene.tryFromJson(payload['scene']);
  final model = ssSpatialModelFromJson(payload['model']);
  if (model == null) return null;
  final plan = cadFloorPlanFromSpatialModelCompat(model);
  final scaleJson = payload['scale'];
  final scale = scaleJson is Map ? _legacyScaleFromJson(scaleJson) : null;
  return SsCadScene(plan: plan, scale: scale);
}

FloorPlanScale? _legacyScaleFromJson(Map j) {
  final mmPerPixel = j['mmPerPixel'];
  final refLen = j['referenceLengthMm'];
  final start = j['referenceStart'];
  final end = j['referenceEnd'];
  if (mmPerPixel is! num || refLen is! num || start is! Map || end is! Map) return null;
  final sx = start['x'];
  final sy = start['y'];
  final ex = end['x'];
  final ey = end['y'];
  if (sx is! num || sy is! num || ex is! num || ey is! num) return null;
  final sourceName = j['source'];
  final source = ScaleSource.values.where((s) => s.name == sourceName).firstOrNull ?? ScaleSource.unknown;
  return FloorPlanScale(
    mmPerPixel: mmPerPixel.toDouble(),
    referenceStart: Point2(sx.toDouble(), sy.toDouble()),
    referenceEnd: Point2(ex.toDouble(), ey.toDouble()),
    referenceLengthMm: refLen.toDouble(),
    source: source,
  );
}
