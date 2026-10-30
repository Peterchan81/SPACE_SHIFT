// SS008 — [SsRecognitionSummary.fromModel] 레이어별 개수·검토 필요 요소 판정 검증.
import 'package:ason_space/models/floor_plan_geometry.dart' show Point2;
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/services/ss_recognition_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('레이어별 개수를 집계하고, 신뢰도가 낮거나 reviewNeeded인 요소만 확인 목록에 담는다', () {
    const model = SSSpatialModel(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      spaces: [
        SSSpace(id: 's-high', polygon: [Point2(0, 0), Point2(1, 0), Point2(1, 1)], areaNormalized: 0.5, closed: true, confidence: 0.9, spaceConfidence: SSSpaceConfidence.high),
        SSSpace(id: 's-low', polygon: [Point2(0, 0), Point2(1, 0), Point2(1, 1)], areaNormalized: 0.2, closed: true, confidence: 0.4, spaceConfidence: SSSpaceConfidence.low),
      ],
      walls: [
        SSWall(id: 'w-high', start: Point2(0, 0), end: Point2(1, 0), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
        SSWall(id: 'w-low', start: Point2(0, 0), end: Point2(0, 1), thicknessNormalized: 0.02, kind: SSWallKind.interior, confidence: 0.5),
      ],
      openings: [
        SSOpening(id: 'door-1', kind: SSOpeningKind.door, center: Point2(0.5, 0), widthNormalized: 0.05, confidence: 0.8),
        SSOpening(id: 'window-low', kind: SSOpeningKind.window, center: Point2(0.9, 0.5), widthNormalized: 0.05, confidence: 0.3),
      ],
      objects: [
        SSObjectCandidate(id: 'obj-toilet', polygon: [Point2(0.2, 0.2), Point2(0.3, 0.2), Point2(0.3, 0.3)], kind: SSObjectKind.toilet),
        SSObjectCandidate(id: 'obj-unknown', polygon: [Point2(0.6, 0.6), Point2(0.7, 0.6), Point2(0.7, 0.7)], kind: SSObjectKind.unknown),
      ],
      warnings: [],
      structuralElements: [
        SSStructuralElement(id: 'stair-1', kind: SSStructuralKind.stair, polygon: [Point2(0.1, 0.1), Point2(0.2, 0.1), Point2(0.2, 0.2)], confidence: 0.9),
        SSStructuralElement(id: 'col-low', kind: SSStructuralKind.column, polygon: [Point2(0.4, 0.4), Point2(0.45, 0.4), Point2(0.45, 0.45)], confidence: 0.2),
      ],
    );

    final summary = SsRecognitionSummary.fromModel(model);

    expect(summary.counts[SsRecognitionLayer.space], 2);
    expect(summary.counts[SsRecognitionLayer.wall], 2);
    expect(summary.counts[SsRecognitionLayer.door], 1);
    expect(summary.counts[SsRecognitionLayer.window], 1);
    expect(summary.counts[SsRecognitionLayer.fixture], 1);
    expect(summary.counts[SsRecognitionLayer.furniture], 1);
    expect(summary.counts[SsRecognitionLayer.stair], 1);
    expect(summary.counts[SsRecognitionLayer.column], 1);
    expect(summary.counts[SsRecognitionLayer.elevator], 0);
    expect(summary.totalCount, 10);

    final reviewIds = summary.reviewItems.map((r) => r.id).toSet();
    expect(reviewIds, {'s-low', 'w-low', 'window-low', 'obj-unknown', 'col-low'});
    expect(reviewIds.contains('s-high'), isFalse);
    expect(reviewIds.contains('door-1'), isFalse);
    expect(reviewIds.contains('obj-toilet'), isFalse);
    expect(reviewIds.contains('stair-1'), isFalse);
  });

  test('항상 보이는 레이어는 0개여도 알 수 있고, 가구/설비·구조요소는 검출된 적 없으면 모두 0이다(가짜 데이터 없음)', () {
    const model = SSSpatialModel(sourceWidthPx: 400, sourceHeightPx: 300, spaces: [], walls: [], openings: [], objects: [], warnings: []);
    final summary = SsRecognitionSummary.fromModel(model);
    for (final layer in SsRecognitionLayers.alwaysShown) {
      expect(summary.counts[layer], 0, reason: layer.name);
    }
    expect(summary.reviewItems, isEmpty);
    expect(summary.totalCount, 0);
  });
}
