// SPACE SHIFT — PC1 CONTINUE: FALSE POSITIVE CLEANUP (§3/§16).
// 단순 length cutoff가 아니라 두께+길이+junction+GPT 의미 ROI를 결합해
// text/furniture/fixture/door-arc/window-detail을 구분하는지, 그리고
// 진짜 짧은 구조 벽은 보존되는지 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/gpt_semantic_schema.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_classifier.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

const w = 400;
const h = 300;

PixelWallCandidate _reviewNeeded({
  required String id,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  int junction = 0,
}) {
  return PixelWallCandidate(
    id: id,
    start: Point2(x1 / w, y1 / h),
    end: Point2(x2 / w, y2 / h),
    thicknessNormalized: 1.5 / w,
    orientation: PixelWallOrientation.horizontal,
    isExterior: false,
    baseConfidence: 0.3,
    junctionSupport: junction,
    confidenceTier: PixelWallConfidenceTier.low,
    category: PixelWallCategory.reviewNeeded,
    sourceSegmentIds: [id],
  );
}

void main() {
  test('가구 ROI와 크게 겹치는 후보는 furniture로 분류된다', () {
    final candidate = _reviewNeeded(id: 'c1', x1: 55, y1: 10, x2: 65, y2: 10);
    final semantic = GptSemanticResponse(
      spaces: const [
        GptSemanticSpace(
          id: 's1',
          label: '거실',
          semanticType: 'livingRoom',
          approxRegion: GptApproxRegion(x0: 0, y0: 0, x1: 1, y1: 1),
        ),
      ],
      furnitureRegions: const [
        GptSemanticRegionNote(approxRegion: GptApproxRegion(x0: 0.12, y0: 0.02, x1: 0.18, y1: 0.06), note: '소파로 보임'),
      ],
    );
    final result = classifyNoiseCategories(candidates: [candidate], semantic: semantic);
    expect(result.single.noiseCategory, PixelWallNoiseCategory.furniture);
  });

  test('욕실 라벨 ROI 안의 가구성 후보는 fixture로 분류된다', () {
    final candidate = _reviewNeeded(id: 'c1', x1: 55, y1: 10, x2: 65, y2: 10);
    final semantic = GptSemanticResponse(
      spaces: const [
        GptSemanticSpace(
          id: 's1',
          label: '욕실1',
          semanticType: 'bathroom',
          approxRegion: GptApproxRegion(x0: 0.1, y0: 0, x1: 0.2, y1: 0.1),
        ),
      ],
      furnitureRegions: const [
        GptSemanticRegionNote(approxRegion: GptApproxRegion(x0: 0.12, y0: 0.02, x1: 0.18, y1: 0.06), note: '세면대로 보임'),
      ],
    );
    final result = classifyNoiseCategories(candidates: [candidate], semantic: semantic);
    expect(result.single.noiseCategory, PixelWallNoiseCategory.fixture);
  });

  test('문 ROI 근처의 후보는 doorArc로 분류된다', () {
    final candidate = _reviewNeeded(id: 'c1', x1: 60, y1: 20, x2: 68, y2: 20);
    final semantic = GptSemanticResponse(
      spaces: const [
        GptSemanticSpace(id: 's1', label: '거실', semanticType: 'livingRoom', approxRegion: GptApproxRegion(x0: 0, y0: 0, x1: 1, y1: 1)),
      ],
      openings: const [
        GptSemanticOpening(type: 'door', approxRegion: GptApproxRegion(x0: 0.15, y0: 0.06, x1: 0.17, y1: 0.08)),
      ],
    );
    final result = classifyNoiseCategories(candidates: [candidate], semantic: semantic);
    expect(result.single.noiseCategory, PixelWallNoiseCategory.doorArc);
  });

  test('얇고 짧고 junction 근거가 약한 후보는 text로 분류된다(단순 length cutoff 아님 — 두께+junction도 함께 봄)', () {
    final candidate = _reviewNeeded(id: 'c1', x1: 200, y1: 200, x2: 210, y2: 200, junction: 0);
    final result = applyTextHeuristic(candidates: [candidate], analysisWidthPx: w, analysisHeightPx: h);
    expect(result.single.noiseCategory, PixelWallNoiseCategory.text);
  });

  test('짧아도 junction 지지가 강하고 두꺼우면 text로 분류되지 않는다(진짜 짧은 구조 벽 보존)', () {
    final thickShortWall = PixelWallCandidate(
      id: 'c2',
      start: Point2(200 / w, 200 / h),
      end: Point2(210 / w, 200 / h),
      thicknessNormalized: 6 / w,
      orientation: PixelWallOrientation.horizontal,
      isExterior: false,
      baseConfidence: 0.5,
      junctionSupport: 2,
      confidenceTier: PixelWallConfidenceTier.medium,
      category: PixelWallCategory.reviewNeeded,
      sourceSegmentIds: const ['c2'],
    );
    final result = applyTextHeuristic(candidates: [thickShortWall], analysisWidthPx: w, analysisHeightPx: h);
    expect(result.single.noiseCategory, isNot(PixelWallNoiseCategory.text));
  });

  test('structural(이미 구조 벽으로 확정) candidate는 재분류하지 않는다', () {
    final structural = PixelWallCandidate(
      id: 's1',
      start: Point2(0.1, 0.1),
      end: Point2(0.5, 0.1),
      thicknessNormalized: 0.02,
      orientation: PixelWallOrientation.horizontal,
      isExterior: true,
      baseConfidence: 0.9,
      junctionSupport: 2,
      confidenceTier: PixelWallConfidenceTier.high,
      category: PixelWallCategory.structural,
      sourceSegmentIds: const ['s1'],
    );
    final semantic = GptSemanticResponse(
      spaces: const [GptSemanticSpace(id: 's1', label: 'x', semanticType: 'y', approxRegion: GptApproxRegion(x0: 0, y0: 0, x1: 1, y1: 1))],
      furnitureRegions: const [GptSemanticRegionNote(approxRegion: GptApproxRegion(x0: 0, y0: 0, x1: 1, y1: 1), note: '')],
    );
    var result = classifyNoiseCategories(candidates: [structural], semantic: semantic);
    result = applyTextHeuristic(candidates: result, analysisWidthPx: w, analysisHeightPx: h);
    expect(result.single.noiseCategory, PixelWallNoiseCategory.trueStructural);
  });
}
