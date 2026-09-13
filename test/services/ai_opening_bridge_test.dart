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

class _CallCountingVisionService implements VisionInterpretationService {
  _CallCountingVisionService(this.onCall);
  final VisionUnderstanding Function() onCall;

  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async => onCall();
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

CadFloorPlan _planWithWall(CadWall wall) => _planWithWalls([wall]);

CadFloorPlan _planWithWalls(List<CadWall> walls) => CadFloorPlan(
  sourceWidthPx: kImage2Width,
  sourceHeightPx: kImage2Height,
  walls: walls,
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
      sampleCount: 1,
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

  test('코너 근처에서 가장 가까운 벽이 틀린 벽이어도, 다음으로 가까운 벽에서 실제 gap을 찾아낸다', () async {
    // (280,190)은 gap 있는 수직 벽(x=280)과 gap 없는 수평 벽(y=190)이
    // 만나는 코너다. hint(290,188)는 수평 벽(dist=2)이 수직 벽
    // (dist=10)보다 훨씬 가깝다 — "가장 가까운 벽 1개"만 시도하면
    // 수평 벽(연속 벽)에서 실패하고 끝나버린다. 새 구현은 실패하면
    // 다음 후보(수직 벽)를 마저 시도해 실제 gap을 찾아야 한다.
    final verticalWithGap = _realVerticalWall();
    final horizontalContinuous = _continuousHorizontalWall();
    final plan = _planWithWalls([horizontalContinuous, verticalWithGap]);
    final vision = _FakeVisionService(_understandingWith([_doorOpeningAt(290, 188)]));

    final merged = await mergeAiDetectedOpenings(
      plan: plan,
      originalImageBytes: image2Bytes,
      visionService: vision,
      sampleCount: 1,
    );

    expect(merged.openings, hasLength(1));
    expect(merged.openings.single.wallId, verticalWithGap.id);
  });

  test('여러 번 표본추출(sampleCount)해 다른 호출에서만 감지된 문도 놓치지 않는다', () async {
    // 첫 호출은 완전히 다른(무관한) 위치만 감지하고, 두 번째 호출에서만
    // 실제 gap 위치를 감지한다고 가정한다 — 실제 GPT 호출 간 변동성을
    // 흉내낸다. sampleCount>1이면 한 번이라도 맞으면 반영돼야 한다.
    final wall = _realVerticalWall();
    final plan = _planWithWall(wall);
    var callCount = 0;
    final vision = _CallCountingVisionService(() {
      callCount++;
      return callCount == 1
          ? _understandingWith([_doorOpeningAt(150, 450)]) // 벽과 무관한 위치.
          : _understandingWith([_doorOpeningAt(280, 165)]); // 실제 gap 위치.
    });

    final merged = await mergeAiDetectedOpenings(
      plan: plan,
      originalImageBytes: image2Bytes,
      visionService: vision,
      sampleCount: 3,
    );

    expect(callCount, 3);
    expect(merged.openings, isNotEmpty);
    expect(merged.openings.any((o) => o.wallId == wall.id), isTrue);
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
