/// SS009 — MASTER UI 6(평면도 확인·보정)이 다루는 "AI 인식 결과 위에 사용자가
/// 더하는 보정" 데이터. [SSSpatialModel](AI 인식 결과, SS008 산출물)은 바꾸지
/// 않고 그대로 둔 채, 이 장면이 그 위에 "무엇을 어떻게 고쳤는가"만 따로 기록한다
/// (§7 "원본 → AI 결과 → 사용자 수정" 원칙과 같다 — AI 결과 자체를 덮어쓰지 않고
/// 보정 레이어를 분리해 원본/AI 결과/최종 결과를 항상 비교할 수 있게 한다).
///
/// - [strokes] — 펜/형광펜 자유 그리기(지우개로 일부만 지울 수 있다). 사람이 눈으로
///   확인할 부분을 표시하는 "표시·메모" 레이어다.
/// - 구조 보정(문→창 같은 의미 수정·잘못된 벽 삭제·누락 벽/문/창 추가)은
///   [removedWallIds]/[removedOpeningIds]/[removedObjectIds]/[openingKindOverrides]/
///   [addedWalls]/[addedOpenings]로 표현한다 — AI 인식 결과를 직접 변형하지 않고
///   "무엇을 지웠고 무엇을 더했는가"만 보존한다.
/// - [resolvedReviewIds] — "확인 필요" 표시가 붙은 요소 중 사용자가 이미 확인했다고
///   표시한 id. [applyReviewToSpatialModel]이 최종 모델에 반영한다(해당 엔티티의
///   reviewNeeded를 false로 내린다).
library;

import 'package:flutter/foundation.dart';

import 'floor_plan_geometry.dart';
import 'ss_spatial_model.dart';

/// 펜/형광펜(자유 그리기 주석) — 지우개는 그려진 선을 지우는 동작이라 선 자체의
/// 종류로 저장하지 않는다.
enum SsAnnotationTool { pen, highlighter }

@immutable
class SsAnnotationStroke {
  const SsAnnotationStroke({required this.id, required this.tool, required this.colorValue, required this.strokeWidth, required this.points});

  final int id;
  final SsAnnotationTool tool;
  final int colorValue;
  final double strokeWidth;
  final List<Point2> points;

  Map<String, Object?> toJson() => {
    'id': id,
    'tool': tool.name,
    'colorValue': colorValue,
    'strokeWidth': strokeWidth,
    'points': [for (final p in points) {'x': p.x, 'y': p.y}],
  };

  static SsAnnotationStroke? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final tool = SsAnnotationTool.values.where((t) => t.name == j['tool']).firstOrNull;
    final colorValue = j['colorValue'];
    final strokeWidth = j['strokeWidth'];
    final pts = j['points'];
    if (id is! int || tool == null || colorValue is! int || strokeWidth is! num || pts is! List) return null;
    final points = <Point2>[];
    for (final p in pts) {
      if (p is! Map) continue;
      final x = p['x'], y = p['y'];
      if (x is num && y is num) points.add(Point2(x.toDouble(), y.toDouble()));
    }
    if (points.isEmpty) return null;
    return SsAnnotationStroke(id: id, tool: tool, colorValue: colorValue, strokeWidth: strokeWidth.toDouble(), points: points);
  }
}

/// 사용자가 새로 더한 벽(간단한 선분) — AI가 놓친 벽을 보탤 때 쓴다.
@immutable
class SsAddedWall {
  const SsAddedWall({required this.id, required this.start, required this.end});
  final String id;
  final Point2 start;
  final Point2 end;

  Map<String, Object?> toJson() => {
    'id': id,
    'start': {'x': start.x, 'y': start.y},
    'end': {'x': end.x, 'y': end.y},
  };

  static SsAddedWall? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final s = j['start'], e = j['end'];
    if (id is! String || s is! Map || e is! Map) return null;
    final sx = s['x'], sy = s['y'], ex = e['x'], ey = e['y'];
    if (sx is! num || sy is! num || ex is! num || ey is! num) return null;
    return SsAddedWall(id: id, start: Point2(sx.toDouble(), sy.toDouble()), end: Point2(ex.toDouble(), ey.toDouble()));
  }
}

