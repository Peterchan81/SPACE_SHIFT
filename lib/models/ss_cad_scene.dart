/// SS011 — MASTER UI 8(CAD 편집·치수·파일 내보내기) 편집 상태 하나.
///
/// [CadFloorPlan](벽/문/창/공간 — 기존 Canonical CAD 모델)에 "가구/주요 객체"
/// ([SsCadFurniture])를 더하고, 치수를 보존하는 [FloorPlanScale]을 함께 묶어
/// [SsHistory]의 상태(T) 하나로 Undo/Redo가 벽·가구 편집을 함께 되돌리게 한다
/// (ss_draw_editor_controller.dart의 SsDrawScene과 같은 생각).
library;

import 'package:flutter/foundation.dart';

import 'cad_floor_plan.dart';
import 'cad_floor_plan_json.dart';
import 'floor_plan_geometry.dart';

/// 가구/주요 객체의 최소 분류 — 3D 마감재처럼 세분화하지 않는다(이번 WO 범위는
/// "가구를 놓고 위치/크기/회전을 편집"까지).
enum SsCadFurnitureKind { sofa, bed, table, wardrobe, kitchen, bath, other }

extension SsCadFurnitureKindX on SsCadFurnitureKind {
  String get label => switch (this) {
    SsCadFurnitureKind.sofa => '소파',
    SsCadFurnitureKind.bed => '침대',
    SsCadFurnitureKind.table => '테이블',
    SsCadFurnitureKind.wardrobe => '수납장',
    SsCadFurnitureKind.kitchen => '주방가구',
    SsCadFurnitureKind.bath => '욕실가구',
    SsCadFurnitureKind.other => '가구',
  };
}

/// 평면도 위에 놓인 가구/주요 객체 하나 — 중심점 + 폭/깊이(정규화 좌표, [CadWall]과
/// 같은 좌표계) + 회전(도, 시계방향)만 다룬다.
@immutable
class SsCadFurniture {
  const SsCadFurniture({
    required this.id,
    required this.kind,
    required this.center,
    required this.widthNormalized,
    required this.depthNormalized,
    this.rotationDegrees = 0,
    this.label,
  });

  final String id;
  final SsCadFurnitureKind kind;
  final Point2 center;
  final double widthNormalized;
  final double depthNormalized;
  final double rotationDegrees;
  final String? label;

  SsCadFurniture copyWith({
    Point2? center,
    double? widthNormalized,
    double? depthNormalized,
    double? rotationDegrees,
    String? label,
  }) => SsCadFurniture(
    id: id,
    kind: kind,
    center: center ?? this.center,
    widthNormalized: widthNormalized ?? this.widthNormalized,
    depthNormalized: depthNormalized ?? this.depthNormalized,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    label: label ?? this.label,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'cx': center.x,
    'cy': center.y,
    'w': widthNormalized,
    'd': depthNormalized,
    'rotation': rotationDegrees,
    if (label != null) 'label': label,
  };

  static SsCadFurniture? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final cx = j['cx'];
    final cy = j['cy'];
    final w = j['w'];
    final d = j['d'];
    if (id is! String || cx is! num || cy is! num || w is! num || d is! num) return null;
    final kind = SsCadFurnitureKind.values.where((k) => k.name == j['kind']).firstOrNull ?? SsCadFurnitureKind.other;
    final rotation = j['rotation'];
    return SsCadFurniture(
      id: id,
      kind: kind,
      center: Point2(cx.toDouble(), cy.toDouble()),
      widthNormalized: w.toDouble(),
      depthNormalized: d.toDouble(),
      rotationDegrees: rotation is num ? rotation.toDouble() : 0,
      label: j['label'] is String ? j['label'] as String : null,
    );
  }
}

/// 편집 중인 CAD 도면 한 장 — [plan](벽/문/창/공간) + [scale](치수 보존, 없으면
/// 아직 실측 전) + [furniture]를 함께 묶는다.
@immutable
class SsCadScene {
  const SsCadScene({required this.plan, this.scale, this.furniture = const []});

  final CadFloorPlan plan;
  final FloorPlanScale? scale;
  final List<SsCadFurniture> furniture;

  SsCadScene copyWith({CadFloorPlan? plan, FloorPlanScale? scale, List<SsCadFurniture>? furniture}) => SsCadScene(
    plan: plan ?? this.plan,
    scale: scale ?? this.scale,
    furniture: furniture ?? this.furniture,
  );

  Map<String, Object?> toJson() => {
    'plan': cadFloorPlanToJson(plan),
    if (scale != null) 'scale': floorPlanScaleToJson(scale!),
    'furniture': [for (final f in furniture) f.toJson()],
  };

  static SsCadScene? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final plan = cadFloorPlanFromJson(j['plan']);
    if (plan == null) return null;
    final furnitureJson = j['furniture'];
    return SsCadScene(
      plan: plan,
      scale: floorPlanScaleFromJson(j['scale']),
      furniture: furnitureJson is List ? [for (final f in furnitureJson) ?SsCadFurniture.tryFromJson(f)] : const [],
    );
  }
}
