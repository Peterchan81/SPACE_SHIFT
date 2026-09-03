import 'dart:typed_data';

import '../models/vision_understanding.dart';
import '../vision_cad_poc/sample_image2_fixture.dart';
import 'vision_interpretation_service.dart';

/// Vision Guided CAD POC — Mock Vision Provider(설계 3번).
///
/// 실제 Claude/OpenAI Vision을 호출하지 않는다(API 키 없이 이 POC를
/// 완결하기 위한 명시적 요구사항). 대신 "이미지 2"를 사람이 육안으로
/// 미리 관찰한 semantic 이해를, 실제 사용할 Vision provider가 돌려줄
/// 법한 형태(대략적인 위치 + 명확한 confidence 구분)로 흉내낸다.
///
/// 반드시 지키는 것:
/// - 모든 geometryHint는 [sample_image2_fixture]의 실제 픽셀 좌표에서
///   의도적으로 몇 px씩 어긋나 있다 — 이 값을 최종 CAD 좌표로 그대로
///   쓰면 안 된다는 실험적 증거이기도 하다.
/// - 드레스룸|부부거실 사이(y=190)에는 실제로 문이 없는데도, 이 Mock은
///   "문이 있는 것 같다"는 잘못된 hint를 하나 일부러 포함한다 — 실제
///   Vision 모델도 이런 오판을 할 수 있고, 이 파이프라인이 그런 오판을
///   (틀렸다고 자동으로 확정하지도, 무시하지도 않고) CASE D로 잡아내는지
///   보여주기 위함이다.
/// - 실제로 그려지지 않은 가구(bed)를 하나 hint로 포함한다 — Vision
///   hallucination을 CASE E로 배제하는 경로를 보여주기 위함이다.
/// - scaleConfirmed는 항상 false다 — 이 도면에는 인쇄된 치수가 없다.
class MockVisionInterpretationService implements VisionInterpretationService {
  const MockVisionInterpretationService();

  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async {
    return VisionUnderstanding(
      floorDomain: VisionFloorDomain(
        id: 'floor-domain',
        confidence: VisionConfidence.high,
        geometryHint: GeometryHint.polygon([
          for (final p in image2Envelope) _jitter(p.x, p.y, 5),
        ]),
      ),
      spaces: [
        _space('balcony', VisionSpaceSemanticType.balcony, VisionConfidence.medium),
        _space('masterBedroom', VisionSpaceSemanticType.bedroomMaster, VisionConfidence.high),
        _space('dressRoom', VisionSpaceSemanticType.utility, VisionConfidence.medium),
        _space('masterLiving', VisionSpaceSemanticType.living, VisionConfidence.medium),
        _space('kitchenDining', VisionSpaceSemanticType.kitchen, VisionConfidence.high),
        _space('pantry', VisionSpaceSemanticType.pantry, VisionConfidence.medium),
        _space('bath1', VisionSpaceSemanticType.bathroom, VisionConfidence.high),
        _space('entrance', VisionSpaceSemanticType.entrance, VisionConfidence.high),
        _space('living', VisionSpaceSemanticType.living, VisionConfidence.high),
        _space('bath2', VisionSpaceSemanticType.bathroom, VisionConfidence.high),
        _space('bedroom2', VisionSpaceSemanticType.bedroom, VisionConfidence.high),
        _space('bedroom1', VisionSpaceSemanticType.bedroom, VisionConfidence.high),
        // 실외기실은 위쪽이 열려있어 실제로도 판단이 애매한 공간이다 —
        // 일부러 낮은 confidence로 표시한다(정직한 불확실성).
        _space('mechanical', VisionSpaceSemanticType.mechanicalRoom, VisionConfidence.low),
      ],
      boundaries: [
        // 외곽(E1~E12) — image2Envelope의 각 변.
        for (var i = 0; i < image2Envelope.length; i++)
          _boundary(
            'exterior-$i',
            image2Envelope[i],
            image2Envelope[(i + 1) % image2Envelope.length],
            VisionBoundaryType.exteriorWall,
            isExterior: true,
          ),
        _boundary(
          'balcony-kitchenDining',
          (x: 380, y: 110),
          (x: 620, y: 110),
          VisionBoundaryType.interiorWall,
        ),
        _boundary(
          'masterBedroom-dressLiving',
          (x: 280, y: 110),
          (x: 280, y: 320),
          VisionBoundaryType.interiorWall,
        ),
        _boundary(
          'dressRoom-masterLiving',
          (x: 280, y: 190),
          (x: 380, y: 190),
          VisionBoundaryType.interiorWall,
        ),
        _boundary(
          'kitchenDining-pantryBath1',
          (x: 620, y: 110),
          (x: 620, y: 320),
          VisionBoundaryType.interiorWall,
        ),
        _boundary(
          'pantryBath1-entrance',
          (x: 700, y: 110),
          (x: 700, y: 320),
          VisionBoundaryType.interiorWall,
        ),
        _boundary(
          'pantry-bath1',
          (x: 620, y: 220),
          (x: 700, y: 220),
          VisionBoundaryType.interiorWall,
        ),
        _boundary(
          'upperLower',
          (x: 60, y: 320),
          (x: 840, y: 320),
          VisionBoundaryType.interiorWall,
        ),
        _boundary(
          'bath2-bedroom2',
          (x: 460, y: 320),
          (x: 460, y: 540),
          VisionBoundaryType.interiorWall,
        ),
        _boundary(
          'bedroom2-bedroom1',
          (x: 620, y: 320),
          (x: 620, y: 540),
          VisionBoundaryType.interiorWall,
        ),
      ],
      openings: [
        _opening(
          'masterBedroom-dressLiving-door',
          'masterBedroom-dressLiving',
          x: 280,
          y: 170,
          confidence: VisionConfidence.high,
        ),
        _opening(
          'pantryBath1-entrance-door',
          'pantryBath1-entrance',
          x: 700,
          y: 170,
          confidence: VisionConfidence.high,
        ),
        _opening(
          'upperLower-door',
          'upperLower',
          x: 170,
          y: 320,
          confidence: VisionConfidence.medium,
        ),
        _opening(
          'bedroom2-bedroom1-door',
          'bedroom2-bedroom1',
          x: 620,
          y: 420,
          confidence: VisionConfidence.high,
        ),
        // 실제로는 문이 없는 연속 벽인데 Vision이 문이 있다고 오판한
        // 경우 — CASE D(충돌) 시연용.
        _opening(
          'dressRoom-masterLiving-door',
          'dressRoom-masterLiving',
          x: 330,
          y: 190,
          confidence: VisionConfidence.medium,
        ),
      ],
      objects: [
        // 실제로 그려지지 않은 가구 — CASE E(hallucination 배제) 시연용.
        VisionObject(
          id: 'hallucinated-bed',
          confidence: VisionConfidence.medium,
          geometryHint: GeometryHint.boundingBox(
            minX: 80 / kImage2Width,
            minY: 130 / kImage2Height,
            maxX: 220 / kImage2Width,
            maxY: 230 / kImage2Height,
          ),
          objectType: VisionObjectType.bed,
          containingSpaceId: 'space-masterBedroom',
        ),
      ],
      scaleConfirmed: false,
      notes: const [
        'no printed dimension text was observed on this drawing — scale remains unconfirmed',
      ],
    );
  }

