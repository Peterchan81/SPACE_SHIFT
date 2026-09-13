import 'package:flutter/foundation.dart';

import 'cad_floor_plan.dart';
import 'floor_plan_geometry.dart';
import 'space_scene_v2.dart' show SpaceObjectIdentityV2;

/// 중앙 캔버스가 평면도를 어떤 형태로 보여줄지 — CAD 변환 결과를
/// 기본으로 우선 표시하고(WO 6번), 원본 이미지 또는 둘 다(비교)로
/// 전환할 수 있다.
enum FloorPlanDisplayMode { cad, original, compare }

extension FloorPlanDisplayModeX on FloorPlanDisplayMode {
  String get label => switch (this) {
    FloorPlanDisplayMode.cad => 'CAD',
    FloorPlanDisplayMode.original => '원본',
    FloorPlanDisplayMode.compare => '비교',
  };
}

/// CANONICAL 2D CONFIRMATION → 3D PIPELINE WO §4 — "구조 확인/보정" 모드에서
/// 캔버스 탭 한 번이 어떤 편집으로 이어지는지 결정하는 도구. 정교한 CAD
/// 편집기가 목적이 아니므로 딱 이 4개만 둔다: 선택(기존 select/삭제
/// 흐름 그대로), 벽 추가(드래그 두 점), 문/창 추가(기존 벽 위 탭 한 번).
enum CadEditTool { select, addWall, addDoor, addWindow }

extension CadEditToolX on CadEditTool {
  String get label => switch (this) {
    CadEditTool.select => '선택',
    CadEditTool.addWall => '벽 추가',
    CadEditTool.addDoor => '문 추가',
    CadEditTool.addWindow => '창 추가',
  };
}

/// CAD 캔버스/오버레이가 필요로 하는 값들을 한 번에 묶어, 위젯 생성자
/// 파라미터가 지나치게 늘어나지 않게 한다. 화면(State)에서 만들어
/// [FloorPlanPreview]/[WorkspaceCanvas]에 그대로 전달한다.
@immutable
class CadWorkspaceState {
  const CadWorkspaceState({
    this.floorPlan,
    this.selectedObjectId,
    this.displayMode = FloorPlanDisplayMode.cad,
    this.debugOverlay = false,
    this.calibrating = false,
    this.calibrationWallId,
    this.calibrationStart,
    this.calibrationEnd,
    this.calibrationPixelLength,
    this.scale,
    this.ceilingHeightMm,
    this.generatedFloorPlanImageBytes,
    this.isGeneratingFloorPlanImage = false,
    this.selected3DObjectId,
    this.structureEditing = false,
    this.cadEditTool = CadEditTool.select,
    this.pendingWallStart,
    this.confirmedFloorPlan,
  });

  final CadFloorPlan? floorPlan;

  /// V1 AI-IMAGE FLOW WO — GPT가 원본 평면도 사진을 보고 새로 그려준
  /// "깨끗한 CAD 스타일 2D 평면도" 이미지 그 자체(좌표/폴리곤이 아니라
  /// PNG/JPEG 픽셀). 중앙 화면은 이제 이 이미지를 [FloorPlanDisplayMode.cad]
  /// 슬롯에 그대로 보여준다 — [floorPlan](벽/공간 polygon)은 여전히 내부적
  /// 으로 3D 아이소 생성에만 쓰이고, 화면에 CAD 오버레이/공간 번호/좌표로
  /// 노출되지 않는다. null이면 아직 생성 전이거나 생성에 실패한 것 —
  /// 이 경우 화면은 원본 사진을 그대로 보여준다(가짜로 CAD 결과를 만들지
  /// 않는다).
  final Uint8List? generatedFloorPlanImageBytes;

  /// true인 동안 "AI 평면도 생성 중" 상태를 보여준다.
  final bool isGeneratingFloorPlanImage;
  final String? selectedObjectId;

  /// WO092 §5 — 실시간 3D(아이소/투시)에서 사용자가 탭해 선택한 벽/바닥/
  /// 천장의 [SpaceObjectIdentityV2.objectId](예: `wall:wall-3`,
  /// `floor:room-1`, `ceiling:room-1`). 2D CAD geometry 선택([selectedObjectId],
  /// 원본 [CadWall.id]/[CadRoom.id]를 그대로 씀)과는 다른 값 공간이라
  /// 완전히 별개의 필드로 둔다 — 같은 방(room) id가 "바닥"과 "천장" 두
  /// 선택으로 동시에 존재할 수 있어 원본 id 하나로는 구분할 수 없기
  /// 때문이다.
  final String? selected3DObjectId;
  final FloorPlanDisplayMode displayMode;
  final bool debugOverlay;