/// 사용자가 새로 더한 개구부(문/창) — 벽 위 상대위치가 아니라 평면도 위 절대
/// 중심점(정규화 좌표)으로만 표시한다(AI가 아예 놓친 요소라 기준 벽이 불확실할
/// 수 있다 — 위치를 거짓으로 꾸며 특정 벽에 붙이지 않는다).
@immutable
class SsAddedOpening {
  const SsAddedOpening({required this.id, required this.kind, required this.center});
  final String id;
  final SSOpeningKind kind;
  final Point2 center;

  Map<String, Object?> toJson() => {'id': id, 'kind': kind.name, 'center': {'x': center.x, 'y': center.y}};

  static SsAddedOpening? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = SSOpeningKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final c = j['center'];
    if (id is! String || kind == null || c is! Map) return null;
    final x = c['x'], y = c['y'];
    if (x is! num || y is! num) return null;
    return SsAddedOpening(id: id, kind: kind, center: Point2(x.toDouble(), y.toDouble()));
  }
}

@immutable
class SsReviewScene {
  const SsReviewScene({
    this.strokes = const [],
    this.nextStrokeId = 1,
    this.removedWallIds = const {},
    this.removedOpeningIds = const {},
    this.removedObjectIds = const {},
    this.openingKindOverrides = const {},
    this.addedWalls = const [],
    this.addedOpenings = const [],
    this.resolvedReviewIds = const {},
    this.nextAddedId = 1,
  });

  static const SsReviewScene empty = SsReviewScene();

  final List<SsAnnotationStroke> strokes;
  final int nextStrokeId;

  final Set<String> removedWallIds;
  final Set<String> removedOpeningIds;
  final Set<String> removedObjectIds;

  /// 문↔창처럼 의미를 바꾼 개구부(원본 id → 바꾼 종류).
  final Map<String, SSOpeningKind> openingKindOverrides;

  final List<SsAddedWall> addedWalls;
  final List<SsAddedOpening> addedOpenings;

  final Set<String> resolvedReviewIds;
  final int nextAddedId;

  bool get isEmpty =>
      strokes.isEmpty &&
      removedWallIds.isEmpty &&
      removedOpeningIds.isEmpty &&
      removedObjectIds.isEmpty &&
      openingKindOverrides.isEmpty &&
      addedWalls.isEmpty &&
      addedOpenings.isEmpty;

  // ---------------- 펜/형광펜/지우개 ----------------

  SsReviewScene addStroke(SsAnnotationTool tool, {required int colorValue, required double strokeWidth, required List<Point2> points}) {
    if (points.length < 2) return this;
    final s = SsAnnotationStroke(id: nextStrokeId, tool: tool, colorValue: colorValue, strokeWidth: strokeWidth, points: points);
    return copyWith(strokes: [...strokes, s], nextStrokeId: nextStrokeId + 1);
  }

  /// 지우개 — [p] 근처(정규화 좌표, [toleranceNormalized] 이내)를 지나는 선을 통째로 지운다.
  SsReviewScene eraseNear(Point2 p, {double toleranceNormalized = 0.02}) {
    final kept = <SsAnnotationStroke>[
      for (final s in strokes)
        if (!s.points.any((q) => q.distanceTo(p) <= toleranceNormalized)) s,
    ];
    if (kept.length == strokes.length) return this;
    return copyWith(strokes: kept);
  }

  // ---------------- 삭제(잘못 인식된 요소) ----------------

  SsReviewScene removeWallById(String id) => id.startsWith('user-wall-')
      ? copyWith(addedWalls: [for (final w in addedWalls) if (w.id != id) w])
      : copyWith(removedWallIds: {...removedWallIds, id});

  SsReviewScene removeOpeningById(String id) => id.startsWith('user-opening-')
      ? copyWith(addedOpenings: [for (final o in addedOpenings) if (o.id != id) o])
      : copyWith(removedOpeningIds: {...removedOpeningIds, id});

  SsReviewScene removeObjectById(String id) => copyWith(removedObjectIds: {...removedObjectIds, id});

  // ---------------- 의미 수정 ----------------

  SsReviewScene setOpeningKind(String openingId, SSOpeningKind kind) =>
      copyWith(openingKindOverrides: {...openingKindOverrides, openingId: kind});

  // ---------------- 누락 요소 추가 ----------------

