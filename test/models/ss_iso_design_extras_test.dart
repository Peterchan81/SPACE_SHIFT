import 'package:ason_space/models/ss_iso_design_extras.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SsIsoLight/SsIsoEquipment JSON', () {
    test('조명은 JSON 왕복 후 값이 그대로다', () {
      const light = SsIsoLight(id: 'l1', kind: SsIsoLightKind.pendant, roomId: 'room-1', xMm: 100, yMm: 2200, zMm: 300, label: '거실 펜던트');
      final restored = SsIsoLight.tryFromJson(light.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, 'l1');
      expect(restored.kind, SsIsoLightKind.pendant);
      expect(restored.roomId, 'room-1');
      expect(restored.xMm, 100);
      expect(restored.yMm, 2200);
      expect(restored.zMm, 300);
      expect(restored.label, '거실 펜던트');
    });

    test('설비는 JSON 왕복 후 값이 그대로다', () {
      const equipment = SsIsoEquipment(id: 'e1', kind: SsIsoEquipmentKind.sink, roomId: 'room-2', xMm: 50, zMm: 80);
      final restored = SsIsoEquipment.tryFromJson(equipment.toJson());
      expect(restored, isNotNull);
      expect(restored!.kind, SsIsoEquipmentKind.sink);
      expect(restored.roomId, 'room-2');
    });

    test('잘못된 JSON이면 null(지어내지 않는다)', () {
      expect(SsIsoLight.tryFromJson({'id': 'l1'}), isNull);
      expect(SsIsoEquipment.tryFromJson('not a map'), isNull);
    });
  });

  group('SsIsoDesignExtras', () {
    test('빈 값은 JSON 왕복 후에도 비어 있다', () {
      final restored = SsIsoDesignExtras.tryFromJson(SsIsoDesignExtras.empty.toJson());
      expect(restored.materialLabels, isEmpty);
      expect(restored.hiddenObjectIds, isEmpty);
      expect(restored.lights, isEmpty);
      expect(restored.equipment, isEmpty);
    });

    test('마감재 라벨/숨긴 객체/조명/설비가 모두 JSON 왕복된다', () {
      const extras = SsIsoDesignExtras(
        materialLabels: {'wall:w1': '페인트'},
        hiddenObjectIds: {'furniture:room-1:0'},
        lights: [SsIsoLight(id: 'l1', kind: SsIsoLightKind.downlight, roomId: 'r1', xMm: 0, yMm: 0, zMm: 0)],
        equipment: [SsIsoEquipment(id: 'e1', kind: SsIsoEquipmentKind.vanity, roomId: 'r1', xMm: 0, zMm: 0)],
      );
      final restored = SsIsoDesignExtras.tryFromJson(extras.toJson());
      expect(restored.materialLabels['wall:w1'], '페인트');
      expect(restored.hiddenObjectIds.contains('furniture:room-1:0'), isTrue);
      expect(restored.lights.single.kind, SsIsoLightKind.downlight);
      expect(restored.equipment.single.kind, SsIsoEquipmentKind.vanity);
    });

    test('잘못된 JSON이면 빈 값으로 안전하게 대체된다', () {
      final restored = SsIsoDesignExtras.tryFromJson('broken');
      expect(restored.materialLabels, isEmpty);
    });

    test('마감재 프리셋은 8종이고 라벨이 중복되지 않는다', () {
      expect(kSsIsoMaterialPresets.length, 8);
      expect(kSsIsoMaterialPresets.map((p) => p.label).toSet().length, 8);
    });
  });
}