  /// true면 "치수 보정" 드래그 선택 모드 — geometry 선택 대신 캔버스
  /// drag로 벽 구간을 고른다(실기 FAIL 재수정 WO 11/12번).
  final bool calibrating;

  /// 드래그로 실제 [CadWall]을 찾았으면 그 id(우선, WO 15번) — 못 찾아
  /// 두 점 직선 거리로 폴백했으면 null.
  final String? calibrationWallId;

  /// 지금 선택된 보정 대상의 시작/끝점(정규화 좌표) — 벽을 찾았으면
  /// 그 벽의 start/end, 폴백이면 드래그 시작/끝점.
  final Point2? calibrationStart;
  final Point2? calibrationEnd;

  /// 위 두 점의 실제 픽셀 거리 — 지금 축척(추정이든 실측이든)으로 본
  /// "현재 추정 길이" 계산과, 사용자가 실제 mm를 입력했을 때 새 축척을
  /// 만드는 데 함께 쓰인다.
  final double? calibrationPixelLength;

  bool get hasCalibrationSelection => calibrationPixelLength != null;

  final FloorPlanScale? scale;
  final double? ceilingHeightMm;

  bool get hasGeometry => floorPlan != null;
  bool get hasScale => scale != null;
  bool get hasCeilingHeight => ceilingHeightMm != null;

  /// CANONICAL 2D CONFIRMATION → 3D PIPELINE WO §6/§7 — "2D 공간 확정"을
  /// 누르기 전까지는 3D를 만들 수 없다. AI/CV 결과가 몇 개를 찾았는지와
  /// 무관하게, 사용자가 확정한 [confirmedFloorPlan] 스냅샷 하나만 3D의
  /// 유일한 입력이 된다(§7 "다시 CV/GPT를 호출해서 재분석하지 않는다").
  final CadFloorPlan? confirmedFloorPlan;
  bool get isConfirmed => confirmedFloorPlan != null;

  /// true인 동안 중앙 캔버스가 (원본/AI Clean 이미지를 basemap으로 삼아)
  /// [CadFloorPlanOverlay]를 편집 가능 상태로 얹어 보여준다 — "치수
  /// 보정"([calibrating])과는 독립된, 별도의 opt-in 모드다.
  final bool structureEditing;
  final CadEditTool cadEditTool;

  /// [CadEditTool.addWall] 도구에서 드래그 대신 두 번 탭으로 벽을 그릴
  /// 경우를 대비해 첫 번째 탭 위치를 잠시 들고 있는 자리 — 이번 구현은
  /// 드래그 한 번으로 벽을 긋는 방식을 기본으로 쓰므로 대부분 null이다.
  final Point2? pendingWallStart;

  /// [3D 아이소 만들기] 버튼 활성화 조건을 만족하지 못하는 이유들(WO
  /// 11번) — 비어 있으면 3D 준비가 끝난 것이다. 축척/천장고는 분석
  /// 직후 자동으로 채워지므로(2D 단순화 WO — [resolveAutoScale]/
  /// [kDefaultCeilingHeightMm]), 실사용에서는 사실상 항상 만족된다 —
  /// 그래도 아직 채워지지 않은 예외적인 순간을 위해 안내 문구는 남긴다.
  ///
  /// CANONICAL 2D CONFIRMATION WO §6 — "2D 공간 확정" 전이면 아무리
  /// geometry/축척/천장고가 갖춰져도 3D를 만들 수 없다(가장 중요한
  /// acceptance criterion — 확정한 것과 3D가 항상 같아야 한다).
  List<String> get missing3DReasons => [
    if (!hasGeometry) '평면도 분석을 먼저 진행해주세요.',
    if (!hasScale) '공간 크기를 계산하지 못했습니다.',
    if (!hasCeilingHeight) '천장 높이를 확인해주세요.',
    if (!isConfirmed) '2D에서 공간을 먼저 확정해주세요.',
  ];

  bool get isReadyFor3D => missing3DReasons.isEmpty;
}

