// SS009 — 평면도 확인·보정 보정 레이어([SsReviewScene])와 AI 인식 결과에 반영하는
// [applyReviewToSpatialModel] 단위 테스트.
//
// 1. 벽/개구부/가구 삭제는 "지웠다는 표시"만 남기고 원본 AI 인식 결과는 바꾸지 않는다.
// 2. 개구부 의미 수정(문→창)이 최종 모델에 반영된다.
// 3. 누락된 벽/문을 추가할 수 있고, 추가한 요소를 다시 지우면 깨끗이 없어진다.
// 4. "확인함"으로 표시한 요소는 최종 모델에서 reviewNeeded가 내려간다(원본은 그대로).
// 5. 펜 선을 그리고 지우개로 지울 수 있다.
// 6. JSON으로 저장했다가 복원해도 내용이 같다.
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_review_scene.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _model = SSSpatialModel(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  spaces: [
    SSSpace(
      id: 'space-1',
      polygon: [Point2(0, 0), Point2(1, 0), Point2(1, 1), Point2(0, 1)],
      areaNormalized: 1,
      closed: true,
      confidence: 0.9,
      reviewNeeded: true,
      reviewReasons: ['확인 필요'],
    ),
  ],
  walls: [
    SSWall(id: 'wall-1', start: Point2(0, 0), end: Point2(1, 0), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
    SSWall(id: 'wall-2', start: Point2(0, 0), end: Point2(0, 1), thicknessNormalized: 0.02, kind: SSWallKind.interior, confidence: 0.3),
  ],
  openings: [SSOpening(id: 'door-1', kind: SSOpeningKind.door, center: Point2(0.5, 0), widthNormalized: 0.05, confidence: 0.8)],
  objects: [
    SSObjectCandidate(
      id: 'obj-1',
      polygon: [Point2(0.1, 0.1), Point2(0.2, 0.1), Point2(0.2, 0.2), Point2(0.1, 0.2)],
      kind: SSObjectKind.furnitureOrEquipment,
    ),
  ],
  warnings: [],
);

void main() {
  group('SsReviewScene / applyReviewToSpatialModel', () {
    test('벽 삭제는 표시만 하고 원본 AI 인식 결과를 바꾸지 않는다', () {
      final scene = SsReviewScene.empty.removeWallById('wall-2');
      expect(scene.removedWallIds, {'wall-2'});
      final result = applyReviewToSpatialModel(_model, scene);
      expect(result.walls.map((w) => w.id), isNot(contains('wall-2')));
      expect(_model.walls.map((w) => w.id), contains('wall-2'));
    });

    test('개구부 의미 수정 — 문을 창으로 바꾼다', () {
      final scene = SsReviewScene.empty.setOpeningKind('door-1', SSOpeningKind.window);
      final result = applyReviewToSpatialModel(_model, scene);
      final opening = result.openings.firstWhere((o) => o.id == 'door-1');
      expect(opening.kind, SSOpeningKind.window);
      expect(_model.openings.single.kind, SSOpeningKind.door);
    });

    test('누락된 벽/문을 추가할 수 있다', () {
      final scene = SsReviewScene.empty.addWallSegment(const Point2(0.2, 0.2), const Point2(0.8, 0.2)).addOpeningAt(SSOpeningKind.window, const Point2(0.5, 0.2));
      final result = applyReviewToSpatialModel(_model, scene);
      expect(result.walls.length, _model.walls.length + 1);
      expect(result.openings.length, _model.openings.length + 1);
      expect(result.openings.last.kind, SSOpeningKind.window);
    });

    test('추가한 벽을 다시 지우면 깨끗이 없어진다(원본 삭제 목록을 더럽히지 않는다)', () {
      final added = SsReviewScene.empty.addWallSegment(const Point2(0, 0), const Point2(1, 1));
      final addedId = added.addedWalls.single.id;
      final removed = added.removeWallById(addedId);
      expect(removed.addedWalls, isEmpty);
      expect(removed.removedWallIds, isEmpty);
    });

    test('가구/설비를 삭제할 수 있다', () {
      final scene = SsReviewScene.empty.removeObjectById('obj-1');
      final result = applyReviewToSpatialModel(_model, scene);
      expect(result.objects, isEmpty);
    });

    test('확인 필요 항목을 확인함으로 표시하면 최종 모델에서 reviewNeeded가 내려간다', () {
      final scene = SsReviewScene.empty.markResolved('space-1');
      final result = applyReviewToSpatialModel(_model, scene);
      expect(result.spaces.single.reviewNeeded, isFalse);
      expect(_model.spaces.single.reviewNeeded, isTrue);
    });

    test('펜 선 추가 후 지우개로 지울 수 있다', () {
      final scene = SsReviewScene.empty.addStroke(
        SsAnnotationTool.pen,
        colorValue: 0xFFFF0000,
        strokeWidth: 3,
        points: const [Point2(0.1, 0.1), Point2(0.2, 0.2)],
      );
      expect(scene.strokes, hasLength(1));
      final erased = scene.eraseNear(const Point2(0.1, 0.1));
      expect(erased.strokes, isEmpty);
    });

    test('JSON 왕복', () {
      final scene = SsReviewScene.empty
          .removeWallById('wall-2')
          .setOpeningKind('door-1', SSOpeningKind.window)
          .addWallSegment(const Point2(0, 0), const Point2(1, 1))
          .markResolved('space-1')
          .addStroke(SsAnnotationTool.highlighter, colorValue: 0xFFFFFF00, strokeWidth: 4, points: const [Point2(0, 0), Point2(1, 1)]);
      final restored = SsReviewScene.tryFromJson(scene.toJson());
      expect(restored.removedWallIds, scene.removedWallIds);
      expect(restored.openingKindOverrides, scene.openingKindOverrides);
      expect(restored.addedWalls.length, scene.addedWalls.length);
      expect(restored.resolvedReviewIds, scene.resolvedReviewIds);
      expect(restored.strokes.length, scene.strokes.length);
    });
  });
}
