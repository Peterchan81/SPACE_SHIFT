// SS005 — 편집 컨트롤러 단위 테스트: Grid/Snap, 벽 그리기, 선택/이동/삭제/수정, Undo/Redo.
import 'package:ason_space/core/ss_draw_editor_controller.dart';
import 'package:ason_space/models/ss_draw_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('벽 그리기 + 100mm 기본 Grid Snap', () {
    test('드래그 시작~끝이 100mm 격자에 맞춰 벽이 된다', () {
      final c = SsDrawEditorController();
      expect(c.gridMm, 100);
      c.beginWallDraft(const SsDrawPoint(42, 7));
      c.updateWallDraft(const SsDrawPoint(1005, 3));
      c.commitWallDraft();
      expect(c.scene.walls, hasLength(1));
      final w = c.scene.walls.single;
      expect(w.a, const SsDrawPoint(0, 0));
      expect(w.b, const SsDrawPoint(1000, 0));
    });

    test('너무 짧은 드래그는 벽이 되지 않는다', () {
      final c = SsDrawEditorController();
      c.beginWallDraft(const SsDrawPoint(0, 0));
      c.updateWallDraft(const SsDrawPoint(10, 0));
      c.commitWallDraft();
      expect(c.scene.walls, isEmpty);
    });

    test('Snap을 끄면 격자에 맞추지 않는다', () {
      final c = SsDrawEditorController()..setSnapEnabled(false);
      c.beginWallDraft(const SsDrawPoint(42, 7));
      c.updateWallDraft(const SsDrawPoint(1005, 3));
      c.commitWallDraft();
      final w = c.scene.walls.single;
      expect(w.a, const SsDrawPoint(42, 7));
      expect(w.b, const SsDrawPoint(1005, 3));
    });
  });

  group('선택 / 이동 / 삭제 / 수정', () {
    late SsDrawEditorController c;
    setUp(() {
      c = SsDrawEditorController();
      c.beginWallDraft(const SsDrawPoint(0, 0));
      c.updateWallDraft(const SsDrawPoint(1000, 0));
      c.commitWallDraft();
    });

    test('벽을 탭하면 선택되고 두께 수정이 반영된다', () {
      c.selectAt(const SsDrawPoint(500, 2));
      expect(c.selection.objectType, '벽');
      final id = int.parse(c.selection.objectId);
      c.setWallThicknessMm(id, 200);
      expect(c.scene.wall(id)!.thicknessMm, 200);
    });

    test('드래그로 벽을 이동하면 두 끝점이 함께 옮겨진다', () {
      c.selectAt(const SsDrawPoint(500, 0));
      c.beginDrag();
      c.updateDrag(0, 300);
      final id = int.parse(c.selection.objectId);
      expect(c.scene.wall(id)!.a.yMm, 300);
      c.endDrag();
      expect(c.scene.wall(id)!.a.yMm, 300, reason: '드래그가 끝나면 History에 커밋된다');
      expect(c.canUndo, isTrue);
    });

    test('문을 벽 위에 놓고 선택해서 폭을 수정·삭제할 수 있다', () {
      final ok = c.addOpeningAt(SsDrawOpeningKind.door, const SsDrawPoint(500, 0));
      expect(ok, isTrue);
      expect(c.scene.openings, hasLength(1));
      c.selectAt(const SsDrawPoint(500, 0));
      expect(c.selection.objectType, '문');
      final id = int.parse(c.selection.objectId);
      c.setOpeningWidthMm(id, 1000);
      expect(c.scene.opening(id)!.widthMm, 1000);
      c.deleteSelected();
      expect(c.scene.openings, isEmpty);
    });

    test('벽을 삭제 도구로 지우면 사라진다', () {
      c.selectAt(const SsDrawPoint(500, 0));
      c.deleteSelected();
      expect(c.scene.walls, isEmpty);
    });
  });

  group('Undo/Redo/History(§7) 연결', () {
    test('되돌리기·다시하기가 SsHistory 기반으로 동작한다', () {
      final c = SsDrawEditorController();
      c.beginWallDraft(const SsDrawPoint(0, 0));
      c.updateWallDraft(const SsDrawPoint(1000, 0));
      c.commitWallDraft();
      expect(c.scene.walls, hasLength(1));
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.scene.walls, isEmpty);
      expect(c.canRedo, isTrue);
      c.redo();
      expect(c.scene.walls, hasLength(1));
    });
  });
}
