/// SS008 — [SSSpatialModel](AI가 평면도에서 인식한 구조화된 공간 모델)을
/// 프로젝트 저장 칸([SsDataSlot.recognitionData], JSON Map)에 담거나
/// 복원하기 위한 코덱. 기존 ss_spatial_model.dart는 고치지 않고(기존 코드
/// 보호), 이 파일에서만 직렬화를 추가한다.
///
/// 알 수 없는/깨진 값은 조용히 기본값으로 메우지 않고 null을 돌려주는
/// 쪽(엔티티 단위)으로 방어하되, 전체 모델이 깨졌을 때만 null을 돌려준다
/// (SsProject.tryFromJson과 같은 원칙 — 호출부가 마지막 정상 상태로 되돌아갈
/// 수 있게).
library;

import 'floor_plan_geometry.dart' show Point2;
import 'ss_spatial_model.dart';

Map<String, Object?> _point2ToJson(Point2 p) => {'x': p.x, 'y': p.y};

Point2? _point2FromJson(Object? j) {
  if (j is! Map) return null;
  final x = j['x'];
  final y = j['y'];
  if (x is! num || y is! num) return null;
  return Point2(x.toDouble(), y.toDouble());
}

List<Point2> _polygonFromJson(Object? j) {
  final out = <Point2>[];
  if (j is List) {
    for (final e in j) {
      final p = _point2FromJson(e);
      if (p != null) out.add(p);
    }
  }
  return out;
}

List<String> _stringList(Object? j) {
  if (j is! List) return const [];
  return [for (final e in j) '$e'];
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

List<T> _listFrom<T>(Object? j, T? Function(Object? e) fromJson) {
  if (j is! List) return const [];
  final out = <T>[];
  for (final e in j) {
    final v = fromJson(e);
    if (v != null) out.add(v);
  }
  return out;
}

Map<String, Object?> _ssSpaceToJson(SSSpace s) => {
  'id': s.id,
  'polygon': [for (final p in s.polygon) _point2ToJson(p)],
  'areaNormalized': s.areaNormalized,
  'closed': s.closed,
  'confidence': s.confidence,
  'spaceConfidence': s.spaceConfidence.name,
  'adjacentSpaceIds': s.adjacentSpaceIds,
  'boundaryOpeningIds': s.boundaryOpeningIds,
  'boundaryIds': s.boundaryIds,
  'containedObjectIds': s.containedObjectIds,
  'source': s.source.name,
  'reviewNeeded': s.reviewNeeded,
  'reviewReasons': s.reviewReasons,
  'label': s.label,
  'roomType': s.roomType.name,
};

SSSpace? _ssSpaceFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final area = j['areaNormalized'];
  final confidence = j['confidence'];
  if (id is! String || area is! num || confidence is! num) return null;
  return SSSpace(
    id: id,
    polygon: _polygonFromJson(j['polygon']),
    areaNormalized: area.toDouble(),
    closed: j['closed'] == true,
    confidence: confidence.toDouble(),
    spaceConfidence: _enumByName(SSSpaceConfidence.values, j['spaceConfidence']) ?? SSSpaceConfidence.unknown,
    adjacentSpaceIds: _stringList(j['adjacentSpaceIds']),
    boundaryOpeningIds: _stringList(j['boundaryOpeningIds']),
    boundaryIds: _stringList(j['boundaryIds']),
    containedObjectIds: _stringList(j['containedObjectIds']),
    source: _enumByName(SSEntitySource.values, j['source']) ?? SSEntitySource.geometry,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: _stringList(j['reviewReasons']),
    label: j['label'] is String ? j['label'] as String : null,
    roomType: _enumByName(SSRoomType.values, j['roomType']) ?? SSRoomType.other,
  );
}

Map<String, Object?> _ssBoundaryToJson(SSBoundary b) => {
  'id': b.id,
  'spaceId': b.spaceId,
  'start': _point2ToJson(b.start),
  'end': _point2ToJson(b.end),
  'type': b.type.name,
  'confidence': b.confidence,
  'oppositeSpaceId': b.oppositeSpaceId,
  'isExterior': b.isExterior,
  'wallId': b.wallId,
  'openingId': b.openingId,
  'source': b.source.name,
  'reviewNeeded': b.reviewNeeded,
  'reviewReasons': b.reviewReasons,
};

SSBoundary? _ssBoundaryFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final spaceId = j['spaceId'];
  final start = _point2FromJson(j['start']);
  final end = _point2FromJson(j['end']);
  final confidence = j['confidence'];
  if (id is! String || spaceId is! String || start == null || end == null || confidence is! num) return null;
  return SSBoundary(
    id: id,
    spaceId: spaceId,
    start: start,
    end: end,
    type: _enumByName(SSBoundaryType.values, j['type']) ?? SSBoundaryType.unknown,
    confidence: confidence.toDouble(),
    oppositeSpaceId: j['oppositeSpaceId'] is String ? j['oppositeSpaceId'] as String : null,
    isExterior: j['isExterior'] == true,
    wallId: j['wallId'] is String ? j['wallId'] as String : null,
    openingId: j['openingId'] is String ? j['openingId'] as String : null,
    source: _enumByName(SSEntitySource.values, j['source']) ?? SSEntitySource.geometry,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: _stringList(j['reviewReasons']),
  );
}

