// SS006 — SsPhotoScene 모델 단위 테스트: 객체 추가/삭제 지시/재질/조명/개구부와 JSON 왕복.
import 'dart:typed_data';

import 'package:ason_space/models/ss_photo_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  test('addObject는 id를 증가시키고 visibleObjects에 보인다', () {
    final scene = SsPhotoScene(imageBytes: bytes).addObject(name: '소파', category: SsPhotoObjectCategory.furniture, x: 0.1, y: 0.1);
    expect(scene.objects.length, 1);
    expect(scene.visibleObjects.length, 1);
    expect(scene.objects.first.id, 1);
    expect(scene.nextId, 2);
  });

  test('updateObject로 removed를 켜면 visibleObjects에서 빠지고 removedObjects에 들어간다', () {
    var scene = SsPhotoScene(imageBytes: bytes).addObject(name: '소파', category: SsPhotoObjectCategory.furniture, x: 0, y: 0);
    scene = scene.updateObject(1, (o) => o.copyWith(removed: true));
    expect(scene.visibleObjects, isEmpty);
    expect(scene.removedObjects.single.name, '소파');
  });

  test('setFinish은 같은 면을 덮어쓴다', () {
    var scene = SsPhotoScene(imageBytes: bytes);
    scene = scene.setFinish(SsPhotoSurface.wall, swatchId: 'ivory', colorValue: 0xFFFFFFFF);
    scene = scene.setFinish(SsPhotoSurface.wall, swatchId: 'beige', colorValue: 0xFFE3C9A6);
    expect(scene.finishes.length, 1);
    expect(scene.finishes[SsPhotoSurface.wall]!.swatchId, 'beige');
  });

  test('addOpening/removeOpening', () {
    var scene = SsPhotoScene(imageBytes: bytes).addOpening(SsPhotoOpeningKind.window, x: 0.2, y: 0.2);
    expect(scene.openings.single.kind, SsPhotoOpeningKind.window);
    scene = scene.removeOpening(scene.openings.single.id);
    expect(scene.openings, isEmpty);
  });

  test('toEditJson/fromEditJson은 편집 내용을 그대로 복원한다(원본 바이트는 별도)', () {
    var scene = SsPhotoScene(imageBytes: bytes)
        .addObject(name: '소파', category: SsPhotoObjectCategory.furniture, x: 0.1, y: 0.1)
        .setFinish(SsPhotoSurface.floor, swatchId: 'walnut', colorValue: 0xFF8B5A2B)
        .setLighting(const SsPhotoLighting(presetId: 'warmCozy', label: '따뜻한 조명'))
        .addOpening(SsPhotoOpeningKind.door, x: 0.3, y: 0.3);

    final json = scene.toEditJson();
    final restored = SsPhotoScene.fromEditJson(bytes, json);

    expect(restored.imageBytes, same(bytes));
    expect(restored.objects.single.name, '소파');
    expect(restored.finishes[SsPhotoSurface.floor]!.swatchId, 'walnut');
    expect(restored.lighting!.presetId, 'warmCozy');
    expect(restored.openings.single.kind, SsPhotoOpeningKind.door);
    expect(restored.nextId, scene.nextId);
  });
}
