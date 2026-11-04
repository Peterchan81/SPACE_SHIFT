/// SS013 — MASTER UI 10(3D ISO 전문 디자인 에디터) 편집 상태 하나.
///
/// 구조(벽/문/창)와 재질(벽/바닥/천장)은 새 모델을 만들지 않고 기존 [CadFloorPlan]/
/// [CadWall.materialOverride]/[CadRoom.materialOverride]/[CadRoom.ceilingMaterialOverride]를
/// 그대로 재사용한다(space_scene_builder_v2가 이미 이 값을 3D에 반영한다 — SS013은 UI에서
/// 고치기만 한다). 이 WO가 새로 더하는 것은 CAD에는 없던 3D 전용 객체 셋뿐이다 — 가구/조명/설비.
/// 전부 world mm 좌표(SpaceSceneV2와 같은 단위·축: X/Z=바닥 평면, Y=높이)로 저장한다.
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show Color;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'cad_floor_plan.dart';
import 'cad_floor_plan_json.dart';
import 'ss_cad_scene.dart' show SsCadFurnitureKind;
import 'ss_iso_camera_state.dart';

enum SsIsoLightKind { downlight, indirect, pendant }

extension SsIsoLightKindX on SsIsoLightKind {
  String get label => switch (this) {
    SsIsoLightKind.downlight => '다운라이트',
    SsIsoLightKind.indirect => '간접조명',
    SsIsoLightKind.pendant => '펜던트',
  };
  Color get color => switch (this) {
    SsIsoLightKind.downlight => const Color(0xFFFFE7A8),
    SsIsoLightKind.indirect => const Color(0xFFFFD98A),
    SsIsoLightKind.pendant => const Color(0xFFFFF1C2),
  };
}

enum SsIsoEquipmentKind { sink, vanity }

extension SsIsoEquipmentKindX on SsIsoEquipmentKind {
  String get label => switch (this) {
    SsIsoEquipmentKind.sink => '싱크',
    SsIsoEquipmentKind.vanity => '세면대',
  };
  Color get color => switch (this) {
    SsIsoEquipmentKind.sink => const Color(0xFFCBD5DC),
    SsIsoEquipmentKind.vanity => const Color(0xFFE3E7EA),
  };
}

@immutable
class SsIsoFurniture {
  const SsIsoFurniture({
    required this.id,
    required this.kind,
    required this.positionMm,
    this.widthMm = 800,
    this.depthMm = 400,
    this.heightMm = 450,
    this.rotationRadians = 0,
    this.color = const Color(0xFF8C6B52),
  });

  final String id;
  final SsCadFurnitureKind kind;
  final Vector3 positionMm;
  final double widthMm;
  final double depthMm;
  final double heightMm;
  final double rotationRadians;
  final Color color;

  SsIsoFurniture copyWith({Vector3? positionMm, double? rotationRadians}) => SsIsoFurniture(
    id: id,
    kind: kind,
    positionMm: positionMm ?? this.positionMm,
    widthMm: widthMm,
    depthMm: depthMm,
    heightMm: heightMm,
    rotationRadians: rotationRadians ?? this.rotationRadians,
    color: color,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'x': positionMm.x, 'y': positionMm.y, 'z': positionMm.z,
    'w': widthMm, 'd': depthMm, 'h': heightMm,
    'rotation': rotationRadians,
    'color': ((color.a * 255).round() & 0xFF) << 24 | ((color.r * 255).round() & 0xFF) << 16 | ((color.g * 255).round() & 0xFF) << 8 | ((color.b * 255).round() & 0xFF),
  };

  static SsIsoFurniture? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final x = j['x'], y = j['y'], z = j['z'];
    if (id is! String || x is! num || y is! num || z is! num) return null;
    final kind = SsCadFurnitureKind.values.where((k) => k.name == j['kind']).firstOrNull ?? SsCadFurnitureKind.other;
    final w = j['w'], d = j['d'], h = j['h'], rot = j['rotation'], colorValue = j['color'];
    return SsIsoFurniture(
      id: id,
      kind: kind,
      positionMm: Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
      widthMm: w is num ? w.toDouble() : 800,
      depthMm: d is num ? d.toDouble() : 400,
      heightMm: h is num ? h.toDouble() : 450,
      rotationRadians: rot is num ? rot.toDouble() : 0,
      color: colorValue is int ? Color(colorValue) : const Color(0xFF8C6B52),
    );
  }
}

@immutable
class SsIsoLight {
  const SsIsoLight({required this.id, required this.kind, required this.positionMm});
  final String id;
  final SsIsoLightKind kind;
  final Vector3 positionMm;

  SsIsoLight copyWith({Vector3? positionMm}) => SsIsoLight(id: id, kind: kind, positionMm: positionMm ?? this.positionMm);

  Map<String, Object?> toJson() => {'id': id, 'kind': kind.name, 'x': positionMm.x, 'y': positionMm.y, 'z': positionMm.z};

