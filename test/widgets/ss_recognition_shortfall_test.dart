// SS-수정004 — 인식 결과 부족 판단(SsRecognitionShortfall) 단위 테스트.
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/services/ss_recognition_summary.dart';
import 'package:ason_space/widgets/workspace/ss_recognition_shortfall.dart';
import 'package:flutter_test/flutter_test.dart';

const _threeWallsNoRoom = SSSpatialModel(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  spaces: [],
  walls: [
    SSWall(id: 'w1', start: Point2(0, 0), end: Point2(1, 0), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
    SSWall(id: 'w2', start: Point2(0, 0), end: Point2(0, 1), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
    SSWall(id: 'w3', start: Point2(1, 0), end: Point2(1, 1), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
  ],
  openings: [],
  objects: [],
  warnings: [],
);

const _goodModel = SSSpatialModel(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  spaces: [
    SSSpace(id: 'space-1', polygon: [Point2(0.05, 0.05), Point2(0.95, 0.05), Point2(0.95, 0.95), Point2(0.05, 0.95)], areaNormalized: 0.8, closed: true, confidence: 0.9),
  ],
  walls: [
    SSWall(id: 'wall-1', start: Point2(0, 0), end: Point2(1, 0), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
    SSWall(id: 'wall-2', start: Point2(0, 0), end: Point2(0, 1), thicknessNormalized: 0.02, kind: SSWallKind.interior, confidence: 0.9),
  ],
  openings: [
    SSOpening(id: 'door-1', kind: SSOpeningKind.door, center: Point2(0.5, 0.0), widthNormalized: 0.05, confidence: 0.8),
  ],
  objects: [],
  warnings: [],
);

void main() {
  test('방 0개 · 벽 3개면 무엇이 부족한지와 기본 엔진 사용 사실을 알려준다', () {
    final s = SsRecognitionShortfall.evaluate(
      summary: SsRecognitionSummary.fromModel(_threeWallsNoRoom),
      aiRecognitionConnected: false,
      warnings: const ['공간이 완전히 닫히지 않았습니다. 벽을 직접 보정해주세요.'],
    );
    expect(s, isNotNull);
    expect(s!.headline, contains('방을 찾지 못했습니다'));
    expect(s.headline, contains('벽 3개만 인식'));
    expect(s.reason, contains('기본 인식 엔진'));
    expect(s.warnings, contains('공간이 완전히 닫히지 않았습니다. 벽을 직접 보정해주세요.'));
  });

  test('충분히 인식되고 경고가 없으면 안내하지 않는다', () {
    final s = SsRecognitionShortfall.evaluate(summary: SsRecognitionSummary.fromModel(_goodModel), aiRecognitionConnected: false);
    expect(s, isNull);
  });

  test('인식 결과 자체가 없으면(요약 없음) 안내한다', () {
    final s = SsRecognitionShortfall.evaluate(summary: null, aiRecognitionConnected: false);
    expect(s, isNotNull);
    expect(s!.headline, contains('벽을 찾지 못했습니다'));
  });

  test('AI 인식이 연결된 서비스라면 이유 문구도 그 사실대로 바뀐다', () {
    final s = SsRecognitionShortfall.evaluate(summary: null, aiRecognitionConnected: true);
    expect(s!.reason, isNot(contains('기본 인식 엔진')));
  });

  test('CAD 변환은 벽이 1개 이상일 때만 가능하다', () {
    const empty = SSSpatialModel(sourceWidthPx: 0, sourceHeightPx: 0, spaces: [], walls: [], openings: [], objects: [], warnings: []);
    expect(SsRecognitionShortfall.canConvertToCad(SsRecognitionSummary.fromModel(empty)), isFalse);
    expect(SsRecognitionShortfall.canConvertToCad(SsRecognitionSummary.fromModel(_threeWallsNoRoom)), isTrue);
  });
}
