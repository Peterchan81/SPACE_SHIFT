// SPACE SHIFT — WO088-1 IMAGE 2 COORDINATE-BASED 2D STRUCTURE POC.
//
// [buildCoordStructureFromExtraction]이 pixel_wall_extractor.dart의
// 1단계 evidence만 가져오고(§8 — WallSystem/PlanarGraph/FloorDomain을
// 전혀 쓰지 않는다), 정규화 좌표가 이미지 해상도/화면 zoom과 무관하게
// 안정적인지, 사용자 수정이 나머지 구조와 분리되는지(§9)를 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/vision_cad_poc/coord_structure_v1/coord_structure_model.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/gpt_semantic_schema.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

PixelWallCandidate _seg({
  required String id,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  bool isExterior = false,
  PixelWallCategory category = PixelWallCategory.structural,
}) {
  final o = y1 == y2 ? PixelWallOrientation.horizontal : PixelWallOrientation.vertical;
  return PixelWallCandidate(
    id: id,
    start: Point2(x1, y1),
    end: Point2(x2, y2),
    thicknessNormalized: 0.02,
    orientation: o,
    isExterior: isExterior,
    baseConfidence: 0.8,
    junctionSupport: 2,
    confidenceTier: PixelWallConfidenceTier.high,
    category: category,
    sourceSegmentIds: [id],
  );
}

PixelWallExtractionResult _extraction({required List<PixelWallCandidate> candidates, int w = 400, int h = 300}) {
  return PixelWallExtractionResult.success(
    sourceWidthPx: w,
    sourceHeightPx: h,
    analysisWidthPx: w,
    analysisHeightPx: h,
    mask: null,
    candidates: candidates,
    rejected: const [],
    openings: const [],
    rooms: const [],
    rotationDegrees: 0,
    rawWallSegmentCount: candidates.length,
  );
}