/// [CadWorkspaceState]와 짝을 이루는 콜백 묶음.
@immutable
class CadWorkspaceCallbacks {
  const CadWorkspaceCallbacks({
    required this.onSelectObject,
    required this.onWallEndpointChanged,
    required this.onDisplayModeChanged,
    required this.onToggleDebugOverlay,
    required this.onCalibrationDragEnd,
    required this.onStartCalibration,
    required this.onApplyCalibrationLength,
    required this.onCancelCalibrationSelection,
    required this.onSetCeilingHeight,
    required this.onCeilingHeightPresetSelected,
    required this.onGenerate3D,
    required this.onRenameRoom,
    required this.onSelect3DObject,
    required this.onToggleStructureEditing,
    required this.onCadEditToolChanged,
    required this.onAddWallDrag,
    required this.onAddOpeningTap,
    required this.onOpeningMoved,
    required this.onConfirmFloorPlan,
  });

  final ValueChanged<String?> onSelectObject;

  /// WO092 §5 — 실시간 3D에서 벽/바닥/천장을 탭해 선택(또는 빈 곳을
  /// 탭해 선택 해제)했을 때 호출된다. [onSelectObject](2D CAD 선택)와
  /// 값 공간이 달라(위 [CadWorkspaceState.selected3DObjectId] 참고)
  /// 별도 콜백으로 분리한다.
  final ValueChanged<SpaceObjectIdentityV2?> onSelect3DObject;
  final void Function(String wallId, bool isStart, Point2 newPosition)
  onWallEndpointChanged;
  final ValueChanged<FloorPlanDisplayMode> onDisplayModeChanged;
  final VoidCallback onToggleDebugOverlay;

  /// 치수 보정 drag가 끝났을 때 호출된다 — [String?]는 hit-test로 찾은
  /// 실제 CadWall id(우선), 못 찾았으면 null(두 점 거리 폴백, WO 15번).
  final void Function(Point2 dragStart, Point2 dragEnd, String? nearestWallId)
  onCalibrationDragEnd;

  final VoidCallback onStartCalibration;

  /// 사용자가 입력한 실제 길이(mm)로 축척을 확정한다 — 벽/공간별·전체
  /// 면적·3D 크기가 전부 새 축척으로 다시 계산된다(WO 14번).
  final ValueChanged<double> onApplyCalibrationLength;

  /// 지금 고른 보정 대상(벽 또는 두 점)을 취소하고 다시 드래그할 수
  /// 있게 한다.
  final VoidCallback onCancelCalibrationSelection;

  /// "직접 입력" — 기존 천장고 바텀시트(프리셋+직접입력+validation)를 연다.
  final VoidCallback onSetCeilingHeight;

  /// 2D 정확도 개선 WO(9번) — 천장 높이 프리셋 칩을 한 번 눌러 바로
  /// 선택한다(바텀시트를 열지 않는 가장 빠른 경로).
  final ValueChanged<double> onCeilingHeightPresetSelected;

  final VoidCallback onGenerate3D;

  /// 2D 정확도 개선 WO(4번) — 공간 이름을 사용자가 직접 바꾼다("공간 N"
  /// 자동 이름은 분석이 실제로 알아낸 값이 아니므로, 바꾸고 싶은 사용자를
  /// 위한 구조를 지금부터 만들어 둔다).
  final void Function(String roomId, String name) onRenameRoom;

  // CANONICAL 2D CONFIRMATION → 3D PIPELINE WO §4/§6 — 구조 확인/보정 모드.
  final VoidCallback onToggleStructureEditing;
  final ValueChanged<CadEditTool> onCadEditToolChanged;

  /// [CadEditTool.addWall] — 캔버스를 드래그해 새 벽 하나를 긋는다
  /// (시작점 → 끝점).
  final void Function(Point2 start, Point2 end) onAddWallDrag;

  /// [CadEditTool.addDoor]/[CadEditTool.addWindow] — 기존 벽 위(또는
  /// 근처)를 탭해 그 벽에 새 문/창을 붙인다. 벽 근처가 아니면 아무 일도
  /// 일어나지 않는다(근거 없는 개구부를 지어내지 않는다).
  final void Function(Point2 point, OpeningType type) onAddOpeningTap;

  /// 선택된 문/창을 드래그해 같은 host wall 위의 다른 위치로 옮긴다.
  final void Function(String openingId, Point2 draggedPoint) onOpeningMoved;

  /// "2D 공간 확정" — 지금 draft 상태를 스냅샷으로 승격해 3D의 유일한
  /// 입력으로 삼는다(§6/§7).
  final VoidCallback onConfirmFloorPlan;
}