  VisionSpace _space(String key, VisionSpaceSemanticType type, VisionConfidence confidence) {
    final box = image2Rooms[key]!;
    return VisionSpace(
      id: 'space-$key',
      confidence: confidence,
      geometryHint: GeometryHint.boundingBox(
        minX: (box.left - 6) / kImage2Width,
        minY: (box.top - 6) / kImage2Height,
        maxX: (box.right + 6) / kImage2Width,
        maxY: (box.bottom + 6) / kImage2Height,
      ),
      label: box.label,
      semanticType: type,
    );
  }

  VisionBoundary _boundary(
    String id,
    ({num x, num y}) start,
    ({num x, num y}) end,
    VisionBoundaryType type, {
    bool isExterior = false,
  }) {
    return VisionBoundary(
      id: 'boundary-$id',
      confidence: VisionConfidence.high,
      geometryHint: GeometryHint.segment(
        _jitter(start.x.toDouble(), start.y.toDouble(), 4),
        _jitter(end.x.toDouble(), end.y.toDouble(), 4),
      ),
      boundaryType: type,
    );
  }

  VisionOpening _opening(
    String id,
    String boundaryId, {
    required double x,
    required double y,
    required VisionConfidence confidence,
  }) {
    return VisionOpening(
      id: 'opening-$id',
      confidence: confidence,
      geometryHint: GeometryHint.point(_jitter(x, y, 3)),
      openingType: VisionOpeningType.door,
      attachedBoundaryId: 'boundary-$boundaryId',
    );
  }

  NormalizedPoint _jitter(double x, double y, double pxOffset) {
    // 항상 같은 방향으로 몇 px 어긋나게 만든다 — "정확한 값을 몰래 알고
    // 있다가 그대로 내놓는" 것이 아니라 정말 근사치임을 코드로 보장한다.
    return NormalizedPoint((x + pxOffset) / kImage2Width, (y - pxOffset) / kImage2Height);
  }
}
