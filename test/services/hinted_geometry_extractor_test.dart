// Vision Guided CAD POC — HintedGeometryExtractor 단위 테스트.
//
// 실제 손으로 좌표를 만든 것이 아니라, 합성 "이미지 2" 픽셀
// (sample_image2_fixture.dart, image2Rooms/image2Envelope와 동일한
// 좌표로 그려짐)에 대해 진짜로 픽셀 스캔을 수행해 검증한다 — Vision
// hint는 일부러 부정확하게 주고(실제 벽 위치에서 어긋나게), extractor가
// 그 근방에서 실제 벽/개구부를 정밀하게 찾아내는지를 확인한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/vision_understanding.dart';
import 'package:ason_space/services/hinted_geometry_extractor.dart';
import 'package:ason_space/vision_cad_poc/sample_image2_fixture.dart';

void main() {
  late HintedGeometryExtractor extractor;

  setUpAll(() {
    extractor = HintedGeometryExtractor(buildImage2Png());
  });

  test('이미지가 정상적으로 디코딩되고 마스크가 준비된다', () {
    expect(extractor.isReady, isTrue);
    expect(extractor.width, kImage2Width);
    expect(extractor.height, kImage2Height);
  });

  group('refineBoundary — 부정확한 hint 근처에서 실제 벽을 정밀하게 찾는다', () {
    test('발코니|주방·식당 사이 수평 내벽 (실제 y=110)', () {
      // hint를 일부러 8px 어긋나게 준다.
      final candidate = extractor.refineBoundary(
        NormalizedPoint(380 / kImage2Width, 118 / kImage2Height),
        NormalizedPoint(620 / kImage2Width, 118 / kImage2Height),
      );
      expect(candidate, isNotNull);
      expect(candidate!.confidence, isNot(VisionConfidence.unknown));
      final points = candidate.geometry.allPoints;
      final avgY = (points.first.y + points.last.y) / 2 * kImage2Height;
      expect(avgY, closeTo(110, 2));
    });

    test('주방·식당|펜트리·욕실1 사이 수직 내벽 (실제 x=620)', () {
      final candidate = extractor.refineBoundary(
        NormalizedPoint(628 / kImage2Width, 110 / kImage2Height),
        NormalizedPoint(628 / kImage2Width, 320 / kImage2Height),
      );
      expect(candidate, isNotNull);
      final points = candidate!.geometry.allPoints;
      final avgX = (points.first.x + points.last.x) / 2 * kImage2Width;
      expect(avgX, closeTo(620, 2));
    });

    test('아무 벽도 없는 위치 hint는 confidence가 낮거나 못 찾는다', () {
      // 거실 한복판 — 벽이 전혀 없는 위치.
      final candidate = extractor.refineBoundary(
        NormalizedPoint(150 / kImage2Width, 400 / kImage2Height),
        NormalizedPoint(300 / kImage2Width, 400 / kImage2Height),
      );
      expect(
        candidate == null || candidate.confidence == VisionConfidence.low,
        isTrue,
      );
    });
  });

  group('refineOpening — 벽의 gap(문)과 연속된 벽을 구분한다', () {
    test('안방|드레스룸+부부거실 사이 문 (실제 gap y=150~190, x=280)', () {
      final result = extractor.refineOpening(
        boundaryStart: NormalizedPoint(280 / kImage2Width, 110 / kImage2Height),
        boundaryEnd: NormalizedPoint(280 / kImage2Width, 320 / kImage2Height),
        openingHint: NormalizedPoint(280 / kImage2Width, 165 / kImage2Height),
      );
      expect(result.found, isTrue);
      expect(result.wallContinuous, isFalse);
      expect(result.center, isNotNull);
      expect(result.center!.y * kImage2Height, closeTo(170, 15));
    });

    test('드레스룸|부부거실 사이는 문이 없는 연속 벽이다', () {
      final result = extractor.refineOpening(
        boundaryStart: NormalizedPoint(280 / kImage2Width, 190 / kImage2Height),
        boundaryEnd: NormalizedPoint(380 / kImage2Width, 190 / kImage2Height),
        openingHint: NormalizedPoint(330 / kImage2Width, 190 / kImage2Height),
      );
      expect(result.found, isFalse);
      expect(result.wallContinuous, isTrue);
    });
  });

  group('regionHasStructure — 오브젝트 hallucination 판별용 존재 확인', () {
    test('실제 벽이 그려진 영역은 구조가 있다고 판단한다', () {
      final hasStructure = extractor.regionHasStructure((
        minX: 375 / kImage2Width,
        minY: 105 / kImage2Height,
        maxX: 385 / kImage2Width,
        maxY: 320 / kImage2Height,
      ));
      expect(hasStructure, isTrue);
    });

    test('완전히 빈 흰 배경 영역은 구조가 없다고 판단한다', () {
      final hasStructure = extractor.regionHasStructure((
        minX: 120 / kImage2Width,
        minY: 400 / kImage2Height,
        maxX: 200 / kImage2Width,
        maxY: 480 / kImage2Height,
      ));
      expect(hasStructure, isFalse);
    });
  });
}
