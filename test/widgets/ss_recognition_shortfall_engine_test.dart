// #1027-23 남은 문제 1 — 인식 부족 안내 머리말이 기본 엔진 후보 개수와 모순되지 않는다.
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/services/ss_recognition_summary.dart';
import 'package:ason_space/widgets/workspace/ss_recognition_shortfall.dart';
import 'package:flutter_test/flutter_test.dart';

const _stats = FloorPlanAnalysisDebugStats(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  analysisWidthPx: 800,
  analysisHeightPx: 600,
  rawHorizontalRuns: 3,
  rawVerticalRuns: 0,
  mergedWallCount: 3,
  roomCandidateCount: 0,
  openingCandidateCount: 0,
  durationMs: 1,
);

const _engineThreeWalls = FloorPlanAnalysisResult(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  walls: [
    WallSegment(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.4, 0.1), thicknessNormalized: 0.01, confidence: 0.8),
    WallSegment(id: 'w2', start: Point2(0.5, 0.5), end: Point2(0.8, 0.5), thicknessNormalized: 0.01, confidence: 0.8),
    WallSegment(id: 'w3', start: Point2(0.2, 0.8), end: Point2(0.6, 0.8), thicknessNormalized: 0.01, confidence: 0.8),
  ],
  openings: [],
  rooms: [],
  warnings: [],
  debugStats: _stats,
);

const _emptyModel = SSSpatialModel(sourceWidthPx: 800, sourceHeightPx: 600, spaces: [], walls: [], openings: [], objects: [], warnings: []);

const _oneWallModel = SSSpatialModel(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  spaces: [],
  walls: [
    SSWall(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.4, 0.1), thicknessNormalized: 0.01, kind: SSWallKind.exterior, confidence: 0.8),
  ],
  openings: [],
  objects: [],
  warnings: [],
);

void main() {
  test('엔진이 벽 3개를 찾았지만 결과에 벽이 없으면 "벽을 찾지 못했습니다"라고 하지 않고 사실대로 알린다', () {
    final s = SsRecognitionShortfall.evaluate(
      summary: SsRecognitionSummary.fromModel(_emptyModel),
      aiRecognitionConnected: false,
      engineResult: _engineThreeWalls,
    );
    expect(s, isNotNull);
    expect(s!.headline, isNot(contains('벽을 찾지 못했습니다')));
    expect(s.headline, contains('엔진이 찾은 벽 3개는 방을 이루지 못해 결과에 넣지 않았습니다'));
    expect(s.engineDetail, contains('벽 3'));
  });

  test('결과에 벽 일부만 들어가면 빠진 개수를 함께 알린다', () {
    final s = SsRecognitionShortfall.evaluate(
      summary: SsRecognitionSummary.fromModel(_oneWallModel),
      aiRecognitionConnected: false,
      engineResult: _engineThreeWalls,
    );
    expect(s!.headline, contains('벽 1개만 인식'));
    expect(s.headline, contains('3개 중 2개는 방을 이루지 못해'));
  });

  test('엔진도 벽을 찾지 못했으면 지금처럼 "벽을 찾지 못했습니다"', () {
    const engineNone = FloorPlanAnalysisResult(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      walls: [],
      openings: [],
      rooms: [],
      warnings: [],
      debugStats: _stats,
    );
    final s = SsRecognitionShortfall.evaluate(
      summary: SsRecognitionSummary.fromModel(_emptyModel),
      aiRecognitionConnected: false,
      engineResult: engineNone,
    );
    expect(s!.headline, contains('벽을 찾지 못했습니다'));
    expect(s.engineDetail, contains('벽 0'));
  });
}
