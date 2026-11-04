/// SS013 — MASTER UI 10(3D 아이소 작업) 전용 구조화 데이터. 벽/바닥/천장 색상 자체는 이미 있는
/// [CadWall.materialOverride]/[CadRoom.materialOverride]/[CadRoom.ceilingMaterialOverride]에
/// 저장한다(기존 3D 빌더([buildSpaceSceneV2])가 이미 그대로 반영한다 — 새 재질 파이프라인을 만들지
/// 않는다). 이 파일은 그 색이 어떤 이름의 마감재인지("페인트"/"타일" 등, 기존 모델에는 없는 라벨)와,
/// 기존 모델에 아직 자리가 없는 조명/설비 배치, 그리고 "3D에서 숨긴(삭제한) 객체"만 담는다.
library;

import 'package:flutter/foundation.dart';

/// 조명 종류 — MASTER UI 10 리본의 "조명" 그룹(다운라이트/간접조명/펜던트)과 같다.
enum SsIsoLightKind {
  downlight('다운라이트', 0xFFFFF3D6, 0.8),
  indirect('간접조명', 0xFFBFE3FF, 0.5),
  pendant('펜던트', 0xFFFFE2B8, 0.7);

  const SsIsoLightKind(this.label, this.defaultColorValue, this.defaultIntensity);
  final String label;
  final int defaultColorValue;
  final double defaultIntensity;
}

/// 설비 종류 — MASTER UI 10 리본의 "설비" 그룹(싱크/세면대)에 콘센트/기타를 더한다.
enum SsIsoEquipmentKind {
  sink('싱크', 0xFFB0B4B8),
  vanity('세면대', 0xFFF2F2F2),
  outlet('콘센트', 0xFFEDEDED),
  other('기타 설비', 0xFFC8CDD3);

  const SsIsoEquipmentKind(this.label, this.defaultColorValue);
  final String label;
  final int defaultColorValue;
}

/// 3D 공간에 놓인 조명 하나 — 위치는 world mm([pointToMm]과 같은 좌표계, Y=위).
@immutable
class SsIsoLight {
  const SsIsoLight({
    required this.id,
    required this.kind,
    required this.roomId,
    required this.xMm,
    required this.yMm,
    required this.zMm,
    this.label,
  });

  final String id;
  final SsIsoLightKind kind;
  final String roomId;
  final double xMm;
  final double yMm;
  final double zMm;
  final String? label;

  SsIsoLight copyWith({double? xMm, double? yMm, double? zMm}) =>
      SsIsoLight(id: id, kind: kind, roomId: roomId, xMm: xMm ?? this.xMm, yMm: yMm ?? this.yMm, zMm: zMm ?? this.zMm, label: label);

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'roomId': roomId,
    'x': xMm,
    'y': yMm,
    'z': zMm,
    if (label != null) 'label': label,
  };

  static SsIsoLight? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final roomId = j['roomId'];
    final x = j['x'];
    final y = j['y'];
    final z = j['z'];
    if (id is! String || roomId is! String || x is! num || y is! num || z is! num) return null;
    final kind = SsIsoLightKind.values.where((k) => k.name == j['kind']).firstOrNull ?? SsIsoLightKind.downlight;
    return SsIsoLight(id: id, kind: kind, roomId: roomId, xMm: x.toDouble(), yMm: y.toDouble(), zMm: z.toDouble(), label: j['label'] is String ? j['label'] as String : null);
  }
}

/// 3D 공간에 놓인 설비 하나(바닥 위, 높이는 렌더러가 임의 박스 높이로 고정).
@immutable
class SsIsoEquipment {
  const SsIsoEquipment({required this.id, required this.kind, required this.roomId, required this.xMm, required this.zMm, this.label});

  final String id;
  final SsIsoEquipmentKind kind;
  final String roomId;
  final double xMm;
  final double zMm;
  final String? label;

  SsIsoEquipment copyWith({double? xMm, double? zMm}) => SsIsoEquipment(id: id, kind: kind, roomId: roomId, xMm: xMm ?? this.xMm, zMm: zMm ?? this.zMm, label: label);

  Map<String, Object?> toJson() => {'id': id, 'kind': kind.name, 'roomId': roomId, 'x': xMm, 'z': zMm, if (label != null) 'label': label};