Map<String, Object?> _ssWallToJson(SSWall w) => {
  'id': w.id,
  'start': _point2ToJson(w.start),
  'end': _point2ToJson(w.end),
  'thicknessNormalized': w.thicknessNormalized,
  'kind': w.kind.name,
  'confidence': w.confidence,
  'separatesSpaceIds': w.separatesSpaceIds,
  'source': w.source.name,
  'reviewNeeded': w.reviewNeeded,
  'reviewReasons': w.reviewReasons,
};

SSWall? _ssWallFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final start = _point2FromJson(j['start']);
  final end = _point2FromJson(j['end']);
  final thickness = j['thicknessNormalized'];
  final confidence = j['confidence'];
  if (id is! String || start == null || end == null || thickness is! num || confidence is! num) return null;
  return SSWall(
    id: id,
    start: start,
    end: end,
    thicknessNormalized: thickness.toDouble(),
    kind: _enumByName(SSWallKind.values, j['kind']) ?? SSWallKind.interior,
    confidence: confidence.toDouble(),
    separatesSpaceIds: _stringList(j['separatesSpaceIds']),
    source: _enumByName(SSEntitySource.values, j['source']) ?? SSEntitySource.geometry,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: _stringList(j['reviewReasons']),
  );
}

Map<String, Object?> _ssWallEdgeToJson(SSWallEdge w) => {
  'id': w.id,
  'start': _point2ToJson(w.start),
  'end': _point2ToJson(w.end),
  'thicknessNormalized': w.thicknessNormalized,
  'kind': w.kind.name,
  'confidence': w.confidence,
  'physicalWallIds': w.physicalWallIds,
  'source': w.source.name,
  'reviewNeeded': w.reviewNeeded,
  'reviewReasons': w.reviewReasons,
};

SSWallEdge? _ssWallEdgeFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final start = _point2FromJson(j['start']);
  final end = _point2FromJson(j['end']);
  final thickness = j['thicknessNormalized'];
  final confidence = j['confidence'];
  if (id is! String || start == null || end == null || thickness is! num || confidence is! num) return null;
  return SSWallEdge(
    id: id,
    start: start,
    end: end,
    thicknessNormalized: thickness.toDouble(),
    kind: _enumByName(SSWallKind.values, j['kind']) ?? SSWallKind.interior,
    confidence: confidence.toDouble(),
    physicalWallIds: _stringList(j['physicalWallIds']),
    source: _enumByName(SSEntitySource.values, j['source']) ?? SSEntitySource.geometry,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: _stringList(j['reviewReasons']),
  );
}

Map<String, Object?> _ssOpeningToJson(SSOpening o) => {
  'id': o.id,
  'kind': o.kind.name,
  'center': _point2ToJson(o.center),
  'widthNormalized': o.widthNormalized,
  'confidence': o.confidence,
  'wallId': o.wallId,
  'parentWallId': o.parentWallId,
  'startT': o.startT,
  'endT': o.endT,
  'connectsSpaceIds': o.connectsSpaceIds,
  'source': o.source.name,
  'reviewNeeded': o.reviewNeeded,
  'reviewReasons': o.reviewReasons,
};

SSOpening? _ssOpeningFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final center = _point2FromJson(j['center']);
  final width = j['widthNormalized'];
  final confidence = j['confidence'];
  if (id is! String || center == null || width is! num || confidence is! num) return null;
  final startT = j['startT'];
  final endT = j['endT'];
  return SSOpening(
    id: id,
    kind: _enumByName(SSOpeningKind.values, j['kind']) ?? SSOpeningKind.unknown,
    center: center,
    widthNormalized: width.toDouble(),
    confidence: confidence.toDouble(),
    wallId: j['wallId'] is String ? j['wallId'] as String : null,
    parentWallId: j['parentWallId'] is String ? j['parentWallId'] as String : null,
    startT: startT is num ? startT.toDouble() : null,
    endT: endT is num ? endT.toDouble() : null,
    connectsSpaceIds: _stringList(j['connectsSpaceIds']),
    source: _enumByName(SSEntitySource.values, j['source']) ?? SSEntitySource.geometry,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: _stringList(j['reviewReasons']),
  );
}

Map<String, Object?> _ssObjectCandidateToJson(SSObjectCandidate o) => {
  'id': o.id,
  'polygon': [for (final p in o.polygon) _point2ToJson(p)],
  'kind': o.kind.name,
  'containingSpaceId': o.containingSpaceId,
  'source': o.source.name,
  'reviewNeeded': o.reviewNeeded,
  'reviewReasons': o.reviewReasons,
};

