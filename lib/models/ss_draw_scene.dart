/// SS005 — 직접 그리기 평면도 에디터가 만드는 구조화 데이터.
///
/// 좌표는 항상 mm(SS001 §11 mm 기본 단위) 문서 좌표계로만 저장한다 — 화면 pan/zoom/stylus 입력과
/// 무관하게, 확대·축소해도 이 값은 절대 바뀌지 않는다([WorkspaceViewportTransform] 문서 좌표 원칙과 같은 생각).
/// 단순 Raster 이미지가 아니라, 벽/개구부를 각자 도형으로 들고 있어 이후 CAD FLOW(SS010)가 그대로 이어받을 수 있다.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// 벽 종류 — 외벽/내벽(CAD 변환 시 두께·마감 기본값에 쓰인다).
enum SsDrawWallType { exterior, interior }

/// 개구부 종류.
enum SsDrawOpeningKind { door, window }

/// 문서 좌표 한 점(mm).
@immutable
class SsDrawPoint {
  const SsDrawPoint(this.xMm, this.yMm);

  final double xMm;
  final double yMm;

  SsDrawPoint translated(double dxMm, double dyMm) => SsDrawPoint(xMm + dxMm, yMm + dyMm);

  double distanceTo(SsDrawPoint other) {
    final dx = xMm - other.xMm;
    final dy = yMm - other.yMm;
    return math.sqrt(dx * dx + dy * dy);
  }

  Map<String, Object?> toJson() => {'x': xMm, 'y': yMm};

  static SsDrawPoint? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final x = j['x'];
    final y = j['y'];
    if (x is! num || y is! num) return null;
    return SsDrawPoint(x.toDouble(), y.toDouble());
  }

  @override
  bool operator ==(Object other) => other is SsDrawPoint && other.xMm == xMm && other.yMm == yMm;

  @override
  int get hashCode => Object.hash(xMm, yMm);

  @override
  String toString() => 'SsDrawPoint($xMm, $yMm)';
}

/// 벽 하나 — 끝점 두 개(a→b), 종류, 두께(mm).
@immutable
class SsDrawWall {
  const SsDrawWall({required this.id, required this.a, required this.b, this.type = SsDrawWallType.interior, this.thicknessMm = 120});

  final int id;
  final SsDrawPoint a;
  final SsDrawPoint b;
  final SsDrawWallType type;
  final double thicknessMm;

  double get lengthMm => a.distanceTo(b);

  SsDrawWall copyWith({SsDrawPoint? a, SsDrawPoint? b, SsDrawWallType? type, double? thicknessMm}) =>
      SsDrawWall(id: id, a: a ?? this.a, b: b ?? this.b, type: type ?? this.type, thicknessMm: thicknessMm ?? this.thicknessMm);

  /// 시작점(a)에서 [tMm]만큼 떨어진 벽 위의 점(개구부 배치용). 길이를 벗어나면 끝점으로 clamp한다.
  SsDrawPoint pointAt(double tMm) {
    final len = lengthMm;
    if (len <= 0) return a;
    final t = (tMm / len).clamp(0.0, 1.0);
    return SsDrawPoint(a.xMm + (b.xMm - a.xMm) * t, a.yMm + (b.yMm - a.yMm) * t);
  }

  /// 점 [p]를 벽 위로 투영했을 때 (시작점에서부터의 거리mm, 벽까지의 수직거리mm).
  (double alongMm, double distMm) project(SsDrawPoint p) {
    final len = lengthMm;
    if (len <= 0) return (0, p.distanceTo(a));
    final abx = b.xMm - a.xMm, aby = b.yMm - a.yMm;
    final t = (((p.xMm - a.xMm) * abx + (p.yMm - a.yMm) * aby) / (len * len)).clamp(0.0, 1.0);
    final projX = a.xMm + t * abx, projY = a.yMm + t * aby;
    return (t * len, p.distanceTo(SsDrawPoint(projX, projY)));
  }

  Map<String, Object?> toJson() => {'id': id, 'a': a.toJson(), 'b': b.toJson(), 'type': type.name, 'thicknessMm': thicknessMm};

  static SsDrawWall? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final a = SsDrawPoint.tryFromJson(j['a']);
    final b = SsDrawPoint.tryFromJson(j['b']);
    final type = SsDrawWallType.values.where((t) => t.name == j['type']).firstOrNull;
    final thickness = j['thicknessMm'];
    if (id is! int || a == null || b == null || type == null || thickness is! num) return null;
    return SsDrawWall(id: id, a: a, b: b, type: type, thicknessMm: thickness.toDouble());
  }
}

