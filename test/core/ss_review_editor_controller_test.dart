// SS009 — 평면도 확인·보정 도구 컨트롤러([SsReviewEditorController]) 단위 테스트.
//
// 1. 펜 드래그 한 번이 Undo 한 단위가 된다.
// 2. 선택 도구로 벽을 선택해 삭제할 수 있다(잘못된 구조요소 삭제).
// 3. 문을 선택해 창으로 바꿀 수 있다(객체 의미 수정).
// 4. 벽 추가 — 두 번 눌러 벽 하나를 만든다.
// 5. 문/창 추가 — 한 번 눌러 바로 추가된다(누락 요소 추가).
// 6. 지우개로 지운 선도 Undo로 복원된다.
import 'package:ason_space/core/ss_review_editor_controller.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _model = SSSpatialModel(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  spaces: [],
  walls: [SSWall(id: 'wall-1', start: Point2(0.1, 0.1), end: Point2(0.9, 0.1), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9)],
  openings: [SSOpening(id: 'door-1', kind: SSOpeningKind.door, center: Point2(0.5, 0.1), widthNormalized: 0.05, confidence: 0.8)],
  objects: [],
  warnings: [],
);

void main() {
  group('SsReviewEditorController', () {
    test('펜으로 그리면 한 번의 드래그가 하나의 Undo 단위가 된다', () {
      final c = SsReviewEditorController(baseModel: _model);
      c.setTool(SsReviewTool.pen);
      c.pointerDown(const Point2(0.1, 0.1));
      c.pointerMove(const Point2(0.2, 0.2));
      c.pointerMove(const Point2(0.3, 0.3));
      c.pointerUp();
      expect(c.scene.strokes, hasLength(1));
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.scene.strokes, isEmpty);
      c.redo();
      expect(c.scene.strokes, hasLength(1));
    });

    test('선택 도구로 벽을 선택해 삭제할 수 있다', () {
      final c = SsReviewEditorController(baseModel: _model);
      c.setTool(SsReviewTool.select);
      c.selectAt(const Point2(0.2, 0.1));
      expect(c.selection.objectType, '벽');
      expect(c.selection.objectId, 'wall-1');
      c.deleteSelected();
      expect(c.effectiveModel.walls, isEmpty);
    });

    test('문을 선택해 창으로 바꿀 수 있다', () {
      final c = SsReviewEditorController(baseModel: _model);
      c.selectAt(const Point2(0.5, 0.1));
      expect(c.selection.objectType, '문');
      c.setSelectedOpeningKind(SSOpeningKind.window);
      expect(c.effectiveModel.openings.single.kind, SSOpeningKind.window);
    });

    test('벽 추가 — 두 번 눌러 한 벽을 만든다', () {
      final c = SsReviewEditorController(baseModel: _model);
      c.setTool(SsReviewTool.addWall);
      c.pointerDown(const Point2(0.2, 0.5));
      expect(c.addWallDraftStart, isNotNull);
      c.pointerDown(const Point2(0.8, 0.5));
      expect(c.addWallDraftStart, isNull);
      expect(c.effectiveModel.walls.length, 2);
    });

    test('문/창 추가 — 한 번 눌러 바로 추가된다', () {
      final c = SsReviewEditorController(baseModel: _model);
      c.setTool(SsReviewTool.addWindow);
      c.pointerDown(const Point2(0.5, 0.5));
      expect(c.effectiveModel.openings.length, 2);
      expect(c.effectiveModel.openings.last.kind, SSOpeningKind.window);
    });

    test('지우개로 지운 선도 Undo로 복원된다', () {
      final c = SsReviewEditorController(baseModel: _model);
      c.setTool(SsReviewTool.pen);
      c.pointerDown(const Point2(0.0, 0.0));
      c.pointerMove(const Point2(0.05, 0.05));
      c.pointerUp();
      expect(c.scene.strokes, hasLength(1));

      c.setTool(SsReviewTool.eraser);
      c.pointerDown(const Point2(0.0, 0.0));
      c.pointerUp();
      expect(c.scene.strokes, isEmpty);
      c.undo();
      expect(c.scene.strokes, hasLength(1));
    });
  });
}
