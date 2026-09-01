import 'package:flutter/foundation.dart';

import 'cad_floor_plan.dart';
import 'floor_plan_geometry.dart';

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
    this.calibrationPoints = const [],
    this.scale,
    this.ceilingHeightMm,
  });

  final CadFloorPlan? floorPlan;
  final String? selectedObjectId;
  final FloorPlanDisplayMode displayMode;
  final bool debugOverlay;

  /// true면 "기준 치수 설정" 두 점 찍기 모드 — geometry 선택 대신
  /// 캔버스 탭을 기준점으로 기록한다(WO 9번).
  final bool calibrating;
  final List<Point2> calibrationPoints;

  final FloorPlanScale? scale;
  final double? ceilingHeightMm;

  bool get hasGeometry => floorPlan != null;
  bool get hasScale => scale != null;
  bool get hasCeilingHeight => ceilingHeightMm != null;

  /// [3D 공간 생성] 버튼 활성화 조건을 만족하지 못하는 이유들(WO 11번) —
  /// 비어 있으면 3D 준비가 끝난 것이다.
  List<String> get missing3DReasons => [
    if (!hasGeometry) '평면도 분석을 먼저 진행해주세요.',
    if (!hasScale) '기준 치수(축척)를 설정해주세요.',
    if (!hasCeilingHeight) '천장고를 입력해주세요.',
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
    required this.onCalibrationTap,
    required this.onStartCalibration,
    required this.onSetCeilingHeight,
    required this.onGenerate3D,
  });

  final ValueChanged<String?> onSelectObject;
  final void Function(String wallId, bool isStart, Point2 newPosition)
  onWallEndpointChanged;
  final ValueChanged<FloorPlanDisplayMode> onDisplayModeChanged;
  final VoidCallback onToggleDebugOverlay;
  final ValueChanged<Point2> onCalibrationTap;
  final VoidCallback onStartCalibration;
  final VoidCallback onSetCeilingHeight;
  final VoidCallback onGenerate3D;
}
