// SS006 — SsPhotoEditorController 단위 테스트: 선택/삭제(AI 배경 복원 지시)/복원/재생성 요청/이동/
// 가구 추가/재질/조명/개구부가 History(Undo/Redo)와 함께 동작하는지 확인한다.
import 'dart:typed_data';

import 'package:ason_space/core/ss_photo_editor_controller.dart';
import 'package:ason_space/models/ss_photo_scene.dart';
import 'package:flutter/material.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);

  SsPhotoEditorController makeController() {
    final scene = SsPhotoScene(
      imageBytes: bytes,
    ).addObject(name: '소파', category: SsPhotoObjectCategory.furniture, x: 0.1, y: 0.1, width: 0.3, height: 0.3);
    return SsPhotoEditorController(initialScene: scene);
  }

  test('selectAt은 객체 영역 안을 누르면 선택하고, 밖을 누르면 선택을 지운다', () {
    final c = makeController();
    c.selectAt(const Offset(0.2, 0.2));
    expect(c.selection.isEmpty, isFalse);
    expect(c.selection.objectId, '1');
    c.selectAt(const Offset(0.9, 0.9));
    expect(c.selection.isEmpty, isTrue);
  });

  test('deleteSelected은 객체를 숨기고 되돌릴 수 있다(Undo)', () {
    final c = makeController();
    c.selectAt(const Offset(0.2, 0.2));
    c.deleteSelected();
    expect(c.scene.visibleObjects, isEmpty);
    expect(c.scene.removedObjects.single.aiRestoreBackground, isTrue);
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.scene.visibleObjects.length, 1);
  });

  test('restoreObjectById은 삭제한 객체를 되살린다', () {
    final c = makeController();
    c.selectAt(const Offset(0.2, 0.2));
    c.deleteSelected();
    c.restoreObjectById(1);
    expect(c.scene.visibleObjects.length, 1);
  });

  test('restoreSelected은 선택 없이도 가장 최근 삭제를 되살린다', () {
    final c = makeController();
    c.selectAt(const Offset(0.2, 0.2));
    c.deleteSelected();
    c.restoreSelected();
    expect(c.scene.visibleObjects.length, 1);
  });

  test('드래그(beginDrag/updateDrag/endDrag)로 객체를 옮기고 History에 쌓인다', () {
    final c = makeController();
    c.selectAt(const Offset(0.2, 0.2));
    c.beginDrag();
    c.updateDrag(0.1, 0.1);
    expect(c.isDragging, isTrue);
    c.endDrag();
    expect(c.isDragging, isFalse);
    final moved = c.scene.object(1)!;
    expect(moved.x, closeTo(0.2, 0.0001));
    expect(moved.y, closeTo(0.2, 0.0001));
    expect(c.canUndo, isTrue);
  });

  test('addFurnitureAt/setFinish/setLighting/addOpeningAt/removeOpening이 History에 쌓인다', () {
    final c = makeController();
    final before = c.history.steps.length;
    c.addFurnitureAt(const Offset(0.5, 0.5), name: '러그');
    c.setFinish(SsPhotoSurface.wall, swatchId: 'ivory', colorValue: 0xFFFFFFFF);
    c.setLighting(const SsPhotoLighting(presetId: 'dim', label: '은은한 조명'));
    c.addOpeningAt(SsPhotoOpeningKind.window, const Offset(0.6, 0.2));
    expect(c.history.steps.length, before + 4);
    expect(c.scene.finishes[SsPhotoSurface.wall]!.swatchId, 'ivory');
    expect(c.scene.lighting!.presetId, 'dim');
    expect(c.scene.openings.length, 1);
    final openingId = c.scene.openings.single.id;
    c.removeOpening(openingId);
    expect(c.scene.openings, isEmpty);
  });

  test('requestRegenerate는 선택한 객체에 재생성 대기 표시를 남긴다', () {
    final c = makeController();
    c.selectAt(const Offset(0.2, 0.2));
    c.requestRegenerate();
    expect(c.scene.object(1)!.pendingRegenerate, isTrue);
  });

  test('replaceSelectedFurniture는 위치는 유지한 채 이름을 바꾼다', () {
    final c = makeController();
    c.selectAt(const Offset(0.2, 0.2));
    c.replaceSelectedFurniture('암체어');
    final obj = c.scene.object(1)!;
    expect(obj.name, '암체어');
    expect(obj.x, closeTo(0.1, 0.0001));
  });

  test('toggleBeforeAfter는 showOriginal을 뒤집는다', () {
    final c = makeController();
    expect(c.showOriginal, isFalse);
    c.toggleBeforeAfter();
    expect(c.showOriginal, isTrue);
  });
}
