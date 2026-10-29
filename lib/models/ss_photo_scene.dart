/// SS006 — MASTER UI 4-2(실제 공간 이미지 AI 디자인 에디터). 사진 위에서 다루는 편집 지시 데이터 하나.
///
/// 실제 AI 이미지 재생성(픽셀 변경 — 배경 복원, 재질 적용 결과 등)은 SS007(이미지 AI 렌더링)이 맡는다.
/// 이 모델(SS006)은 "무엇을 어떻게 바꿀지"를 정하는 편집 지시(객체 삭제/추가/이동, 재질·색상, 조명,
/// 개구부)를 담고, [SsHistory]로 Undo/Redo/History를 관리할 수 있게 불변 값으로 다룬다. 원본
/// 사진([imageBytes])은 어떤 편집을 해도 바뀌지 않는다(§5 원본 보존 — SsProject.withSource,
/// SsDrawScene과 같은 원칙). 좌표는 사진 크기에 무관한 정규화 값(0.0~1.0) — [RegionSelection]과 같다.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

/// 사진 위 객체(가구 등)의 분류.
enum SsPhotoObjectCategory {
  furniture('가구'),
  lighting('조명'),
  decor('소품'),
  structure('구조물'),
  other('기타');

  const SsPhotoObjectCategory(this.label);
  final String label;
}

/// 사진 위에서 다루는 객체 하나(인식된 기존 가구이거나 사용자가 새로 추가한 가구).
@immutable
class SsPhotoObject {
  const SsPhotoObject({
    required this.id,
    required this.name,
    required this.category,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.removed = false,
    this.aiRestoreBackground = true,
    this.pendingRegenerate = false,
  });

  final int id;
  final String name;
  final SsPhotoObjectCategory category;

  // 정규화(0.0~1.0) 좌표/크기 — 화면 크기와 무관.
  final double x;
  final double y;
  final double width;
  final double height;

  /// 사용자가 삭제를 지시했는가(원본 픽셀은 그대로 — 실제 제거는 SS007이 한다).
  final bool removed;

  /// 삭제한 자리의 벽/바닥/배경을 AI로 자연스럽게 복원할지(MASTER UI 기본값: 켜짐).
  final bool aiRestoreBackground;

  /// "AI가 잘못 수정했다"고 사용자가 표시해 다시 생성해 주길 기다리는 상태(§ 영역 재선택·재생성).
  final bool pendingRegenerate;

  SsPhotoObject copyWith({
    String? name,
    SsPhotoObjectCategory? category,
    double? x,
    double? y,
    double? width,
    double? height,
    bool? removed,
    bool? aiRestoreBackground,
    bool? pendingRegenerate,
  }) => SsPhotoObject(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    removed: removed ?? this.removed,
    aiRestoreBackground: aiRestoreBackground ?? this.aiRestoreBackground,
    pendingRegenerate: pendingRegenerate ?? this.pendingRegenerate,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'removed': removed,
    'aiRestoreBackground': aiRestoreBackground,
    'pendingRegenerate': pendingRegenerate,
  };

  static SsPhotoObject? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final name = j['name'];
    final category = SsPhotoObjectCategory.values.where((c) => c.name == j['category']).firstOrNull;
    final x = j['x'];
    final y = j['y'];
    final w = j['width'];
    final h = j['height'];
    if (id is! int || name is! String || category == null || x is! num || y is! num || w is! num || h is! num) return null;
    return SsPhotoObject(
      id: id,
      name: name,
      category: category,
      x: x.toDouble(),
      y: y.toDouble(),
      width: w.toDouble(),
      height: h.toDouble(),
      removed: j['removed'] == true,
      aiRestoreBackground: j['aiRestoreBackground'] != false,
      pendingRegenerate: j['pendingRegenerate'] == true,
    );
  }
}

/// 마감(재질/색상)을 바꿀 수 있는 면.
enum SsPhotoSurface {
  wall('벽체'),
  floor('바닥'),
  ceiling('천장'),
  molding('몰딩'),
  other('기타');

