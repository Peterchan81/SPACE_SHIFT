/// SS011 — CAD 편집 화면이 [CadFloorPlan]/[FloorPlanScale] 편집 결과를 그대로
/// 프로젝트 데이터([SsDataSlot.cadData])에 저장·복원할 수 있게 하는 JSON 왕복
/// 변환. 기존 [cad_floor_plan.dart]는 건드리지 않고(기존 코드 보호), 그 모델을
/// 그대로 감싸는 순수 함수만 새로 둔다 — [ss_spatial_model_json.dart]와 같은
/// 패턴(점2/목록을 각각 변환해 합치는 방식)이다.
library;

import 'cad_floor_plan.dart';
import 'floor_plan_geometry.dart';
import 'ss_spatial_model.dart' show SSRoomType;

Map<String, Object?> _point2ToJson(Point2 p) => {'x': p.x, 'y': p.y};

Point2? _point2FromJson(Object? j) {
  if (j is! Map) return null;
  final x = j['x'];
  final y = j['y'];
  if (x is! num || y is! num) return null;
  return Point2(x.toDouble(), y.toDouble());
}

Map<String, Object?> cadWallToJson(CadWall w) => {
  'id': w.id,
  'start': _point2ToJson(w.start),
  'end': _point2ToJson(w.end),
  'thicknessNormalized': w.thicknessNormalized,
  'wallType': w.wallType.name,
  'confidence': w.confidence,
  'source': w.source.name,
  'edited': w.edited,
  if (w.heightMm != null) 'heightMm': w.heightMm,
  'reviewNeeded': w.reviewNeeded,
  'reviewReasons': w.reviewReasons,
};

CadWall? cadWallFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final start = _point2FromJson(j['start']);
  final end = _point2FromJson(j['end']);
  final thickness = j['thicknessNormalized'];
  final confidence = j['confidence'];
  if (id is! String || start == null || end == null || thickness is! num || confidence is! num) return null;
  final wallType = CadWallType.values.where((t) => t.name == j['wallType']).firstOrNull ?? CadWallType.interior;
  final source = CadElementSource.values.where((s) => s.name == j['source']).firstOrNull ?? CadElementSource.analyzed;
  final reasons = j['reviewReasons'];
  return CadWall(
    id: id,
    start: start,
    end: end,
    thicknessNormalized: thickness.toDouble(),
    wallType: wallType,
    confidence: confidence.toDouble(),
    source: source,
    edited: j['edited'] == true,
    heightMm: j['heightMm'] is num ? (j['heightMm'] as num).toDouble() : null,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: reasons is List ? [for (final r in reasons) '$r'] : const [],
  );
}

Map<String, Object?> cadOpeningToJson(CadOpening o) => {
  'id': o.id,
  'type': o.type.name,
  'center': _point2ToJson(o.center),
  'widthNormalized': o.widthNormalized,
  'confidence': o.confidence,
  if (o.wallId != null) 'wallId': o.wallId,
  'source': o.source.name,
  'edited': o.edited,
  'reviewNeeded': o.reviewNeeded,
  'reviewReasons': o.reviewReasons,
};

CadOpening? cadOpeningFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final center = _point2FromJson(j['center']);
  final width = j['widthNormalized'];
  final confidence = j['confidence'];
  if (id is! String || center == null || width is! num || confidence is! num) return null;
  final type = OpeningType.values.where((t) => t.name == j['type']).firstOrNull ?? OpeningType.unknown;
  final source = CadElementSource.values.where((s) => s.name == j['source']).firstOrNull ?? CadElementSource.analyzed;
  final reasons = j['reviewReasons'];
  return CadOpening(
    id: id,
    type: type,
    center: center,
    widthNormalized: width.toDouble(),
    confidence: confidence.toDouble(),
    wallId: j['wallId'] is String ? j['wallId'] as String : null,
    source: source,
    edited: j['edited'] == true,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: reasons is List ? [for (final r in reasons) '$r'] : const [],
  );
}