void main() {
  group('buildCoordStructureFromExtraction — 1단계 evidence만 사용', () {
    test('normalized coordinate 변환 — candidate의 start/end가 그대로 보존된다', () {
      final c = _seg(id: 'w1', x1: 0.1, y1: 0.2, x2: 0.9, y2: 0.2, isExterior: true);
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [c]));
      expect(model.walls, hasLength(1));
      expect(model.walls.single.start.x, closeTo(0.1, 1e-9));
      expect(model.walls.single.start.y, closeTo(0.2, 1e-9));
      expect(model.walls.single.end.x, closeTo(0.9, 1e-9));
      expect(model.walls.single.isExterior, isTrue);
    });

    test('reviewNeeded candidate도 조용히 삭제되지 않고 그대로 포함된다', () {
      final structural = _seg(id: 'w1', x1: 0, y1: 0, x2: 1, y2: 0);
      final review = _seg(id: 'w2', x1: 0, y1: 0.5, x2: 0.3, y2: 0.5, category: PixelWallCategory.reviewNeeded);
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [structural, review]));
      expect(model.walls, hasLength(2));
      expect(model.walls.firstWhere((w) => w.id == 'w2').reviewNeeded, isTrue);
    });

    test('image resize 후 좌표 불변 — 같은 candidate가 다른 분석 해상도(w/h)에서도 동일한 정규화 좌표를 만든다', () {
      final c = _seg(id: 'w1', x1: 0.25, y1: 0.75, x2: 0.6, y2: 0.75);
      final small = buildCoordStructureFromExtraction(_extraction(candidates: [c], w: 300, h: 200));
      final large = buildCoordStructureFromExtraction(_extraction(candidates: [c], w: 3000, h: 2000));
      expect(small.walls.single.start.x, large.walls.single.start.x);
      expect(small.walls.single.start.y, large.walls.single.start.y);
      expect(small.walls.single.end.x, large.walls.single.end.x);
    });
  });

  group('overlay transform — 화면 zoom과 무관하게 비율이 유지된다', () {
    test('같은 정규화 좌표가 캔버스 크기에 비례해서만 달라진다', () {
      const p = Point2(0.25, 0.5);
      final small = toCanvasPoint(p, canvasWidth: 100, canvasHeight: 100);
      final large = toCanvasPoint(p, canvasWidth: 1000, canvasHeight: 1000);
      expect(large.x / small.x, closeTo(10, 1e-9));
      expect(large.y / small.y, closeTo(10, 1e-9));
      expect(small.x / 100, closeTo(p.x, 1e-9));
    });
  });

  group('gridLines — 화면 zoom과 무관한 고정 간격', () {
    test('0.1 간격이면 0.0부터 1.0까지 11개 선이 나온다', () {
      final lines = gridLines(stepNormalized: 0.1);
      expect(lines, hasLength(11));
      expect(lines.first, 0.0);
      expect(lines.last, 1.0);
    });
  });

  group('deriveCorners — wall endpoint 클러스터링(위상 판단 아님)', () {
    test('가까운 두 벽의 끝점은 하나의 corner로 묶인다', () {
      final a = _seg(id: 'a', x1: 0, y1: 0, x2: 0.5, y2: 0);
      final b = _seg(id: 'b', x1: 0.5001, y1: 0.0001, x2: 0.5001, y2: 0.5); // a의 끝점과 거의 같은 위치.
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [a, b]));
      final sharedCorner = model.corners.firstWhere((c) => c.wallIds.contains('a') && c.wallIds.contains('b'));
      expect(sharedCorner.wallIds, containsAll(['a', 'b']));
    });

    test('멀리 떨어진 끝점은 서로 다른 corner로 남는다', () {
      final a = _seg(id: 'a', x1: 0, y1: 0, x2: 0.5, y2: 0);
      final b = _seg(id: 'b', x1: 0.9, y1: 0.9, x2: 0.9, y2: 0.5);
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [a, b]));
      final aCorners = model.corners.where((c) => c.wallIds.contains('a'));
      final bCorners = model.corners.where((c) => c.wallIds.contains('b'));
      expect(aCorners.any((c) => c.wallIds.contains('b')), isFalse);
      expect(bCorners.any((c) => c.wallIds.contains('a')), isFalse);
    });
  });

  group('user correction — §9 AI 결과를 정답으로 고정하지 않는다', () {
    test('wall endpoint 이동 — 그 벽만 바뀌고 나머지 구조는 그대로 유지된다', () {
      final a = _seg(id: 'a', x1: 0, y1: 0, x2: 0.5, y2: 0);
      final b = _seg(id: 'b', x1: 0.7, y1: 0.7, x2: 0.9, y2: 0.7);
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [a, b]));

      final moved = model.walls.first.copyWith(end: const Point2(0.55, 0.02), source: CoordEvidenceSource.userEdited);
      final corrected = model.copyWithWalls([moved, model.walls[1]]);

      expect(corrected.walls.first.end.x, closeTo(0.55, 1e-9));
      expect(corrected.walls.first.source, CoordEvidenceSource.userEdited);
      expect(corrected.walls[1].start.x, model.walls[1].start.x, reason: '수정하지 않은 다른 벽은 절대 바뀌면 안 된다');
      expect(corrected.openings, model.openings);
      expect(corrected.regions, model.regions);
    });

    test('잘못된 segment 제거 — 나머지 벽은 그대로 유지된다', () {
      final a = _seg(id: 'a', x1: 0, y1: 0, x2: 0.5, y2: 0);
      final b = _seg(id: 'b', x1: 0.7, y1: 0.7, x2: 0.9, y2: 0.7);
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [a, b]));
      final afterDelete = model.copyWithWalls(model.walls.where((w) => w.id != 'a').toList());
      expect(afterDelete.walls, hasLength(1));
      expect(afterDelete.walls.single.id, 'b');
    });

    test('빠진 segment 추가 — userEdited source로 새 벽이 들어가고 기존 벽은 안 바뀐다', () {
      final a = _seg(id: 'a', x1: 0, y1: 0, x2: 0.5, y2: 0);
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [a]));
      const added = CoordWallSegment(
        id: 'user-1',
        start: Point2(0.5, 0),
        end: Point2(0.5, 0.5),
        thicknessNormalized: 0.02,
        isExterior: false,
        confidence: 1.0,
        reviewNeeded: false,
        source: CoordEvidenceSource.userEdited,
      );
      final afterAdd = model.copyWithWalls([...model.walls, added]);
      expect(afterAdd.walls, hasLength(2));
      expect(afterAdd.walls.last.source, CoordEvidenceSource.userEdited);
      expect(afterAdd.walls.first.start.x, model.walls.first.start.x);
    });
  });

  group('flagInterferenceEvidence — WO088-2 §8 가구/설비 오탐을 삭제 대신 review evidence로', () {
    GptSemanticResponse semanticWith({List<GptSemanticRegionNote> furniture = const [], List<GptSemanticRegionNote> ambiguous = const []}) {
      return GptSemanticResponse(
        spaces: const [
          GptSemanticSpace(id: 's1', label: '테스트공간', semanticType: 'room', approxRegion: GptApproxRegion(x0: 0, y0: 0, x1: 1, y1: 1)),
        ],
        furnitureRegions: furniture,
        ambiguousRegions: ambiguous,
      );
    }

    test('furnitureRegion과 겹치는 wall은 삭제되지 않고 reviewNeeded+근거만 추가된다', () {
      // wall 중점 = (0.2, 0.2) — furnitureRegion(0.1..0.3, 0.1..0.3) 내부.
      final c = _seg(id: 'w1', x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.2, isExterior: true);
      final semantic = semanticWith(
        furniture: const [GptSemanticRegionNote(approxRegion: GptApproxRegion(x0: 0.1, y0: 0.1, x1: 0.3, y1: 0.3), note: '옷장으로 보임')],
      );
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [c]), semantic: semantic);
      expect(model.walls, hasLength(1), reason: '자동 삭제 금지 — 여전히 목록에 있어야 한다');
      final w = model.walls.single;
      expect(w.reviewNeeded, isTrue);
      expect(w.reviewReasons, isNotEmpty);
      expect(w.reviewReasons.single, contains('possibleFurnitureInterference'));
      expect(w.reviewReasons.single, contains('옷장으로 보임'));
      // 좌표 자체는 evidence 그대로 — semantic이 좌표를 다시 그리지 않는다(§7).
      expect(w.start.x, closeTo(0.1, 1e-9));
      expect(w.end.x, closeTo(0.3, 1e-9));
    });

    test('ambiguousRegion과 겹치는 wall은 possibleFixtureInterference가 아니라 실제 스키마 의미(possibleAmbiguousRegionInterference)로 정직하게 표시된다', () {
      final c = _seg(id: 'w1', x1: 0.6, y1: 0.6, x2: 0.8, y2: 0.6, isExterior: false);
      final semantic = semanticWith(
        ambiguous: const [GptSemanticRegionNote(approxRegion: GptApproxRegion(x0: 0.5, y0: 0.5, x1: 0.9, y1: 0.9), note: '구조가 불명확함')],
      );
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [c]), semantic: semantic);
      expect(model.walls, hasLength(1));
      expect(model.walls.single.reviewReasons.single, contains('possibleAmbiguousRegionInterference'));
    });

    test('겹치는 region이 없으면 reviewReasons가 비어 있고 reviewNeeded도 그대로다', () {
      final c = _seg(id: 'w1', x1: 0.0, y1: 0.0, x2: 0.05, y2: 0.0);
      final semantic = semanticWith(
        furniture: const [GptSemanticRegionNote(approxRegion: GptApproxRegion(x0: 0.8, y0: 0.8, x1: 0.9, y1: 0.9), note: '멀리 떨어진 가구')],
      );
      final model = buildCoordStructureFromExtraction(_extraction(candidates: [c]), semantic: semantic);
      expect(model.walls.single.reviewNeeded, isFalse);
      expect(model.walls.single.reviewReasons, isEmpty);
    });

    test('semantic이 null이면 flagInterferenceEvidence가 아무 것도 바꾸지 않는다(§7 semantic이 좌표를 임의로 바꾸지 않는다)', () {
      final c = _seg(id: 'w1', x1: 0.1, y1: 0.1, x2: 0.4, y2: 0.1);
      final withoutSemantic = buildCoordStructureFromExtraction(_extraction(candidates: [c]));
      expect(withoutSemantic.walls.single.reviewNeeded, isFalse);
      expect(withoutSemantic.walls.single.reviewReasons, isEmpty);
      expect(withoutSemantic.walls.single.start.x, closeTo(0.1, 1e-9));
    });
  });
}