  static SsIsoLight? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = SsIsoLightKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final x = j['x'], y = j['y'], z = j['z'];
    if (id is! String || kind == null || x is! num || y is! num || z is! num) return null;
    return SsIsoLight(id: id, kind: kind, positionMm: Vector3(x.toDouble(), y.toDouble(), z.toDouble()));
  }
}

@immutable
class SsIsoEquipment {
  const SsIsoEquipment({required this.id, required this.kind, required this.positionMm, this.widthMm = 600, this.depthMm = 500, this.heightMm = 850});
  final String id;
  final SsIsoEquipmentKind kind;
  final Vector3 positionMm;
  final double widthMm;
  final double depthMm;
  final double heightMm;

  SsIsoEquipment copyWith({Vector3? positionMm}) => SsIsoEquipment(id: id, kind: kind, positionMm: positionMm ?? this.positionMm, widthMm: widthMm, depthMm: depthMm, heightMm: heightMm);

  Map<String, Object?> toJson() => {'id': id, 'kind': kind.name, 'x': positionMm.x, 'y': positionMm.y, 'z': positionMm.z, 'w': widthMm, 'd': depthMm, 'h': heightMm};

  static SsIsoEquipment? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = SsIsoEquipmentKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final x = j['x'], y = j['y'], z = j['z'];
    if (id is! String || kind == null || x is! num || y is! num || z is! num) return null;
    final w = j['w'], d = j['d'], h = j['h'];
    return SsIsoEquipment(
      id: id, kind: kind,
      positionMm: Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
      widthMm: w is num ? w.toDouble() : 600,
      depthMm: d is num ? d.toDouble() : 500,
      heightMm: h is num ? h.toDouble() : 850,
    );
  }
}

class SsIsoFinishSwatch {
  const SsIsoFinishSwatch(this.id, this.label, this.color);
  final String id;
  final String label;
  final Color color;
}

const List<SsIsoFinishSwatch> ssIsoFinishSwatches = [
  SsIsoFinishSwatch('paint', '페인트', Color(0xFFF5F4F0)),
  SsIsoFinishSwatch('wallpaper', '벽지', Color(0xFFEFE6D8)),
  SsIsoFinishSwatch('tile', '타일', Color(0xFFD8E2E4)),
  SsIsoFinishSwatch('wood', '목재', Color(0xFFC7A06C)),
  SsIsoFinishSwatch('marble', '대리석', Color(0xFFE8E4DC)),
  SsIsoFinishSwatch('stone', '석재', Color(0xFFBFB8AC)),
  SsIsoFinishSwatch('concrete', '콘크리트', Color(0xFFA9A9A4)),
  SsIsoFinishSwatch('fabric', '패브릭', Color(0xFF9C8C7A)),
];

@immutable
class SsIsoScene {
  const SsIsoScene({
    required this.plan,
    this.scale,
    this.furniture = const [],
    this.lights = const [],
    this.equipment = const [],
    this.camera,
  });

  final CadFloorPlan plan;
  final FloorPlanScale? scale;
  final List<SsIsoFurniture> furniture;
  final List<SsIsoLight> lights;
  final List<SsIsoEquipment> equipment;
  final SsIsoCameraState? camera;

  SsIsoScene copyWith({
    CadFloorPlan? plan,
    FloorPlanScale? scale,
    List<SsIsoFurniture>? furniture,
    List<SsIsoLight>? lights,
    List<SsIsoEquipment>? equipment,
    SsIsoCameraState? camera,
  }) => SsIsoScene(
    plan: plan ?? this.plan,
    scale: scale ?? this.scale,
    furniture: furniture ?? this.furniture,
    lights: lights ?? this.lights,
    equipment: equipment ?? this.equipment,
    camera: camera ?? this.camera,
  );

  Map<String, Object?> toJson() => {
    'plan': cadFloorPlanToJson(plan),
    if (scale != null) 'scale': floorPlanScaleToJson(scale!),
    'furniture': [for (final f in furniture) f.toJson()],
    'lights': [for (final l in lights) l.toJson()],
    'equipment': [for (final e in equipment) e.toJson()],
    if (camera != null) 'camera': camera!.toJson(),
  };

  static SsIsoScene? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final plan = cadFloorPlanFromJson(j['plan']);
    if (plan == null) return null;
    final furnitureJson = j['furniture'];
    final lightsJson = j['lights'];
    final equipmentJson = j['equipment'];
    return SsIsoScene(
      plan: plan,
      scale: floorPlanScaleFromJson(j['scale']),
      furniture: furnitureJson is List ? [for (final f in furnitureJson) ?SsIsoFurniture.tryFromJson(f)] : const [],
      lights: lightsJson is List ? [for (final l in lightsJson) ?SsIsoLight.tryFromJson(l)] : const [],
      equipment: equipmentJson is List ? [for (final e in equipmentJson) ?SsIsoEquipment.tryFromJson(e)] : const [],
      camera: SsIsoCameraState.tryFromJson(j['camera']),
    );
  }
}