  SsReviewScene addWallSegment(Point2 start, Point2 end) {
    final w = SsAddedWall(id: 'user-wall-$nextAddedId', start: start, end: end);
    return copyWith(addedWalls: [...addedWalls, w], nextAddedId: nextAddedId + 1);
  }

  SsReviewScene addOpeningAt(SSOpeningKind kind, Point2 center) {
    final o = SsAddedOpening(id: 'user-opening-$nextAddedId', kind: kind, center: center);
    return copyWith(addedOpenings: [...addedOpenings, o], nextAddedId: nextAddedId + 1);
  }

  // ---------------- 확인 필요 항목 처리 ----------------

  SsReviewScene markResolved(String id) => copyWith(resolvedReviewIds: {...resolvedReviewIds, id});

  SsReviewScene markUnresolved(String id) => copyWith(resolvedReviewIds: {for (final i in resolvedReviewIds) if (i != id) i});

  SsReviewScene copyWith({
    List<SsAnnotationStroke>? strokes,
    int? nextStrokeId,
    Set<String>? removedWallIds,
    Set<String>? removedOpeningIds,
    Set<String>? removedObjectIds,
    Map<String, SSOpeningKind>? openingKindOverrides,
    List<SsAddedWall>? addedWalls,
    List<SsAddedOpening>? addedOpenings,
    Set<String>? resolvedReviewIds,
    int? nextAddedId,
  }) => SsReviewScene(
    strokes: strokes ?? this.strokes,
    nextStrokeId: nextStrokeId ?? this.nextStrokeId,
    removedWallIds: removedWallIds ?? this.removedWallIds,
    removedOpeningIds: removedOpeningIds ?? this.removedOpeningIds,
    removedObjectIds: removedObjectIds ?? this.removedObjectIds,
    openingKindOverrides: openingKindOverrides ?? this.openingKindOverrides,
    addedWalls: addedWalls ?? this.addedWalls,
    addedOpenings: addedOpenings ?? this.addedOpenings,
    resolvedReviewIds: resolvedReviewIds ?? this.resolvedReviewIds,
    nextAddedId: nextAddedId ?? this.nextAddedId,
  );

  Map<String, Object?> toJson() => {
    'strokes': [for (final s in strokes) s.toJson()],
    'nextStrokeId': nextStrokeId,
    'removedWallIds': removedWallIds.toList(),
    'removedOpeningIds': removedOpeningIds.toList(),
    'removedObjectIds': removedObjectIds.toList(),
    'openingKindOverrides': {for (final e in openingKindOverrides.entries) e.key: e.value.name},
    'addedWalls': [for (final w in addedWalls) w.toJson()],
    'addedOpenings': [for (final o in addedOpenings) o.toJson()],
    'resolvedReviewIds': resolvedReviewIds.toList(),
    'nextAddedId': nextAddedId,
  };

  /// 저장된 JSON에서 — 깨졌거나 없으면 빈 보정([empty]).
  static SsReviewScene tryFromJson(Object? j) {
    if (j is! Map) return empty;
    final strokesJ = j['strokes'];
    final overridesJ = j['openingKindOverrides'];
    final overrides = <String, SSOpeningKind>{};
    if (overridesJ is Map) {
      for (final e in overridesJ.entries) {
        final kind = SSOpeningKind.values.where((k) => k.name == e.value).firstOrNull;
        if (kind != null) overrides['${e.key}'] = kind;
      }
    }
    final addedWallsJ = j['addedWalls'];
    final addedOpeningsJ = j['addedOpenings'];
    return SsReviewScene(
      strokes: strokesJ is List ? [for (final s in strokesJ) ?SsAnnotationStroke.tryFromJson(s)] : const [],
      nextStrokeId: j['nextStrokeId'] is int ? j['nextStrokeId'] as int : 1,
      removedWallIds: j['removedWallIds'] is List ? {for (final v in j['removedWallIds'] as List) '$v'} : const {},
      removedOpeningIds: j['removedOpeningIds'] is List ? {for (final v in j['removedOpeningIds'] as List) '$v'} : const {},
      removedObjectIds: j['removedObjectIds'] is List ? {for (final v in j['removedObjectIds'] as List) '$v'} : const {},
      openingKindOverrides: overrides,
      addedWalls: addedWallsJ is List ? [for (final w in addedWallsJ) ?SsAddedWall.tryFromJson(w)] : const [],
      addedOpenings: addedOpeningsJ is List ? [for (final o in addedOpeningsJ) ?SsAddedOpening.tryFromJson(o)] : const [],
      resolvedReviewIds: j['resolvedReviewIds'] is List ? {for (final v in j['resolvedReviewIds'] as List) '$v'} : const {},
      nextAddedId: j['nextAddedId'] is int ? j['nextAddedId'] as int : 1,
    );
  }
}

