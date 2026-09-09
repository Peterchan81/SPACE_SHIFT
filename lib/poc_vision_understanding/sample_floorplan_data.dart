import 'floorplan_semantic_model.dart';

/// 첨부된 실제 원본 평면도(이미지 A, 20.6m x 약 10.6~12m 규모의 4~5
/// 침실형 아파트 평면) 한 장을 "픽셀 검출기 없이" 사람이 도면 전체를
/// 보고 직접 의미 이해한 결과 — 이 POC의 핵심 증거물이다.
///
/// 좌표 단위는 미터(m)다. 도면에 실제로 인쇄된 치수 텍스트(20,600 /
/// 10,600 등)를 형태 비율의 참고 척도로만 썼다 — 이 숫자를 자동으로
/// 검증(OCR)하는 절차가 이 POC에는 없으므로 [scaleConfirmed]는 항상
/// false이고, 구간별 정확한 mm 대응은 확정하지 않는다(아래 [notes]
/// 참고). 이미지 B(GPT 재구성 CAD 참고 이미지)의 좌표/치수는 전혀
/// 사용하지 않았다 — 오직 이미지 A만 직접 읽었다.
final sampleUnderstanding = FloorplanUnderstanding(
  source: UnderstandingSource.manualVisionReading,
  scaleConfirmed: false,
  notes: const [
    '도면에 인쇄된 치수(20,600mm 등)는 전체 비율을 잡는 참고로만 썼다 — '
        '구간별 정확한 mm 경계는 이미지 판독만으로 확정하지 않았다.',
    '우측 상단 돌출부의 정확한 꺾임 위치, 좌측 상단의 작은 단차 등 세부 '
        '외곽선은 근사치다 — 존재 자체(비정형 외곽)는 확실하지만 좌표는 '
        '측량 수준이 아니다.',
    '중앙의 해칭 패턴(계단 또는 선반)은 계단으로 추정했다 — 표준 계단 '
        '기호(평행 발판 + 화살표)와 가장 가깝다.',
    '욕실 3곳의 정확한 경계는 근처 위생기구 아이콘(욕조/세면대/양변기) '
        '위치를 기준으로 추정했다.',
  ],
  floorDomain: const [
    Pt(0, 0),
    Pt(14.2, 0),
    Pt(14.2, -1.2),
    Pt(20.6, -1.2),
    Pt(20.6, 3.5),
    Pt(18.6, 3.5),
    Pt(18.6, 7.0),
    Pt(20.6, 7.0),
    Pt(20.6, 10.0),
    Pt(9.8, 10.0),
    Pt(9.8, 10.8),
    Pt(6.2, 10.8),
    Pt(6.2, 10.0),
    Pt(0, 10.0),
  ],
  spaces: const [
    SemanticSpace(
      id: 'space-bedroom-1',
      name: '침실',
      polygon: [Pt(0, 0), Pt(4.2, 0), Pt(4.2, 3.6), Pt(0, 3.6)],
      confidence: 0.8,
    ),
    SemanticSpace(
      id: 'space-dressroom',
      name: '드레스룸',
      polygon: [Pt(4.2, 0), Pt(6.0, 0), Pt(6.0, 3.0), Pt(4.2, 3.0)],
      confidence: 0.7,
    ),
    SemanticSpace(
      id: 'space-utility',
      name: '다용도실',
      polygon: [Pt(0, 3.6), Pt(4.2, 3.6), Pt(4.2, 6.2), Pt(0, 6.2)],
      confidence: 0.7,
    ),
    SemanticSpace(
      id: 'space-bath-a',
      name: '욕실',
      polygon: [Pt(4.2, 3.0), Pt(6.0, 3.0), Pt(6.0, 6.2), Pt(4.2, 6.2)],
      confidence: 0.6,
    ),
    SemanticSpace(
      id: 'space-stair',
      name: null,
      polygon: [Pt(6.0, 1.2), Pt(9.0, 1.2), Pt(9.0, 4.5), Pt(6.0, 4.5)],
      confidence: 0.5,
    ),
    SemanticSpace(
      id: 'space-bath-b',
      name: '욕실',
      polygon: [Pt(6.0, 4.5), Pt(9.0, 4.5), Pt(9.0, 6.2), Pt(6.0, 6.2)],
      confidence: 0.6,
    ),
    SemanticSpace(
      id: 'space-entrance',
      name: '현관',
      polygon: [Pt(9.0, 1.2), Pt(11.8, 1.2), Pt(11.8, 4.5), Pt(9.0, 4.5)],
      confidence: 0.7,
    ),
    SemanticSpace(
      id: 'space-bath-c',
      name: '욕실',
      polygon: [Pt(11.8, 0), Pt(14.2, 0), Pt(14.2, 3.0), Pt(11.8, 3.0)],
      confidence: 0.55,
    ),
    SemanticSpace(
      id: 'space-living',
      name: '거실',
      polygon: [Pt(0, 6.2), Pt(9.0, 6.2), Pt(9.0, 10.0), Pt(0, 10.0)],
      confidence: 0.8,
    ),
    SemanticSpace(
      id: 'space-kitchen',
      name: '주방 및 식당',
      polygon: [
        Pt(9.0, 6.2),
        Pt(14.2, 6.2),
        Pt(14.2, 10.0),
        Pt(9.8, 10.0),
        Pt(9.8, 10.8),
        Pt(6.2, 10.8),
        Pt(6.2, 10.0),
        Pt(9.0, 10.0),
      ],
      confidence: 0.75,
    ),
    SemanticSpace(
      id: 'space-bedroom-2',
      name: '침실',
      polygon: [
        Pt(14.2, 0),
        Pt(14.2, -1.2),
        Pt(20.6, -1.2),
        Pt(20.6, 3.5),
        Pt(18.6, 3.5),
        Pt(18.6, 5.6),
        Pt(14.2, 5.6),
      ],
      confidence: 0.75,
    ),
    SemanticSpace(
      id: 'space-corridor',
      name: null,
      polygon: [Pt(14.2, 5.6), Pt(18.6, 5.6), Pt(18.6, 7.0), Pt(14.2, 7.0)],
      confidence: 0.45,
    ),
    SemanticSpace(
      id: 'space-bedroom-3',
      name: '침실',
      polygon: [Pt(14.2, 7.0), Pt(20.6, 7.0), Pt(20.6, 10.0), Pt(14.2, 10.0)],
      confidence: 0.75,
    ),
  ],
  boundaries: const [
    // 대표적인 경계만 명시적으로 표현한다(POC 범위) — 나머지 SPACE 외곽선은
    // 렌더러가 인접 SPACE 판정으로 자동 보완한다.
    SemanticBoundary(
      id: 'b-bedroom1-utility',
      type: BoundaryType.interiorWall,
      geometry: [Pt(0, 3.6), Pt(4.2, 3.6)],
      adjacentSpaceIds: ['space-bedroom-1', 'space-utility'],
    ),
    SemanticBoundary(
      id: 'b-utility-living',
      type: BoundaryType.interiorWall,
      geometry: [Pt(0, 6.2), Pt(4.2, 6.2)],
      adjacentSpaceIds: ['space-utility', 'space-living'],
    ),
    SemanticBoundary(
      id: 'b-living-kitchen',
      type: BoundaryType.virtual,
      geometry: [Pt(9.0, 6.2), Pt(9.0, 10.0)],
      adjacentSpaceIds: ['space-living', 'space-kitchen'],
    ),
    SemanticBoundary(
      id: 'b-stair-entrance',
      type: BoundaryType.interiorWall,
      geometry: [Pt(9.0, 1.2), Pt(9.0, 4.5)],
      adjacentSpaceIds: ['space-stair', 'space-entrance'],
    ),
    SemanticBoundary(
      id: 'b-bedroom2-corridor',
      type: BoundaryType.interiorWall,
      geometry: [Pt(14.2, 5.6), Pt(18.6, 5.6)],
      adjacentSpaceIds: ['space-bedroom-2', 'space-corridor'],
    ),
    SemanticBoundary(
      id: 'b-corridor-bedroom3',
      type: BoundaryType.interiorWall,
      geometry: [Pt(14.2, 7.0), Pt(18.6, 7.0)],
      adjacentSpaceIds: ['space-corridor', 'space-bedroom-3'],
    ),
  ],
  openings: const [
    SemanticOpening(
      id: 'door-utility',
      kind: OpeningKind.door,
      boundaryId: 'b-bedroom1-utility',
      geometry: Pt(3.0, 3.6),
    ),
    SemanticOpening(
      id: 'door-entrance-corridor',
      kind: OpeningKind.door,
      boundaryId: 'b-stair-entrance',
      geometry: Pt(9.0, 3.0),
    ),
    SemanticOpening(
      id: 'opening-living-kitchen',
      kind: OpeningKind.openPassage,
      boundaryId: 'b-living-kitchen',
      geometry: Pt(9.0, 8.0),
    ),
    SemanticOpening(
      id: 'door-bedroom2',
      kind: OpeningKind.door,
      boundaryId: 'b-bedroom2-corridor',
      geometry: Pt(16.0, 5.6),
    ),
    SemanticOpening(
      id: 'door-bedroom3',
      kind: OpeningKind.door,
      boundaryId: 'b-corridor-bedroom3',
      geometry: Pt(16.0, 7.0),
    ),
    SemanticOpening(
      id: 'window-bedroom-2',
      kind: OpeningKind.window,
      boundaryId: 'b-bedroom2-corridor',
      geometry: Pt(17.4, -1.2),
    ),
  ],
  structuralObjects: const [
    SemanticStructuralObject(
      id: 'stair-1',
      kind: StructuralObjectKind.stair,
      polygon: [Pt(6.0, 1.2), Pt(9.0, 1.2), Pt(9.0, 4.5), Pt(6.0, 4.5)],
    ),
  ],
  nonStructuralObjects: const [
    SemanticNonStructuralObject(
      id: 'closet-top',
      kind: NonStructuralObjectKind.furniture,
      polygon: [Pt(6.0, -0.3), Pt(9.5, -0.3), Pt(9.5, 1.2), Pt(6.0, 1.2)],
      containingSpaceId: 'space-stair',
    ),
    SemanticNonStructuralObject(
      id: 'tub-bath-a',
      kind: NonStructuralObjectKind.fixture,
      polygon: [Pt(4.5, 3.3), Pt(5.8, 3.3), Pt(5.8, 4.3), Pt(4.5, 4.3)],
      containingSpaceId: 'space-bath-a',
    ),
  ],
);