  const SsPhotoSurface(this.label);
  final String label;
}

/// 면 하나의 재질/색상 지정(MASTER UI "공간 재질/색상" 스와치 선택 결과).
@immutable
class SsPhotoFinish {
  const SsPhotoFinish({required this.surface, required this.swatchId, required this.colorValue});

  final SsPhotoSurface surface;
  final String swatchId;
  final int colorValue;

  Map<String, Object?> toJson() => {'surface': surface.name, 'swatchId': swatchId, 'colorValue': colorValue};

  static SsPhotoFinish? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final surface = SsPhotoSurface.values.where((s) => s.name == j['surface']).firstOrNull;
    final swatchId = j['swatchId'];
    final colorValue = j['colorValue'];
    if (surface == null || swatchId is! String || colorValue is! int) return null;
    return SsPhotoFinish(surface: surface, swatchId: swatchId, colorValue: colorValue);
  }
}

/// 조명 지정 하나.
@immutable
class SsPhotoLighting {
  const SsPhotoLighting({required this.presetId, required this.label, this.warmth = 0.5, this.brightness = 0.5});

  final String presetId;
  final String label;
  final double warmth;
  final double brightness;

  Map<String, Object?> toJson() => {'presetId': presetId, 'label': label, 'warmth': warmth, 'brightness': brightness};

  static SsPhotoLighting? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final presetId = j['presetId'];
    final label = j['label'];
    if (presetId is! String || label is! String) return null;
    final warmth = j['warmth'];
    final brightness = j['brightness'];
    return SsPhotoLighting(
      presetId: presetId,
      label: label,
      warmth: warmth is num ? warmth.toDouble() : 0.5,
      brightness: brightness is num ? brightness.toDouble() : 0.5,
    );
  }
}

/// 벽체 개구부(창/문/구멍) 추가 지시 종류.
enum SsPhotoOpeningKind {
  window('창'),
  door('문'),
  hole('구멍');

  const SsPhotoOpeningKind(this.label);
  final String label;
}

/// 사진 기반 벽체 개구부 지시 하나 — 정규화 좌표 사각 영역.
@immutable
class SsPhotoOpening {
  const SsPhotoOpening({required this.id, required this.kind, required this.x, required this.y, required this.width, required this.height});

  final int id;
  final SsPhotoOpeningKind kind;
  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() => {'id': id, 'kind': kind.name, 'x': x, 'y': y, 'width': width, 'height': height};

  static SsPhotoOpening? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = SsPhotoOpeningKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final x = j['x'];
    final y = j['y'];
    final w = j['width'];
    final h = j['height'];
    if (id is! int || kind == null || x is! num || y is! num || w is! num || h is! num) return null;
    return SsPhotoOpening(id: id, kind: kind, x: x.toDouble(), y: y.toDouble(), width: w.toDouble(), height: h.toDouble());
  }
}

/// 사진 디자인 편집 한 장 — 원본 사진 + 그 위에 쌓인 편집 지시 전체.
@immutable
class SsPhotoScene {
  const SsPhotoScene({
    required this.imageBytes,
    this.objects = const [],
    this.finishes = const {},
    this.lighting,
    this.openings = const [],
    this.nextId = 1,
  });

  /// 원본 사진 바이트 — 어떤 편집을 해도 이 값 자체는 바뀌지 않는다(§5 원본 보존).
  final Uint8List imageBytes;
  final List<SsPhotoObject> objects;
  final Map<SsPhotoSurface, SsPhotoFinish> finishes;
  final SsPhotoLighting? lighting;
  final List<SsPhotoOpening> openings;
  final int nextId;

  /// 지금 화면에서 고를 수 있는(삭제 지시가 없는) 객체.
  List<SsPhotoObject> get visibleObjects => objects.where((o) => !o.removed).toList();

  /// 삭제 지시가 걸린 객체(복원 목록에 보여준다).
  List<SsPhotoObject> get removedObjects => objects.where((o) => o.removed).toList();