SSObjectCandidate? _ssObjectCandidateFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  if (id is! String) return null;
  return SSObjectCandidate(
    id: id,
    polygon: _polygonFromJson(j['polygon']),
    kind: _enumByName(SSObjectKind.values, j['kind']) ?? SSObjectKind.unknown,
    containingSpaceId: j['containingSpaceId'] is String ? j['containingSpaceId'] as String : null,
    source: _enumByName(SSEntitySource.values, j['source']) ?? SSEntitySource.geometry,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: _stringList(j['reviewReasons']),
  );
}

Map<String, Object?> _ssStructuralElementToJson(SSStructuralElement s) => {
  'id': s.id,
  'kind': s.kind.name,
  'polygon': [for (final p in s.polygon) _point2ToJson(p)],
  'confidence': s.confidence,
  'source': s.source.name,
  'reviewNeeded': s.reviewNeeded,
  'reviewReasons': s.reviewReasons,
};

SSStructuralElement? _ssStructuralElementFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final confidence = j['confidence'];
  final kind = _enumByName(SSStructuralKind.values, j['kind']);
  if (id is! String || confidence is! num || kind == null) return null;
  return SSStructuralElement(
    id: id,
    kind: kind,
    polygon: _polygonFromJson(j['polygon']),
    confidence: confidence.toDouble(),
    source: _enumByName(SSEntitySource.values, j['source']) ?? SSEntitySource.geometry,
    reviewNeeded: j['reviewNeeded'] == true,
    reviewReasons: _stringList(j['reviewReasons']),
  );
}

Map<String, Object?> _ssDimensionToJson(SSDimension d) => {
  'id': d.id,
  'rawText': d.rawText,
  'parsedValueMm': d.parsedValueMm,
  'appliesToBoundaryId': d.appliesToBoundaryId,
  'confidence': d.confidence.name,
  'source': d.source.name,
};

SSDimension? _ssDimensionFromJson(Object? j) {
  if (j is! Map) return null;
  final id = j['id'];
  final rawText = j['rawText'];
  if (id is! String || rawText is! String) return null;
  final parsed = j['parsedValueMm'];
  return SSDimension(
    id: id,
    rawText: rawText,
    parsedValueMm: parsed is num ? parsed.toDouble() : null,
    appliesToBoundaryId: j['appliesToBoundaryId'] is String ? j['appliesToBoundaryId'] as String : null,
    confidence: _enumByName(SSSpaceConfidence.values, j['confidence']) ?? SSSpaceConfidence.unknown,
    source: _enumByName(SSEntitySource.values, j['source']) ?? SSEntitySource.ocr,
  );
}

/// [SSSpatialModel] 전체를 JSON 가능 Map으로 — [SsProject]의
/// `SsDataSlot.recognitionData` 칸 payload에 그대로 담을 수 있다.
Map<String, Object?> ssSpatialModelToJson(SSSpatialModel m) => {
  'sourceWidthPx': m.sourceWidthPx,
  'sourceHeightPx': m.sourceHeightPx,
  'spaces': [for (final s in m.spaces) _ssSpaceToJson(s)],
  'walls': [for (final w in m.walls) _ssWallToJson(w)],
  'openings': [for (final o in m.openings) _ssOpeningToJson(o)],
  'objects': [for (final o in m.objects) _ssObjectCandidateToJson(o)],
  'warnings': m.warnings,
  'boundaries': [for (final b in m.boundaries) _ssBoundaryToJson(b)],
  'structuralElements': [for (final e in m.structuralElements) _ssStructuralElementToJson(e)],
  'dimensions': [for (final d in m.dimensions) _ssDimensionToJson(d)],
  'wallEdges': [for (final e in m.wallEdges) _ssWallEdgeToJson(e)],
  'floorDomain': m.floorDomain == null ? null : [for (final p in m.floorDomain!) _point2ToJson(p)],
};

/// [ssSpatialModelToJson]의 역 — 저장된 payload가 깨졌으면(필수 값 누락 등)
/// null을 돌려준다(호출부가 "다시 분석"으로 폴백할 수 있게, 가짜 모델을
/// 만들어 내지 않는다).
SSSpatialModel? ssSpatialModelFromJson(Object? j) {
  if (j is! Map) return null;
  final w = j['sourceWidthPx'];
  final h = j['sourceHeightPx'];
  if (w is! num || h is! num) return null;
  return SSSpatialModel(
    sourceWidthPx: w.toInt(),
    sourceHeightPx: h.toInt(),
    spaces: _listFrom(j['spaces'], _ssSpaceFromJson),
    walls: _listFrom(j['walls'], _ssWallFromJson),
    openings: _listFrom(j['openings'], _ssOpeningFromJson),
    objects: _listFrom(j['objects'], _ssObjectCandidateFromJson),
    warnings: _stringList(j['warnings']),
    boundaries: _listFrom(j['boundaries'], _ssBoundaryFromJson),
    structuralElements: _listFrom(j['structuralElements'], _ssStructuralElementFromJson),
    dimensions: _listFrom(j['dimensions'], _ssDimensionFromJson),
    wallEdges: _listFrom(j['wallEdges'], _ssWallEdgeFromJson),
    floorDomain: j['floorDomain'] is List ? _polygonFromJson(j['floorDomain']) : null,
  );
}