Map<String, Object?> cadRoomToJson(CadRoom r) => {
  'id': r.id,
  'polygon': [for (final p in r.polygon) _point2ToJson(p)],
  'areaNormalized': r.areaNormalized,
  'confidence': r.confidence,
  'closed': r.closed,
  'source': r.source.name,
  if (r.name != null) 'name': r.name,
  'reviewNeeded': r.reviewNeeded,
  'reviewReasons': r.reviewReasons,
  'roomType': r.roomType.name,
};

CadRoom? cadRoomFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final polygonJ = j['polygon'];
  final area = j['areaNormalized'];
  final confidence = j['confidence'];
  if (id is! String || polygonJ is! List || area is! num || confidence is! num) return null;
  final polygon = [for (final p in polygonJ) ?_point2FromJson(p)];
  if (polygon.isEmpty) return null;
  final source = CadElementSource.values.where((s) => s.name == j['source']).firstOrNull ?? CadElementSource.analyzed;
  final roomType = SSRoomType.values.where((t) => t.name == j['roomType']).firstOrNull ?? SSRoomType.other;
  final reasons = j['reviewReasons'];
  return CadRoom(
    id: id,
    polygon: polygon,
    areaNormalized: area.toDouble(),
    confidence: confidence.toDouble(),
    closed: j['closed'] != false,
    source: source,
    name: j['name'] is String ? j['name'] as String : null,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: reasons is List ? [for (final r in reasons) '$r'] : const [],
    roomType: roomType,
  );
}

Map<String, Object?> cadFloorPlanToJson(CadFloorPlan p) => {
  'sourceWidthPx': p.sourceWidthPx,
  'sourceHeightPx': p.sourceHeightPx,
  'walls': [for (final w in p.walls) cadWallToJson(w)],
  'openings': [for (final o in p.openings) cadOpeningToJson(o)],
  'rooms': [for (final r in p.rooms) cadRoomToJson(r)],
  'warnings': p.warnings,
};

/// SS011 §가구/주요 객체 — [objectCandidates](참고/진단 전용, §cad_floor_plan.dart)는
/// 사용자 편집 대상이 아니므로 이 왕복 변환에 포함하지 않는다(그대로 비워 둠).
CadFloorPlan? cadFloorPlanFromJson(Object? j) {
  if (j is! Map) return null;
  final w = j['sourceWidthPx'];
  final h = j['sourceHeightPx'];
  if (w is! num || h is! num) return null;
  final wallsJ = j['walls'];
  final openingsJ = j['openings'];
  final roomsJ = j['rooms'];
  final warningsJ = j['warnings'];
  return CadFloorPlan(
    sourceWidthPx: w.toInt(),
    sourceHeightPx: h.toInt(),
    walls: wallsJ is List ? [for (final e in wallsJ) ?cadWallFromJson(e)] : const [],
    openings: openingsJ is List ? [for (final e in openingsJ) ?cadOpeningFromJson(e)] : const [],
    rooms: roomsJ is List ? [for (final e in roomsJ) ?cadRoomFromJson(e)] : const [],
    warnings: warningsJ is List ? [for (final e in warningsJ) '$e'] : const [],
  );
}

Map<String, Object?> floorPlanScaleToJson(FloorPlanScale s) => {
  'mmPerPixel': s.mmPerPixel,
  'source': s.source.name,
  'referenceLengthMm': s.referenceLengthMm,
  'referenceStart': _point2ToJson(s.referenceStart),
  'referenceEnd': _point2ToJson(s.referenceEnd),
};

FloorPlanScale? floorPlanScaleFromJson(Object? j) {
  if (j is! Map) return null;
  final mmPerPixel = j['mmPerPixel'];
  final refLen = j['referenceLengthMm'];
  final start = _point2FromJson(j['referenceStart']);
  final end = _point2FromJson(j['referenceEnd']);
  if (mmPerPixel is! num || refLen is! num || start == null || end == null) return null;
  final source = ScaleSource.values.where((s) => s.name == j['source']).firstOrNull ?? ScaleSource.unknown;
  return FloorPlanScale(
    mmPerPixel: mmPerPixel.toDouble(),
    referenceStart: start,
    referenceEnd: end,
    referenceLengthMm: refLen.toDouble(),
    source: source,
  );
}