  static SsIsoEquipment? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final roomId = j['roomId'];
    final x = j['x'];
    final z = j['z'];
    if (id is! String || roomId is! String || x is! num || z is! num) return null;
    final kind = SsIsoEquipmentKind.values.where((k) => k.name == j['kind']).firstOrNull ?? SsIsoEquipmentKind.other;
    return SsIsoEquipment(id: id, kind: kind, roomId: roomId, xMm: x.toDouble(), zMm: z.toDouble(), label: j['label'] is String ? j['label'] as String : null);
  }
}

/// [SsIsoEditorState]가 [SsHistory]에 담는 값 중, 기존 [SsCadScene]에는 없는 나머지 전부.
@immutable
class SsIsoDesignExtras {
  const SsIsoDesignExtras({this.materialLabels = const {}, this.hiddenObjectIds = const {}, this.lights = const [], this.equipment = const []});

  static const SsIsoDesignExtras empty = SsIsoDesignExtras();

  /// 3D objectId(예: 'wall:wall-3', 'floor:room-1') → 사용자가 고른 마감재 이름. 실제 색은
  /// [CadWall.materialOverride] 등에 있다 — 이 맵은 표시용 라벨만 보존한다.
  final Map<String, String> materialLabels;

  /// 사용자가 3D에서 "삭제"한 객체의 3D objectId — 구조(벽 등)가 아니라, buildSpaceSceneV2가 자동
  /// 생성한 가구처럼 CAD 모델에 없는 객체를 지우는 유일한 방법이라 별도로 보존한다.
  final Set<String> hiddenObjectIds;

  final List<SsIsoLight> lights;
  final List<SsIsoEquipment> equipment;

  SsIsoDesignExtras copyWith({Map<String, String>? materialLabels, Set<String>? hiddenObjectIds, List<SsIsoLight>? lights, List<SsIsoEquipment>? equipment}) => SsIsoDesignExtras(
    materialLabels: materialLabels ?? this.materialLabels,
    hiddenObjectIds: hiddenObjectIds ?? this.hiddenObjectIds,
    lights: lights ?? this.lights,
    equipment: equipment ?? this.equipment,
  );

  Map<String, Object?> toJson() => {
    'materialLabels': materialLabels,
    'hiddenObjectIds': hiddenObjectIds.toList(),
    'lights': [for (final l in lights) l.toJson()],
    'equipment': [for (final e in equipment) e.toJson()],
  };

  static SsIsoDesignExtras tryFromJson(Object? j) {
    if (j is! Map) return empty;
    final labelsJson = j['materialLabels'];
    final labels = <String, String>{if (labelsJson is Map) for (final e in labelsJson.entries) '${e.key}': '${e.value}'};
    final hiddenJson = j['hiddenObjectIds'];
    final hidden = <String>{if (hiddenJson is List) for (final h in hiddenJson) '$h'};
    final lightsJson = j['lights'];
    final lights = <SsIsoLight>[if (lightsJson is List) for (final l in lightsJson) ?SsIsoLight.tryFromJson(l)];
    final equipJson = j['equipment'];
    final equipment = <SsIsoEquipment>[if (equipJson is List) for (final e in equipJson) ?SsIsoEquipment.tryFromJson(e)];
    return SsIsoDesignExtras(materialLabels: labels, hiddenObjectIds: hidden, lights: lights, equipment: equipment);
  }
}

/// MASTER UI 10 "마감재" 팔레트 — 벽/바닥/천장 공통으로 쓰는 8종 프리셋(이미지 순서 그대로:
/// 페인트/벽지/타일/목재/대리석/석재/콘크리트/패브릭). 색상 전용 선택기(색상환) 대신 MASTER UI가
/// 보여주는 실제 스와치를 그대로 쓴다.
class SsIsoMaterialPreset {
  const SsIsoMaterialPreset(this.label, this.colorValue);
  final String label;
  final int colorValue;
}

const List<SsIsoMaterialPreset> kSsIsoMaterialPresets = [
  SsIsoMaterialPreset('페인트', 0xFFF5F4F0),
  SsIsoMaterialPreset('벽지', 0xFFE8DCC8),
  SsIsoMaterialPreset('타일', 0xFFD9DADC),
  SsIsoMaterialPreset('목재', 0xFFC89B6E),
  SsIsoMaterialPreset('대리석', 0xFFEDEAE3),
  SsIsoMaterialPreset('석재', 0xFFB9B6AE),
  SsIsoMaterialPreset('콘크리트', 0xFF8C8C8C),
  SsIsoMaterialPreset('패브릭', 0xFFBFA98C),
];
