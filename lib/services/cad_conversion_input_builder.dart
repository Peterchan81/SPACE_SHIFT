/// SS010 — SS009(평면도 확인·보정)/SS005(직접 그리기)가 각자 다른 형식으로 남긴 "확정된 공간
/// 데이터"(SsDataSlot.userCorrections, 없으면 recognitionData)를 CAD 변환 엔진이 공통으로 쓰는
/// [SSSpatialModel] 하나로 통일한다. 새 변환 로직만 더할 뿐, 기존 [SsReviewEditorController]/
/// [SsDrawEditorController]가 만든 데이터 자체는 전혀 바꾸지 않는다(기존 코드 보호).
library;

import 'dart:math' as math;

import '../core/ss_project.dart';
import '../models/cad_floor_plan.dart' show FloorPlanScale, ScaleSource;
import '../models/floor_plan_geometry.dart' show Point2;
import '../models/ss_draw_scene.dart';
import '../models/ss_spatial_model.dart';
import '../models/ss_spatial_model_json.dart';

/// CAD 변환 엔진 입력 — 공통 공간모델([model])과, 직접 그리기처럼 실제 mm 단위가 이미 확정된
/// 경우에만 있는 [knownScale]([ScaleSource.measured]). null이면(평면도 업로드/AI 인식 경로) 변환
/// 엔진이 [resolveAutoScale]로 추정한다.
class CadConversionInput {
  const CadConversionInput({required this.model, this.knownScale});

  final SSSpatialModel model;
  final FloorPlanScale? knownScale;
}

/// [project]의 확정된 공간 데이터에서 [CadConversionInput]을 만든다. 알아볼 수 없는 형식이거나
/// 완전히 비어 있으면 null — 호출부는 "입력 수정 필요"로 다뤄야 한다(이전 단계로 돌아가 안내).
CadConversionInput? buildCadConversionInput(SsProject project) {
  final corrections = project.data[SsDataSlot.userCorrections]?.payload;
  if (corrections != null) {
    final input = _fromPayload(corrections);
    if (input != null) return input;
  }
  final recognition = project.data[SsDataSlot.recognitionData]?.payload;
  if (recognition != null) {
    final model = ssSpatialModelFromJson(recognition['model']);
    if (model != null) return CadConversionInput(model: model);
  }
  return null;
}

CadConversionInput? _fromPayload(Map<String, Object?> payload) {
  if (payload['kind'] == 'directDraw') {
    final scene = SsDrawScene.tryFromJson(payload['scene']);
    return scene.isEmpty ? null : _fromDrawScene(scene);
  }
  // SS009가 남기는 'ssSpatialModel' 보정 결과 — kind가 없는 예전 데이터도 'model' 키만 있으면 받아들인다.
  final model = ssSpatialModelFromJson(payload['model']);
  return model == null ? null : CadConversionInput(model: model);
}

/// SS005(직접 그리기)의 mm 문서 좌표([SsDrawScene])를 CAD 엔진이 쓰는 0..1 정규화 좌표
/// ([SSSpatialModel])로 옮긴다 — 실제 mm 치수는 이미 사용자가 그린 그대로 정확하므로(실측과 동급),
/// [resolveAutoScale]의 추정을 거치지 않고 [ScaleSource.measured] 축척을 직접 만들어 돌려준다.
CadConversionInput _fromDrawScene(SsDrawScene scene) {
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (final w in scene.walls) {
    for (final p in [w.a, w.b]) {
      if (p.xMm < minX) minX = p.xMm;
      if (p.yMm < minY) minY = p.yMm;
      if (p.xMm > maxX) maxX = p.xMm;
      if (p.yMm > maxY) maxY = p.yMm;
    }
  }
  final widthMm = (maxX - minX) > 0 ? maxX - minX : 1.0;
  final heightMm = (maxY - minY) > 0 ? maxY - minY : 1.0;
  final sourceWidthPx = widthMm.round().clamp(1, 1 << 30);
  final sourceHeightPx = heightMm.round().clamp(1, 1 << 30);
  final diagonalMm = math.sqrt(sourceWidthPx * sourceWidthPx + sourceHeightPx * sourceHeightPx);

  Point2 normalize(double xMm, double yMm) => Point2((xMm - minX) / sourceWidthPx, (yMm - minY) / sourceHeightPx);

  final walls = [
    for (final w in scene.walls)
      SSWall(
        id: 'drawWall${w.id}',
        start: normalize(w.a.xMm, w.a.yMm),
        end: normalize(w.b.xMm, w.b.yMm),
        thicknessNormalized: w.thicknessMm / diagonalMm,
        kind: w.type == SsDrawWallType.exterior ? SSWallKind.exterior : SSWallKind.interior,
        confidence: 1.0,
        source: SSEntitySource.user,
      ),
  ];
  final wallById = {for (final w in scene.walls) w.id: w};
  final openings = [
    for (final o in scene.openings)
      if (wallById[o.wallId] != null)
        SSOpening(
          id: 'drawOpening${o.id}',
          kind: o.kind == SsDrawOpeningKind.door ? SSOpeningKind.door : SSOpeningKind.window,
          center: normalize(wallById[o.wallId]!.pointAt(o.alongMm).xMm, wallById[o.wallId]!.pointAt(o.alongMm).yMm),
          widthNormalized: o.widthMm / diagonalMm,
          confidence: 1.0,
          wallId: 'drawWall${o.wallId}',
          source: SSEntitySource.user,
        ),
  ];

  final model = SSSpatialModel(
    sourceWidthPx: sourceWidthPx,
    sourceHeightPx: sourceHeightPx,
    spaces: const [],
    walls: walls,
    openings: openings,
    objects: const [],
    warnings: const [],
  );

  final scale = FloorPlanScale(
    mmPerPixel: 1.0,
    referenceStart: const Point2(0, 0),
    referenceEnd: const Point2(1, 1),
    referenceLengthMm: diagonalMm,
    source: ScaleSource.measured,
  );

  return CadConversionInput(model: model, knownScale: scale);
}