/// 개구부(문/창) 하나 — 어느 벽 위에, 시작점에서부터 거리(along), 폭(mm).
@immutable
class SsDrawOpening {
  const SsDrawOpening({required this.id, required this.wallId, required this.kind, required this.alongMm, this.widthMm = 900});

  final int id;
  final int wallId;
  final SsDrawOpeningKind kind;
  final double alongMm;
  final double widthMm;

  SsDrawOpening copyWith({double? alongMm, double? widthMm}) =>
      SsDrawOpening(id: id, wallId: wallId, kind: kind, alongMm: alongMm ?? this.alongMm, widthMm: widthMm ?? this.widthMm);

  Map<String, Object?> toJson() => {'id': id, 'wallId': wallId, 'kind': kind.name, 'alongMm': alongMm, 'widthMm': widthMm};

  static SsDrawOpening? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final wallId = j['wallId'];
    final kind = SsDrawOpeningKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final along = j['alongMm'];
    final width = j['widthMm'];
    if (id is! int || wallId is! int || kind == null || along is! num || width is! num) return null;
    return SsDrawOpening(id: id, wallId: wallId, kind: kind, alongMm: along.toDouble(), widthMm: width.toDouble());
  }
}

/// 직접 그리기 평면도 한 장 — 벽·개구부 목록 + 다음 id 채번.
@immutable
class SsDrawScene {
  const SsDrawScene({this.walls = const [], this.openings = const [], this.nextId = 1});

  static const SsDrawScene empty = SsDrawScene();

  final List<SsDrawWall> walls;
  final List<SsDrawOpening> openings;
  final int nextId;

  bool get isEmpty => walls.isEmpty;

  SsDrawWall? wall(int id) => walls.where((w) => w.id == id).firstOrNull;

  SsDrawOpening? opening(int id) => openings.where((o) => o.id == id).firstOrNull;

  SsDrawScene addWall(SsDrawPoint a, SsDrawPoint b, {SsDrawWallType type = SsDrawWallType.interior, double thicknessMm = 120}) {
    final w = SsDrawWall(id: nextId, a: a, b: b, type: type, thicknessMm: thicknessMm);
    return copyWith(walls: [...walls, w], nextId: nextId + 1);
  }

  SsDrawScene updateWall(int id, SsDrawWall Function(SsDrawWall wall) update) =>
      copyWith(walls: [for (final w in walls) if (w.id == id) update(w) else w]);

  SsDrawScene removeWall(int id) =>
      copyWith(walls: [for (final w in walls) if (w.id != id) w], openings: [for (final o in openings) if (o.wallId != id) o]);

  SsDrawScene addOpening(int wallId, SsDrawOpeningKind kind, double alongMm, {double? widthMm}) {
    final o = SsDrawOpening(
      id: nextId,
      wallId: wallId,
      kind: kind,
      alongMm: alongMm,
      widthMm: widthMm ?? (kind == SsDrawOpeningKind.door ? 900 : 1200),
    );
    return copyWith(openings: [...openings, o], nextId: nextId + 1);
  }

  SsDrawScene updateOpening(int id, SsDrawOpening Function(SsDrawOpening opening) update) =>
      copyWith(openings: [for (final o in openings) if (o.id == id) update(o) else o]);

  SsDrawScene removeOpening(int id) => copyWith(openings: [for (final o in openings) if (o.id != id) o]);

  SsDrawScene copyWith({List<SsDrawWall>? walls, List<SsDrawOpening>? openings, int? nextId}) =>
      SsDrawScene(walls: walls ?? this.walls, openings: openings ?? this.openings, nextId: nextId ?? this.nextId);

  Map<String, Object?> toJson() => {
    'walls': [for (final w in walls) w.toJson()],
    'openings': [for (final o in openings) o.toJson()],
    'nextId': nextId,
  };

  /// 저장된 JSON에서 — 깨졌거나 없으면 빈 평면도([empty]).
  static SsDrawScene tryFromJson(Object? j) {
    if (j is! Map) return empty;
    final walls = j['walls'];
    final openings = j['openings'];
    final nextId = j['nextId'];
    return SsDrawScene(
      walls: walls is List ? [for (final w in walls) ?SsDrawWall.tryFromJson(w)] : const [],
      openings: openings is List ? [for (final o in openings) ?SsDrawOpening.tryFromJson(o)] : const [],
      nextId: nextId is int ? nextId : 1,
    );
  }
}