/// SS009 완료 조건 — 수정된 구조 데이터를 SS010에 안정적으로 전달하기 위해, AI
/// 인식 결과([base])에 사용자 보정([review])을 반영한 최종 [SSSpatialModel]을
/// 만든다. [base] 자체는 바꾸지 않는다(항상 "원본 AI 인식 결과"로 비교할 수 있게).
SSSpatialModel applyReviewToSpatialModel(SSSpatialModel base, SsReviewScene review) {
  bool resolved(String id) => review.resolvedReviewIds.contains(id);

  SSSpace mapSpace(SSSpace s) => resolved(s.id) ? s.copyWith(reviewNeeded: false) : s;

  SSWall mapWall(SSWall w) {
    if (!resolved(w.id)) return w;
    return SSWall(
      id: w.id,
      start: w.start,
      end: w.end,
      thicknessNormalized: w.thicknessNormalized,
      kind: w.kind,
      confidence: w.confidence,
      separatesSpaceIds: w.separatesSpaceIds,
      source: w.source,
      reviewNeeded: false,
    );
  }

  SSOpening mapOpening(SSOpening o) {
    final overridden = review.openingKindOverrides[o.id];
    final isResolved = resolved(o.id);
    if (overridden == null && !isResolved) return o;
    final kind = overridden ?? o.kind;
    final reviewNeeded = isResolved ? false : o.reviewNeeded;
    return SSOpening(
      id: o.id,
      kind: kind,
      center: o.center,
      widthNormalized: o.widthNormalized,
      confidence: o.confidence,
      wallId: o.wallId,
      parentWallId: o.parentWallId,
      startT: o.startT,
      endT: o.endT,
      connectsSpaceIds: o.connectsSpaceIds,
      source: overridden != null ? SSEntitySource.user : o.source,
      reviewNeeded: reviewNeeded,
      reviewReasons: reviewNeeded ? o.reviewReasons : const [],
    );
  }

  SSObjectCandidate mapObject(SSObjectCandidate o) {
    if (!resolved(o.id)) return o;
    return SSObjectCandidate(id: o.id, polygon: o.polygon, kind: o.kind, containingSpaceId: o.containingSpaceId, source: o.source, reviewNeeded: false);
  }

  SSStructuralElement mapStructural(SSStructuralElement s) {
    if (!resolved(s.id)) return s;
    return SSStructuralElement(id: s.id, kind: s.kind, polygon: s.polygon, confidence: s.confidence, source: s.source, reviewNeeded: false);
  }

  final walls = [
    for (final w in base.walls)
      if (!review.removedWallIds.contains(w.id)) mapWall(w),
    for (final a in review.addedWalls)
      SSWall(id: a.id, start: a.start, end: a.end, thicknessNormalized: 0.02, kind: SSWallKind.interior, confidence: 1.0, source: SSEntitySource.user),
  ];

  final openings = [
    for (final o in base.openings)
      if (!review.removedOpeningIds.contains(o.id)) mapOpening(o),
    for (final a in review.addedOpenings)
      SSOpening(id: a.id, kind: a.kind, center: a.center, widthNormalized: 0.04, confidence: 1.0, source: SSEntitySource.user),
  ];

  final objects = [for (final o in base.objects) if (!review.removedObjectIds.contains(o.id)) mapObject(o)];
  final spaces = [for (final s in base.spaces) mapSpace(s)];
  final structuralElements = [for (final s in base.structuralElements) mapStructural(s)];

  return SSSpatialModel(
    sourceWidthPx: base.sourceWidthPx,
    sourceHeightPx: base.sourceHeightPx,
    spaces: spaces,
    walls: walls,
    openings: openings,
    objects: objects,
    warnings: base.warnings,
    boundaries: base.boundaries,
    structuralElements: structuralElements,
    dimensions: base.dimensions,
    wallEdges: base.wallEdges,
    floorDomain: base.floorDomain,
  );
}
