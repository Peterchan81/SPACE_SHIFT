import '../../models/vision_understanding.dart';

/// SPACE SHIFT — Image 2 GPT Direct CAD Geometry Proposal Benchmark (v3).
///
/// v2(e2e_v2, commit 9596dc9) 대비 달라진 점: 이번에는 GPT가 실제
/// "이미지 2" 원본(443x301px)을 보고 직접 제안한 pixel 단위 구조 축
/// (major vertical/horizontal axes, corner zone 설명)을 1차 authority로
/// 삼아 좌표를 다시 잡았다 — v2는 손으로 어림한 비율이었고, 특히
/// 안방|거실 벽 위치가 실제보다 한참 왼쪽(x≈0.24)에 있었다. GPT가 준
/// 축(V04 ≈ x156-161px → 0.358)을 반영하면 실제 사진과 훨씬 가깝다.
///
/// 이 파일이 쓰는 값(XA..XH, YA..YG 등)은 GPT가 준 pixel 범위의 중앙값을
/// 정규화(443/301으로 나눔)한 것이다 — GPT가 숫자로 주지 않은 세부
/// (부부거실 자체의 작은 추가 돌출, 현관/욕실1 사이 미세한 return 등)는
/// 이번 라운드에서 단순화했고, 이는 정직한 한계로 남긴다.
///
/// 이 proposal 자체는 여전히 "제안"이다 — 최종 좌표는
/// [VisionGuidedSpatialModelBuilder](5499365에서 만든 기존 orchestrator,
/// 재사용)가 실제 픽셀에서 다시 확인·조정한다.
VisionUnderstanding buildImage2VisionProposalV3() {
  NormalizedPoint p(double x, double y) => NormalizedPoint(x, y);

  // GPT가 준 major axes의 중앙값(정규화). 443x301px 기준.
  const xa = 0.0587; // V01 far-left exterior
  const xb = 0.1490; // V02 부부거실 | 드레스룸+욕실2
  const xc = 0.2585; // V03 드레스룸+욕실2 | 주방식당
  const xd = 0.3578; // V04 안방 | 거실
  const xe = 0.5982; // V05 주방식당 | 펜트리+욕실1, 거실 | 침실2
  const xf = 0.7032; // V06 펜트리+욕실1 | 현관, 침실2 | 침실1
  const xh = 0.9526; // V08 far-right exterior
  const xBed1 = 0.86; // 침실1 우측 계단(현관보다 안쪽) — GPT 정성 설명 기반 근사치

  const ya = 0.0382; // H01 주방식당/펜트리/욕실1/현관 상단(주 파사드)
  const yb = 0.1694; // H02 부부거실/드레스룸/욕실2 상단(recessed facade)
  const yc = 0.2259; // H03 드레스룸 | 욕실2 내부 분할
  const yd = 0.2874; // H04 펜트리 | 욕실1 내부 분할
  const yBalTop = 0.023; // 발코니 돌출 상단(GPT 수치 없음, 근사치)
  const yMid = 0.5731; // H06 상단열 | 하단열 경계(major upper/lower transition)
  const yg = 0.9302; // H07 남측 하단 외벽

  const xBalL = 0.55, xBalR = 0.60; // 발코니 좌우(GPT 수치 없음, 근사치)
  const xMechL = 0.01; // 실외기실 좌측 돌출(GPT 수치 없음, 근사치)
  const yMechT = 0.65, yMechB = 0.75;

  final floorDomainPolygon = [
    p(xa, yb),
    p(xc, yb),
    p(xc, ya),
    p(xBalL, ya),
    p(xBalL, yBalTop),
    p(xBalR, yBalTop),
    p(xBalR, ya),
    p(xh, ya),
    p(xh, yMid),
    p(xBed1, yMid),
    p(xBed1, yg),
    p(xa, yg),
    p(xa, yMechB),
    p(xMechL, yMechB),
    p(xMechL, yMechT),
    p(xa, yMechT),
  ];

  final spaces = [
    VisionSpace(
      id: 'space-masterLiving',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.boundingBox(minX: xa, minY: yb, maxX: xb, maxY: yMid),
      label: '부부거실',
      semanticType: VisionSpaceSemanticType.living,
      adjacentSpaceIds: const ['space-dressRoom', 'space-bath2', 'space-masterBedroom'],
      notes: const ['GPT가 언급한 좌측 상단 추가 돌출부(C_EXT_03/04)는 이번 라운드에서 단순화함'],
    ),
    VisionSpace(
      id: 'space-dressRoom',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.boundingBox(minX: xb, minY: yb, maxX: xc, maxY: yc),
      label: '드레스룸',
      semanticType: VisionSpaceSemanticType.utility,
      adjacentSpaceIds: const ['space-bath2', 'space-masterLiving'],
    ),
    VisionSpace(
      id: 'space-bath2',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.boundingBox(minX: xb, minY: yc, maxX: xc, maxY: yMid),
      label: '욕실2',
      semanticType: VisionSpaceSemanticType.bathroom,
      adjacentSpaceIds: const ['space-dressRoom', 'space-masterLiving'],
    ),
    VisionSpace(
      id: 'space-kitchenDining',
      confidence: VisionConfidence.high,
      geometryHint: GeometryHint.boundingBox(minX: xc, minY: ya, maxX: xe, maxY: yMid),
      label: '주방/식당',
      semanticType: VisionSpaceSemanticType.kitchen,
      adjacentSpaceIds: const ['space-balcony', 'space-pantry', 'space-living', 'space-bedroom1'],
    ),
    VisionSpace(
      id: 'space-balcony',
      confidence: VisionConfidence.low,
      geometryHint: GeometryHint.boundingBox(minX: xBalL, minY: yBalTop, maxX: xBalR, maxY: ya),
      label: '발코니',
      semanticType: VisionSpaceSemanticType.balcony,
      adjacentSpaceIds: const ['space-kitchenDining'],
      notes: const ['GPT는 존재를 HIGH confidence로 확인했으나 정확한 좌우 폭은 수치로 주지 않음 — 근사치'],
    ),
    VisionSpace(
      id: 'space-pantry',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.boundingBox(minX: xe, minY: ya, maxX: xf, maxY: yd),
      label: '펜트리',
      semanticType: VisionSpaceSemanticType.pantry,
      adjacentSpaceIds: const ['space-kitchenDining', 'space-bath1'],
    ),
    VisionSpace(
      id: 'space-bath1',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.boundingBox(minX: xe, minY: yd, maxX: xf, maxY: yMid),
      label: '욕실1',
      semanticType: VisionSpaceSemanticType.bathroom,
      adjacentSpaceIds: const ['space-pantry', 'space-bedroom1'],
    ),
    VisionSpace(
      id: 'space-entrance',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.boundingBox(minX: xf, minY: ya, maxX: xh, maxY: yMid),
      label: '현관',
      semanticType: VisionSpaceSemanticType.entrance,
      adjacentSpaceIds: const ['space-bath1', 'space-bedroom1'],
      notes: const ['GPT가 언급한 entrance/bath local return(V07)의 세부 단은 이번 라운드에서 단순화함'],
    ),
    VisionSpace(
      id: 'space-masterBedroom',
      confidence: VisionConfidence.high,
      geometryHint: GeometryHint.boundingBox(minX: xa, minY: yMid, maxX: xd, maxY: yg),
      label: '안방',
      semanticType: VisionSpaceSemanticType.bedroomMaster,
      adjacentSpaceIds: const ['space-masterLiving', 'space-living', 'space-mechanical'],
    ),
    VisionSpace(
      id: 'space-mechanical',
      confidence: VisionConfidence.low,
      geometryHint: GeometryHint.boundingBox(minX: xMechL, minY: yMechT, maxX: xa, maxY: yMechB),
      label: '실외기실',
      semanticType: VisionSpaceSemanticType.mechanicalRoom,
      adjacentSpaceIds: const ['space-masterBedroom'],
      notes: const ['GPT semantic confidence는 HIGH — 삭제하지 않고 유지, geometry만 LOW'],
    ),
    VisionSpace(
      id: 'space-living',
      confidence: VisionConfidence.high,
      geometryHint: GeometryHint.boundingBox(minX: xd, minY: yMid, maxX: xe, maxY: yg),
      label: '거실',
      semanticType: VisionSpaceSemanticType.living,
      adjacentSpaceIds: const ['space-kitchenDining', 'space-masterBedroom', 'space-bedroom2'],
    ),
    VisionSpace(
      id: 'space-bedroom2',
      confidence: VisionConfidence.high,
      geometryHint: GeometryHint.boundingBox(minX: xe, minY: yMid, maxX: xf, maxY: yg),
      label: '침실2',
      semanticType: VisionSpaceSemanticType.bedroom,
      adjacentSpaceIds: const ['space-living', 'space-bedroom1'],
    ),
    VisionSpace(
      id: 'space-bedroom1',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.boundingBox(minX: xf, minY: yMid, maxX: xBed1, maxY: yg),
      label: '침실1',
      semanticType: VisionSpaceSemanticType.bedroom,
      adjacentSpaceIds: const ['space-bedroom2', 'space-bath1', 'space-entrance', 'space-kitchenDining'],
      notes: const ['우측 계단(xBed1) 정확한 위치는 GPT 정성 설명 기반 근사치'],
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
    // 외곽 — floorDomainPolygon의 16개 변.
    wall('ext-1', xa, yb, xc, yb, VisionBoundaryType.exteriorWall),
    wall('ext-2', xc, yb, xc, ya, VisionBoundaryType.exteriorWall),
    wall('ext-3', xc, ya, xBalL, ya, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.high),
    wall('ext-4', xBalL, ya, xBalL, yBalTop, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-5', xBalL, yBalTop, xBalR, yBalTop, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-6', xBalR, yBalTop, xBalR, ya, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-7', xBalR, ya, xh, ya, VisionBoundaryType.exteriorWall),
    wall('ext-8', xh, ya, xh, yMid, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.high),
    wall('ext-8b', xh, yMid, xBed1, yMid, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-8c', xBed1, yMid, xBed1, yg, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-9', xBed1, yg, xa, yg, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.high),
    wall('ext-10', xa, yg, xa, yMechB, VisionBoundaryType.exteriorWall),
    wall('ext-11', xa, yMechB, xMechL, yMechB, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-12', xMechL, yMechB, xMechL, yMechT, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-13', xMechL, yMechT, xa, yMechT, VisionBoundaryType.exteriorWall, confidence: VisionConfidence.low),
    wall('ext-14', xa, yMechT, xa, yb, VisionBoundaryType.exteriorWall),

    // 내벽.
    wall('wall-int-masterLiving-dress', xb, yb, xb, yMid, VisionBoundaryType.interiorWall, confidence: VisionConfidence.high),
    wall('wall-int-dress-bath2', xb, yc, xc, yc, VisionBoundaryType.interiorWall),
    wall('wall-int-dress-kitchen', xc, yb, xc, yMid, VisionBoundaryType.interiorWall, confidence: VisionConfidence.high),
    wall('wall-int-kitchen-pantry', xe, ya, xe, yMid, VisionBoundaryType.interiorWall, confidence: VisionConfidence.high),
    wall('wall-int-pantry-bath1', xe, yd, xf, yd, VisionBoundaryType.interiorWall),
    wall('wall-int-bath1-entrance', xf, ya, xf, yMid, VisionBoundaryType.interiorWall),
    wall('wall-int-mid-row', xa, yMid, xBed1, yMid, VisionBoundaryType.interiorWall, confidence: VisionConfidence.high,
        notes: const ['GPT: 하나의 연속된 벽이 아니라 여러 구간+열림+return의 집합 — 이번 라운드는 단일 세그먼트로 단순화']),
    wall('wall-int-master-living-split', xd, yMid, xd, yg, VisionBoundaryType.interiorWall, confidence: VisionConfidence.high),
    wall('wall-int-living-bed2', xe, yMid, xe, yg, VisionBoundaryType.interiorWall, confidence: VisionConfidence.high),
    wall('wall-int-bed2-bed1', xf, yMid, xf, yg, VisionBoundaryType.interiorWall, confidence: VisionConfidence.high),
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
    // v3: 부부거실|안방 연결은 세로벽이 아니라 상/하단 경계
    // (wall-int-mid-row)의 gap이다(GPT: UPPER_LOWER_BOUNDARY는 여러
    // door/opening을 포함) — v2에서 잘못 배치했던 것을 수정.
    opening('door-dress-master', 'wall-int-mid-row', (xa + xb) / 2, yMid, VisionOpeningType.door,
        const ['space-masterLiving', 'space-masterBedroom'], confidence: VisionConfidence.low),
    opening('door-bath2', 'wall-int-dress-bath2', (xb + xc) / 2, yc, VisionOpeningType.door,
        const ['space-dressRoom', 'space-bath2']),
    opening('door-pantry', 'wall-int-kitchen-pantry', xe, (ya + yd) / 2, VisionOpeningType.door,
        const ['space-kitchenDining', 'space-pantry']),
    opening('door-bath1', 'wall-int-pantry-bath1', (xe + xf) / 2, yd, VisionOpeningType.door,
        const ['space-pantry', 'space-bath1']),
    opening('door-front', 'ext-8', xh, ya + 0.03, VisionOpeningType.door, const ['space-entrance']),
    opening('door-master-living', 'wall-int-master-living-split', xd, yMid + 0.1, VisionOpeningType.door,
        const ['space-masterBedroom', 'space-living']),
    opening('door-living-bed2', 'wall-int-living-bed2', xe, yMid + 0.15, VisionOpeningType.door,
        const ['space-living', 'space-bedroom2']),
    opening('door-bed2-bed1', 'wall-int-bed2-bed1', xf, yMid + 0.1, VisionOpeningType.door,
        const ['space-bedroom2', 'space-bedroom1']),
    opening('opening-kitchen-living', 'wall-int-mid-row', (xd + xe) / 2, yMid, VisionOpeningType.openPassage,
        const ['space-kitchenDining', 'space-living'], confidence: VisionConfidence.low),
    // Windows.
    opening('window-dress-top', 'ext-1', (xb + xc) / 2, yb, VisionOpeningType.window, const ['space-dressRoom']),
    opening('window-kitchen-top', 'ext-3', (xc + xBalL) / 2, ya, VisionOpeningType.window, const ['space-kitchenDining']),
    opening('window-balcony-rail', 'ext-5', (xBalL + xBalR) / 2, yBalTop, VisionOpeningType.window,
        const ['space-balcony'], confidence: VisionConfidence.low),
    opening('window-south-1', 'ext-9', (xa + xd) / 2 - 0.08, yg, VisionOpeningType.window, const ['space-masterBedroom']),
    opening('window-south-2', 'ext-9', (xd + xe) / 2, yg, VisionOpeningType.window, const ['space-living']),
    opening('window-south-3', 'ext-9', (xe + xf) / 2, yg, VisionOpeningType.window, const ['space-bedroom2']),
    opening('window-south-4', 'ext-9', (xf + xBed1) / 2, yg, VisionOpeningType.window, const ['space-bedroom1']),
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
    object('obj-toilet-bath1', VisionObjectType.toilet, 'space-bath1', xe + 0.02, yMid - 0.05, xe + 0.06, yMid - 0.02),
    object('obj-sink-bath1', VisionObjectType.sink, 'space-bath1', xf - 0.04, yd + 0.01, xf - 0.01, yd + 0.04),
    object('obj-toilet-bath2', VisionObjectType.toilet, 'space-bath2', xb + 0.02, yMid - 0.06, xb + 0.06, yMid - 0.03),
    object('obj-sink-bath2', VisionObjectType.sink, 'space-bath2', xc - 0.05, yc + 0.01, xc - 0.02, yc + 0.04,
        confidence: VisionConfidence.low),
    object('obj-shoe-cabinet-entrance', VisionObjectType.cabinet, 'space-entrance', xh - 0.05, ya + 0.01, xh - 0.01, ya + 0.05,
        confidence: VisionConfidence.low),
  ];

  return VisionUnderstanding(
    floorDomain: VisionFloorDomain(
      id: 'floor-domain',
      confidence: VisionConfidence.high,
      geometryHint: GeometryHint.polygon(floorDomainPolygon),
      notes: const [
        'GPT가 준 major axes(V01~V08, H01~H07)의 중앙값을 1차 authority로 사용함',
        '현관/욕실1 사이 미세 return, 부부거실 자체 추가 돌출은 이번 라운드에서 단순화함',
      ],
    ),
    spaces: spaces,
    boundaries: boundaries,
    openings: openings,
    objects: objects,
    scaleConfirmed: false,
    notes: const [
      '이 proposal은 GPT가 실제 이미지 2 원본을 보고 직접 제안한 pixel 단위 구조축을 기반으로 만들었다.',
      '인쇄된 치수가 없어 scale은 항상 unconfirmed로 유지된다.',
    ],
  );
}