  SsPhotoObject? object(int id) => objects.where((o) => o.id == id).firstOrNull;
  SsPhotoOpening? opening(int id) => openings.where((o) => o.id == id).firstOrNull;

  SsPhotoScene addObject({
    required String name,
    required SsPhotoObjectCategory category,
    required double x,
    required double y,
    double width = 0.18,
    double height = 0.18,
  }) {
    final o = SsPhotoObject(id: nextId, name: name, category: category, x: x, y: y, width: width, height: height);
    return copyWith(objects: [...objects, o], nextId: nextId + 1);
  }

  SsPhotoScene updateObject(int id, SsPhotoObject Function(SsPhotoObject object) update) =>
      copyWith(objects: [for (final o in objects) if (o.id == id) update(o) else o]);

  /// 영구 삭제(히스토리에서 더 이상 필요 없을 때). 보통은 [updateObject]로 removed만 켠다.
  SsPhotoScene removeObjectPermanently(int id) => copyWith(objects: [for (final o in objects) if (o.id != id) o]);

  SsPhotoScene setFinish(SsPhotoSurface surface, {required String swatchId, required int colorValue}) =>
      copyWith(finishes: {...finishes, surface: SsPhotoFinish(surface: surface, swatchId: swatchId, colorValue: colorValue)});

  SsPhotoScene setLighting(SsPhotoLighting lighting) => copyWith(lighting: lighting);

  SsPhotoScene addOpening(SsPhotoOpeningKind kind, {required double x, required double y, double width = 0.12, double height = 0.16}) {
    final o = SsPhotoOpening(id: nextId, kind: kind, x: x, y: y, width: width, height: height);
    return copyWith(openings: [...openings, o], nextId: nextId + 1);
  }

  SsPhotoScene removeOpening(int id) => copyWith(openings: [for (final o in openings) if (o.id != id) o]);

  SsPhotoScene copyWith({
    List<SsPhotoObject>? objects,
    Map<SsPhotoSurface, SsPhotoFinish>? finishes,
    SsPhotoLighting? lighting,
    List<SsPhotoOpening>? openings,
    int? nextId,
  }) => SsPhotoScene(
    imageBytes: imageBytes,
    objects: objects ?? this.objects,
    finishes: finishes ?? this.finishes,
    lighting: lighting ?? this.lighting,
    openings: openings ?? this.openings,
    nextId: nextId ?? this.nextId,
  );

  /// 편집 지시만 담은 JSON(원본 사진 바이트는 빼고 SsProject.sourceData에 별도 저장한다).
  Map<String, Object?> toEditJson() => {
    'objects': [for (final o in objects) o.toJson()],
    'finishes': [for (final f in finishes.values) f.toJson()],
    'lighting': lighting?.toJson(),
    'openings': [for (final o in openings) o.toJson()],
    'nextId': nextId,
  };

  /// [imageBytes]는 원본 사진에서 그대로 가져오고, 편집 지시만 저장된 JSON에서 복원한다.
  static SsPhotoScene fromEditJson(Uint8List imageBytes, Object? j) {
    if (j is! Map) return SsPhotoScene(imageBytes: imageBytes);
    final objs = j['objects'];
    final fins = j['finishes'];
    final opens = j['openings'];
    final finishes = <SsPhotoSurface, SsPhotoFinish>{};
    if (fins is List) {
      for (final f in fins) {
        final parsed = SsPhotoFinish.tryFromJson(f);
        if (parsed != null) finishes[parsed.surface] = parsed;
      }
    }
    final nextId = j['nextId'];
    return SsPhotoScene(
      imageBytes: imageBytes,
      objects: objs is List ? [for (final o in objs) ?SsPhotoObject.tryFromJson(o)] : const [],
      finishes: finishes,
      lighting: SsPhotoLighting.tryFromJson(j['lighting']),
      openings: opens is List ? [for (final o in opens) ?SsPhotoOpening.tryFromJson(o)] : const [],
      nextId: nextId is int ? nextId : 1,
    );
  }
}
