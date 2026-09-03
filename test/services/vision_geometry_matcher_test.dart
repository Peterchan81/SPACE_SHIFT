// Vision Guided CAD POC — VisionGeometryMatcher CASE A~E 단위 테스트.
//
// 실제 HintedGeometryExtractor 결과(합성 "이미지 2" 픽셀 기반)와 인위
// 조작한 VisionConfidence 조합을 대조해, 설계 문서가 요구하는 5가지
// 경우가 정확히 그 경우로 분류되는지 확인한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/vision_understanding.dart';
import 'package:ason_space/services/hinted_geometry_extractor.dart';
import 'package:ason_space/services/vision_geometry_matcher.dart';
import 'package:ason_space/vision_cad_poc/sample_image2_fixture.dart';

void main() {
  final matcher = const VisionGeometryMatcher();
  late HintedGeometryExtractor extractor;

  setUpAll(() {
    extractor = HintedGeometryExtractor(buildImage2Png());
  });

  VisionBoundary boundary(VisionConfidence confidence) => VisionBoundary(
    id: 'b-1',
    confidence: confidence,
    geometryHint: const GeometryHint.segment(
      NormalizedPoint(380 / kImage2Width, 118 / kImage2Height),
      NormalizedPoint(620 / kImage2Width, 118 / kImage2Height),
    ),
    boundaryType: VisionBoundaryType.interiorWall,
  );

  group('matchBoundary', () {
    test('CASE A — vision HIGH + geometry HIGH → 확정', () {
      final geometry = extractor.refineBoundary(
        const NormalizedPoint(380 / kImage2Width, 118 / kImage2Height),
        const NormalizedPoint(620 / kImage2Width, 118 / kImage2Height),
      );
      final result = matcher.matchBoundary(
        boundary: boundary(VisionConfidence.high),
        geometryResult: geometry,
      );
      expect(result.matchCase, MatchCase.caseA);
      expect(result.confidence, VisionConfidence.high);
      expect(result.included, isTrue);
      expect(result.typeConfirmed, isTrue);
      expect(result.reviewNeeded, isFalse);
    });

    test('CASE B — vision HIGH + geometry LOW → semantic 유지, review 표시', () {
      const weakGeometry = GeometryCandidate(
        geometry: GeometryHint.segment(
          NormalizedPoint(0.1, 0.1),
          NormalizedPoint(0.2, 0.1),
        ),
        confidence: VisionConfidence.low,
        thicknessNormalized: 0.01,
      );
      final result = matcher.matchBoundary(
        boundary: boundary(VisionConfidence.high),
        geometryResult: weakGeometry,
      );
      expect(result.matchCase, MatchCase.caseB);
      expect(result.confidence, VisionConfidence.low);
      expect(result.included, isTrue);
      expect(result.typeConfirmed, isTrue);
      expect(result.reviewNeeded, isTrue);
    });

    test('CASE C — vision LOW + geometry HIGH → geometry만 채택, semantic 미확정', () {
      final geometry = extractor.refineBoundary(
        const NormalizedPoint(380 / kImage2Width, 118 / kImage2Height),
        const NormalizedPoint(620 / kImage2Width, 118 / kImage2Height),
      );
      final result = matcher.matchBoundary(
        boundary: boundary(VisionConfidence.low),
        geometryResult: geometry,
      );
      expect(result.matchCase, MatchCase.caseC);
      expect(result.source, VisionSource.geometry);
      expect(result.included, isTrue);
      expect(result.typeConfirmed, isFalse);
      expect(result.reviewNeeded, isTrue);
    });

    test('CASE E — geometry 근거 전혀 없음 → 제외', () {
      final result = matcher.matchBoundary(
        boundary: boundary(VisionConfidence.high),
        geometryResult: null,
      );
      expect(result.matchCase, MatchCase.caseE);
      expect(result.included, isFalse);
      expect(result.reviewNeeded, isTrue);
    });

    test('둘 다 LOW → 제외(불확실성 보존)', () {
      const weakGeometry = GeometryCandidate(
        geometry: GeometryHint.segment(
          NormalizedPoint(0.1, 0.1),
          NormalizedPoint(0.2, 0.1),
        ),
        confidence: VisionConfidence.low,
        thicknessNormalized: 0.01,
      );
      final result = matcher.matchBoundary(
        boundary: boundary(VisionConfidence.low),
        geometryResult: weakGeometry,
      );
      expect(result.included, isFalse);
      expect(result.reviewNeeded, isTrue);
    });
  });

  group('matchOpening', () {
    VisionOpening opening(VisionConfidence confidence) => VisionOpening(
      id: 'o-1',
      confidence: confidence,
      geometryHint: const GeometryHint.point(
        NormalizedPoint(280 / kImage2Width, 165 / kImage2Height),
      ),
      openingType: VisionOpeningType.door,
      attachedBoundaryId: 'b-1',
    );

    test('CASE A — 실제 문 gap 위치 + vision HIGH → 확정', () {
      final geometry = extractor.refineOpening(
        boundaryStart: const NormalizedPoint(280 / kImage2Width, 110 / kImage2Height),
        boundaryEnd: const NormalizedPoint(280 / kImage2Width, 320 / kImage2Height),
        openingHint: const NormalizedPoint(280 / kImage2Width, 165 / kImage2Height),
      );
      final result = matcher.matchOpening(opening: opening(VisionConfidence.high), geometryResult: geometry);
      expect(result.matchCase, MatchCase.caseA);
      expect(result.included, isTrue);
    });

    test('CASE C — 실제 문 gap 위치 + vision LOW → geometry만 채택', () {
      final geometry = extractor.refineOpening(
        boundaryStart: const NormalizedPoint(280 / kImage2Width, 110 / kImage2Height),
        boundaryEnd: const NormalizedPoint(280 / kImage2Width, 320 / kImage2Height),
        openingHint: const NormalizedPoint(280 / kImage2Width, 165 / kImage2Height),
      );
      final result = matcher.matchOpening(opening: opening(VisionConfidence.low), geometryResult: geometry);
      expect(result.matchCase, MatchCase.caseC);
      expect(result.typeConfirmed, isFalse);
      expect(result.included, isTrue);
    });

    test('CASE D — vision=문 주장, geometry=연속된 벽 → 충돌, 자동판단 안 함', () {
      final geometry = extractor.refineOpening(
        boundaryStart: const NormalizedPoint(280 / kImage2Width, 190 / kImage2Height),
        boundaryEnd: const NormalizedPoint(380 / kImage2Width, 190 / kImage2Height),
        openingHint: const NormalizedPoint(330 / kImage2Width, 190 / kImage2Height),
      );
      final result = matcher.matchOpening(opening: opening(VisionConfidence.high), geometryResult: geometry);
      expect(result.matchCase, MatchCase.caseD);
      expect(result.included, isFalse);
      expect(result.reviewNeeded, isTrue);
    });

    test('CASE E — gap도 연속 벽도 아님(추출 실패) → 제외', () {
      const result = OpeningGeometryResult(found: false, wallContinuous: false);
      final matched = matcher.matchOpening(opening: opening(VisionConfidence.high), geometryResult: result);
      expect(matched.matchCase, MatchCase.caseE);
      expect(matched.included, isFalse);
    });
  });

  group('matchObject', () {
    VisionObject object(VisionConfidence confidence) => VisionObject(
      id: 'obj-1',
      confidence: confidence,
      geometryHint: const GeometryHint.boundingBox(minX: 0, minY: 0, maxX: 0.1, maxY: 0.1),
      objectType: VisionObjectType.bed,
    );

    test('CASE A — 구조 있음 + vision HIGH → 확정', () {
      final result = matcher.matchObject(object: object(VisionConfidence.high), hasStructure: true);
      expect(result.matchCase, MatchCase.caseA);
      expect(result.included, isTrue);
    });

    test('CASE C — 구조 있음 + vision LOW → 존재만 인정, 종류 미확정', () {
      final result = matcher.matchObject(object: object(VisionConfidence.low), hasStructure: true);
      expect(result.matchCase, MatchCase.caseC);
      expect(result.typeConfirmed, isFalse);
      expect(result.included, isTrue);
    });

    test('CASE E — 구조 없음(hallucination 가능성) → 제외', () {
      final result = matcher.matchObject(object: object(VisionConfidence.high), hasStructure: false);
      expect(result.matchCase, MatchCase.caseE);
      expect(result.included, isFalse);
      expect(result.reviewNeeded, isTrue);
    });
  });
}
