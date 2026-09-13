// SPACE SHIFT — AI×CV CANONICAL MERGE WO 검증.
//
// [mergeAiDetectedOpenings]가 실제 픽셀(합성 "이미지 2" fixture, 이
// 세션에서 [HintedGeometryExtractor]/[VisionGuidedSpatialModelBuilder]
// 테스트가 이미 검증에 쓰는 것과 동일한 이미지)을 기준으로:
// - AI가 실제 gap이 있는 위치를 가리키면 그 벽에 CadOpening을 붙이고
// - AI가 문이 없는 연속 벽을 문이라고 주장하면 반영하지 않고
// - AI가 지목한 위치 근처에 CV 벽 자체가 없으면 반영하지 않는지
// 확인한다. "근거 없는 문/창을 지어내지 않는다"는 원칙이 핵심이다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/vision_understanding.dart';
import 'package:ason_space/services/ai_opening_bridge.dart';
import 'package:ason_space/services/vision_interpretation_service.dart';
import 'package:ason_space/vision_cad_poc/sample_image2_fixture.dart';

class _FakeVisionService implements VisionInterpretationService {
  _FakeVisionService(this.understanding);
  final VisionUnderstanding understanding;

  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async => understanding;
}

class _ThrowingVisionService implements VisionInterpretationService {
  const _ThrowingVisionService();
  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async {
    throw Exception('설정되지 않음');
  }
}

VisionUnderstanding _understandingWith(List<VisionOpening> openings) => VisionUnderstanding(
  floorDomain: const VisionFloorDomain(id: 'floor', confidence: VisionConfidence.high, geometryHint: null),
  openings: openings,
);

// 실제 image2 fixture의 안방|드레스룸+부부거실 사이 수직 벽(x=280,
// y=110~320) — 실제 문 gap이 y=150~190에 있다(기존
// hinted_geometry_extractor_test.dart와 동일한 좌표 소스).
CadWall _realVerticalWall() => const CadWall(
  id: 'wall-real-1',
  start: Point2(280 / kImage2Width, 110 / kImage2Height),
  end: Point2(280 / kImage2Width, 320 / kImage2Height),
  thicknessNormalized: kImage2WallThickness / kImage2Width,
  wallType: CadWallType.interior,
  confidence: 0.9,
);

// 드레스룸|부부거실 사이 수평 벽(y=190, x=280~380) — 전체 구간에 문이
// 없는 완전히 연속된 벽이다(기존 hinted_geometry_extractor_test.dart
// "드레스룸|부부거실 사이는 문이 없는 연속 벽이다"와 동일한 좌표 소스).
CadWall _continuousHorizontalWall() => const CadWall(
  id: 'wall-real-2',
  start: Point2(280 / kImage2Width, 190 / kImage2Height),
  end: Point2(380 / kImage2Width, 190 / kImage2Height),
  thicknessNormalized: kImage2WallThickness / kImage2Height,
  wallType: CadWallType.interior,
  confidence: 0.9,
);

CadFloorPlan _planWithWall(CadWall wall) => CadFloorPlan(
  sourceWidthPx: kImage2Width,
  sourceHeightPx: kImage2Height,
  walls: [wall],
  openings: const [],
  rooms: const [],
  warnings: const [],
);

VisionOpening _doorOpeningAt(double xPx, double yPx, {VisionConfidence confidence = VisionConfidence.high}) {
  return VisionOpening(
    id: 'ai-door-1',
    confidence: confidence,
    geometryHint: GeometryHint.point(NormalizedPoint(xPx / kImage2Width, yPx / kImage2Height)),
    openingType: VisionOpeningType.door,
  );
}

void main() {
  late Uint8List image2Bytes;

  setUpAll(() {
    image2Bytes = buildImage2Png();
  });

  test('AI가 실제 gap 위치를 가리키면 실제 벽에 CadOpening으로 반영된다', () async {
    final wall = _realVerticalWall();
    final plan = _planWithWall(wall);
    final vision = _FakeVisionService(_understandingWith([_doorOpeningAt(280, 165)]));

    final merged = await mergeAiDetectedOpenings(
      plan: plan,
      originalImageBytes: image2Bytes,
      visionService: vision,
    );

    expect(merged.openings, hasLength(1));
    final opening = merged.openings.single;
    expect(opening.wallId, wall.id);
    expect(opening.type, OpeningType.door);
    expect(opening.center.y * kImage2Height, closeTo(170, 15));
    expect(opening.widthNormalized, greaterThan(0));
    expect(merged.warnings.any((w) => w.contains('반영했습니다')), isTrue);
  });

  test('AI가 문이 없는 연속 벽을 문이라고 주장하면 반영하지 않는다(지어내지 않는다)', () async {
    // 드레스룸|부부거실 사이 — 전체 구간에 문이 없는 연속 벽.
    final wall = _continuousHorizontalWall();
    final plan = _planWithWall(wall);
    final vision = _FakeVisionService(_understandingWith([_doorOpeningAt(330, 190)]));

    final merged = await mergeAiDetectedOpenings(
      plan: plan,
      originalImageBytes: image2Bytes,
      visionService: vision,
    );

    expect(merged.openings, isEmpty);
    expect(merged.warnings.any((w) => w.contains('gap 없음') || w.contains('반영하지 않습니다')), isTrue);
  });

  test('AI가 지목한 위치 근처에 CV 벽 자체가 없으면 반영하지 않는다', () async {
    final wall = _realVerticalWall();
    final plan = _planWithWall(wall);
    // 완전히 다른 위치(거실 한복판, 벽에서 멀리 떨어짐).
    final vision = _FakeVisionService(_understandingWith([_doorOpeningAt(150, 450)]));

    final merged = await mergeAiDetectedOpenings(
      plan: plan,
      originalImageBytes: image2Bytes,
      visionService: vision,
    );

    expect(merged.openings, isEmpty);
    expect(merged.warnings.any((w) => w.contains('벽 연결 정보 없음/불일치')), isTrue);
  });

  test('Vision 서비스가 실패해도 예외 없이 원본 plan을 그대로 돌려준다', () async {
    final wall = _realVerticalWall();
    final plan = _planWithWall(wall);

    final merged = await mergeAiDetectedOpenings(
      plan: plan,
      originalImageBytes: image2Bytes,
      visionService: const _ThrowingVisionService(),
    );

    expect(merged.openings, isEmpty);
    expect(merged.walls, plan.walls);
    expect(merged.warnings, isNotEmpty);
  });

  test('AI가 openings를 하나도 감지하지 못하면 원본 plan을 그대로 돌려준다', () async {
    final wall = _realVerticalWall();
    final plan = _planWithWall(wall);
    final vision = _FakeVisionService(_understandingWith(const []));

    final merged = await mergeAiDetectedOpenings(
      plan: plan,
      originalImageBytes: image2Bytes,
      visionService: vision,
    );

    expect(merged.openings, isEmpty);
    expect(merged.walls, plan.walls);
  });
}
