import '../../models/vision_understanding.dart';

/// SPACE SHIFT — Image 2 AI → Real CAD End-to-End POC.
///
/// 이 파일은 SS pixel detector나 합성 이미지가 아니라, **실제 "이미지
/// 2" 원본을 직접 보고** 이전 turn(Claude Vision Geometry Benchmark)에서
/// 수행한 실제 분석 결과를 [VisionUnderstanding] 스키마로 옮긴 것이다 —
/// 사용자 지시("GPT Vision 분석 결과를 Vision CAD Proposal fixture로
/// 사용해도 된다")에 따른 것이며, 새로 지어낸 좌표가 아니다.
///
/// 정직한 한계:
/// - 그 turn에서 처음 옮겨적은 FloorDomain polygon은 자기교차 + 좌측
///   상단 구역(드레스룸/부부거실/욕실2) 누락이 있는 결함이 있었다(같은
///   벤치마크 turn이 이미 "재대조 필요"로 명시했던 바로 그 불확실성이
///   실제로 드러난 것). 이번 파일에서 폐곡선이 자기교차하지 않고 실제
///   13개 공간을 전부 감싸도록 좌표를 다시 정리했다 — 의미(공간
///   종류/인접관계)는 그대로이고, 오직 "하나의 단순 폐곡선으로 만든다"
///   는 순수 기하 정합성만 다시 잡았다.
/// - 외곽/벽/문/창의 정확한 픽셀 좌표는 여전히 근사치이며 confidence는
///   대부분 MEDIUM, 일부(부부거실 분할선/현관 경계/실외기실 상단)는
///   LOW다 — 이 proposal 자체는 최종 CAD 좌표가 아니다.
VisionUnderstanding buildImage2VisionProposal() {
  NormalizedPoint p(double x, double y) => NormalizedPoint(x, y);
  List<NormalizedPoint> rect(double x1, double y1, double x2, double y2) =>
      [p(x1, y1), p(x2, y1), p(x2, y2), p(x1, y2)];

  // 건물 외곽 — 자기교차 없는 단일 폐곡선. 발코니(상단)와 실외기실
  // (좌측)의 두 돌출부를 포함한다.
  const floorDomainPolygon = [
    NormalizedPoint(0.04, 0.10),
    NormalizedPoint(0.24, 0.10),
    NormalizedPoint(0.24, 0.04),
    NormalizedPoint(0.63, 0.04),
    NormalizedPoint(0.63, 0.02),
    NormalizedPoint(0.68, 0.02),
    NormalizedPoint(0.68, 0.04),
    NormalizedPoint(0.97, 0.04),
    NormalizedPoint(0.97, 0.95),
    NormalizedPoint(0.04, 0.95),
    NormalizedPoint(0.04, 0.73),
    NormalizedPoint(-0.03, 0.73),
    NormalizedPoint(-0.03, 0.60),
    NormalizedPoint(0.04, 0.60),
  ];

  final spaces = [
    VisionSpace(
      id: 'space-masterLiving',
      confidence: VisionConfidence.low,
      geometryHint: GeometryHint.polygon(rect(0.04, 0.10, 0.11, 0.34)),
      label: '부부거실',
      semanticType: VisionSpaceSemanticType.living,
      adjacentSpaceIds: const ['space-dressRoom', 'space-bath2', 'space-masterBedroom'],
      notes: const ['드레스룸/욕실2와의 정확한 분리선 확신 낮음'],
    ),
    VisionSpace(
      id: 'space-dressRoom',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.11, 0.10, 0.24, 0.20)),
      label: '드레스룸',
      semanticType: VisionSpaceSemanticType.utility,
      adjacentSpaceIds: const ['space-bath2', 'space-masterLiving'],
    ),
    VisionSpace(
      id: 'space-bath2',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.11, 0.20, 0.24, 0.34)),
      label: '욕실2',
      semanticType: VisionSpaceSemanticType.bathroom,
      adjacentSpaceIds: const ['space-dressRoom', 'space-masterLiving'],
    ),
    VisionSpace(
      id: 'space-kitchenDining',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.24, 0.04, 0.68, 0.34)),
      label: '주방/식당',
      semanticType: VisionSpaceSemanticType.kitchen,
      adjacentSpaceIds: const ['space-balcony', 'space-pantry', 'space-living', 'space-bedroom1'],
    ),
    VisionSpace(
      id: 'space-balcony',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.63, 0.02, 0.68, 0.04)),
      label: '발코니',
      semanticType: VisionSpaceSemanticType.balcony,
      adjacentSpaceIds: const ['space-kitchenDining'],
      notes: const ['돌출 폭/깊이는 근사치'],
    ),
    VisionSpace(
      id: 'space-pantry',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.68, 0.04, 0.80, 0.20)),
      label: '펜트리',
      semanticType: VisionSpaceSemanticType.pantry,
      adjacentSpaceIds: const ['space-kitchenDining', 'space-bath1'],
    ),
    VisionSpace(
      id: 'space-bath1',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.68, 0.20, 0.80, 0.34)),
      label: '욕실1',
      semanticType: VisionSpaceSemanticType.bathroom,
      adjacentSpaceIds: const ['space-pantry', 'space-bedroom1'],
    ),
    VisionSpace(
      id: 'space-entrance',
      confidence: VisionConfidence.low,
      geometryHint: GeometryHint.polygon(rect(0.80, 0.04, 0.97, 0.34)),
      label: '현관',
      semanticType: VisionSpaceSemanticType.entrance,
      adjacentSpaceIds: const ['space-bath1', 'space-bedroom1'],
      notes: const ['펜트리/욕실1과의 실제 단(段) 형태 확신 낮음'],
    ),
    VisionSpace(
      id: 'space-masterBedroom',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.04, 0.34, 0.24, 0.95)),
      label: '안방',
      semanticType: VisionSpaceSemanticType.bedroomMaster,
      adjacentSpaceIds: const ['space-masterLiving', 'space-living', 'space-mechanical'],
    ),
    VisionSpace(
      id: 'space-mechanical',
      confidence: VisionConfidence.low,
      geometryHint: GeometryHint.polygon(rect(-0.03, 0.60, 0.04, 0.73)),
      label: '실외기실',
      semanticType: VisionSpaceSemanticType.mechanicalRoom,
      adjacentSpaceIds: const ['space-masterBedroom'],
      notes: const ['위쪽이 벽인지 완전 개방인지 확신 낮음'],
    ),
    VisionSpace(
      id: 'space-living',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.24, 0.34, 0.44, 0.95)),
      label: '거실',
      semanticType: VisionSpaceSemanticType.living,
      adjacentSpaceIds: const ['space-kitchenDining', 'space-masterBedroom', 'space-bedroom2'],
    ),
    VisionSpace(
      id: 'space-bedroom2',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.44, 0.34, 0.58, 0.95)),
      label: '침실2',
      semanticType: VisionSpaceSemanticType.bedroom,
      adjacentSpaceIds: const ['space-living', 'space-bedroom1'],
    ),
    VisionSpace(
      id: 'space-bedroom1',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(rect(0.58, 0.34, 0.97, 0.95)),
      label: '침실1',
      semanticType: VisionSpaceSemanticType.bedroom,
      adjacentSpaceIds: const ['space-bedroom2', 'space-bath1', 'space-entrance', 'space-kitchenDining'],
    ),
  ];

  VisionBoundary wall(
    String id,
    double x1,
    double y1,
    double x2,
    double y2,
    VisionBoundaryType type, {
    VisionConfidence confidence = VisionConfidence.medium,
    List<String> notes = const [],
  }) {
    return VisionBoundary(
      id: id,
      confidence: confidence,
      geometryHint: GeometryHint.segment(p(x1, y1), p(x2, y2)),
      boundaryType: type,
      notes: notes,
    );
  }

  final boundaries = [
    // 외곽 — floorDomainPolygon의 14개 변을 그대로 잇는다.
    wall('ext-1', 0.04, 0.10, 0.24, 0.10, VisionBoundaryType.exteriorWall),
    wall('ext-2', 0.24, 0.10, 0.24, 0.04, VisionBoundaryType.exteriorWall),
    wall('ext-3', 0.24, 0.04, 0.63, 0.04, VisionBoundaryType.exteriorWall),
    wall('ext-4', 0.63, 0.04, 0.63, 0.02, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-5', 0.63, 0.02, 0.68, 0.02, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-6', 0.68, 0.02, 0.68, 0.04, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-7', 0.68, 0.04, 0.97, 0.04, VisionBoundaryType.exteriorWall),
    wall('ext-8', 0.97, 0.04, 0.97, 0.95, VisionBoundaryType.exteriorWall),
    wall('ext-9', 0.97, 0.95, 0.04, 0.95, VisionBoundaryType.exteriorWall),
    wall('ext-10', 0.04, 0.95, 0.04, 0.73, VisionBoundaryType.exteriorWall),
    wall('ext-11', 0.04, 0.73, -0.03, 0.73, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-12', -0.03, 0.73, -0.03, 0.60, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-13', -0.03, 0.60, 0.04, 0.60, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-14', 0.04, 0.60, 0.04, 0.10, VisionBoundaryType.exteriorWall),

    // 내벽.
    wall('wall-int-masterLiving-dress', 0.11, 0.10, 0.11, 0.34, VisionBoundaryType.interiorWall),
    wall('wall-int-dress-bath2', 0.11, 0.20, 0.24, 0.20, VisionBoundaryType.interiorWall, confidence: VisionConfidence.low),
    wall('wall-int-dress-kitchen', 0.24, 0.04, 0.24, 0.34, VisionBoundaryType.interiorWall),
    wall('wall-int-kitchen-pantry', 0.68, 0.04, 0.68, 0.34, VisionBoundaryType.interiorWall),
    wall('wall-int-pantry-bath1', 0.68, 0.20, 0.80, 0.20, VisionBoundaryType.interiorWall),
    wall('wall-int-bath1-entrance', 0.80, 0.04, 0.80, 0.34, VisionBoundaryType.interiorWall, confidence: VisionConfidence.low),
    wall('wall-int-mid-row', 0.04, 0.34, 0.97, 0.34, VisionBoundaryType.interiorWall),
    wall('wall-int-master-living-split', 0.24, 0.34, 0.24, 0.95, VisionBoundaryType.interiorWall),
    wall('wall-int-living-bed2', 0.44, 0.34, 0.44, 0.95, VisionBoundaryType.interiorWall),
    wall('wall-int-bed2-bed1', 0.58, 0.34, 0.58, 0.95, VisionBoundaryType.interiorWall),
  ];

  VisionOpening opening(
    String id,
    String boundaryId,
    double x,
    double y,
    VisionOpeningType type,
    List<String> connects, {
    VisionConfidence confidence = VisionConfidence.medium,
  }) {
    return VisionOpening(
      id: id,
      confidence: confidence,
      geometryHint: GeometryHint.point(p(x, y)),
      openingType: type,
      attachedBoundaryId: boundaryId,
      connectedSpaceIds: connects,
    );
  }

  final openings = [
    opening('door-dress-master', 'wall-int-masterLiving-dress', 0.11, 0.30, VisionOpeningType.door,
        const ['space-masterLiving', 'space-masterBedroom'], confidence: VisionConfidence.low),
    opening('door-bath2', 'wall-int-dress-bath2', 0.16, 0.20, VisionOpeningType.door,
        const ['space-dressRoom', 'space-bath2']),
    opening('door-pantry', 'wall-int-kitchen-pantry', 0.68, 0.15, VisionOpeningType.door,
        const ['space-kitchenDining', 'space-pantry']),
    opening('door-bath1', 'wall-int-pantry-bath1', 0.74, 0.20, VisionOpeningType.door,
        const ['space-pantry', 'space-bath1']),
    opening('door-front', 'ext-8', 0.97, 0.06, VisionOpeningType.door, const ['space-entrance']),
    opening('door-master-living', 'wall-int-master-living-split', 0.24, 0.45, VisionOpeningType.door,
        const ['space-masterBedroom', 'space-living']),
    opening('door-living-bed2', 'wall-int-living-bed2', 0.44, 0.70, VisionOpeningType.door,
        const ['space-living', 'space-bedroom2']),
    opening('door-bed2-bed1', 'wall-int-bed2-bed1', 0.58, 0.65, VisionOpeningType.door,
        const ['space-bedroom2', 'space-bedroom1']),
    opening('opening-kitchen-living', 'wall-int-mid-row', 0.34, 0.34, VisionOpeningType.openPassage,
        const ['space-kitchenDining', 'space-living'], confidence: VisionConfidence.low),
    // Windows (VisionUnderstanding에는 별도 windows 목록이 없어 openings에
    // type=window로 포함한다 — 기존 스키마를 그대로 재사용).
    opening('window-dress-top', 'ext-1', 0.16, 0.10, VisionOpeningType.window, const ['space-dressRoom']),
    opening('window-kitchen-top', 'ext-3', 0.44, 0.04, VisionOpeningType.window, const ['space-kitchenDining']),
    opening('window-balcony-rail', 'ext-5', 0.655, 0.02, VisionOpeningType.window, const ['space-balcony'],
        confidence: VisionConfidence.low),
    opening('window-south-1', 'ext-9', 0.14, 0.95, VisionOpeningType.window, const ['space-masterBedroom']),
    opening('window-south-2', 'ext-9', 0.34, 0.95, VisionOpeningType.window, const ['space-living']),
    opening('window-south-3', 'ext-9', 0.51, 0.95, VisionOpeningType.window, const ['space-bedroom2']),
    opening('window-south-4', 'ext-9', 0.75, 0.95, VisionOpeningType.window, const ['space-bedroom1']),
  ];

  VisionObject object(String id, VisionObjectType type, String space, double x1, double y1, double x2, double y2,
      {VisionConfidence confidence = VisionConfidence.medium}) {
    return VisionObject(
      id: id,
      confidence: confidence,
      geometryHint: GeometryHint.boundingBox(minX: x1, minY: y1, maxX: x2, maxY: y2),
      objectType: type,
      containingSpaceId: space,
    );
  }

  final objects = [
    object('obj-toilet-bath1', VisionObjectType.toilet, 'space-bath1', 0.70, 0.30, 0.74, 0.33),
    object('obj-sink-bath1', VisionObjectType.sink, 'space-bath1', 0.76, 0.21, 0.79, 0.24),
    object('obj-toilet-bath2', VisionObjectType.toilet, 'space-bath2', 0.13, 0.31, 0.17, 0.33),
    object('obj-sink-bath2', VisionObjectType.sink, 'space-bath2', 0.20, 0.21, 0.23, 0.24,
        confidence: VisionConfidence.low),
    object('obj-shoe-cabinet-entrance', VisionObjectType.cabinet, 'space-entrance', 0.92, 0.05, 0.96, 0.09,
        confidence: VisionConfidence.low),
  ];

  return VisionUnderstanding(
    floorDomain: VisionFloorDomain(
      id: 'floor-domain',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.polygon(floorDomainPolygon),
      notes: const ['현관 앞 단 형태/발코니·실외기실 돌출 정확한 깊이는 근사치'],
    ),
    spaces: spaces,
    boundaries: boundaries,
    openings: openings,
    objects: objects,
    scaleConfirmed: false,
    notes: const [
      '이 proposal은 실제 "이미지 2" 원본을 직접 본 분석 결과이며, 합성 이미지가 아니다.',
      '인쇄된 치수가 없어 scale은 항상 unconfirmed로 유지된다.',
    ],
  );
}
