import 'package:flutter/material.dart';

/// 신규 MASTER 1번(평면도 업로드 작업실) 화면에서 사용자가 시작할 수 있는
/// 3가지 방식. 이번 작업 범위는 [floorPlanUpload]의 실제 화면 구현이며,
/// 나머지 둘은 진입 선택 UI만 유지한다(전체 기능은 후속 작업).
enum WorkspaceStartMethod { floorPlanUpload, drawManually, photoConvert }

extension WorkspaceStartMethodX on WorkspaceStartMethod {
  String get title => switch (this) {
    WorkspaceStartMethod.floorPlanUpload => '평면도 업로드',
    WorkspaceStartMethod.drawManually => '직접 그리기',
    WorkspaceStartMethod.photoConvert => '사진으로 변환',
  };

  String get description => switch (this) {
    WorkspaceStartMethod.floorPlanUpload => '도면 이미지를 업로드하여\n3D 공간을 자동 생성합니다.',
    WorkspaceStartMethod.drawManually => '벽과 공간을 직접 그려서\n나만의 공간을 만드세요.',
    WorkspaceStartMethod.photoConvert => '실제 공간 사진을 업로드하여\nAI로 인테리어를 변경합니다.',
  };

  IconData get icon => switch (this) {
    WorkspaceStartMethod.floorPlanUpload => Icons.upload_file_rounded,
    WorkspaceStartMethod.drawManually => Icons.edit_road_rounded,
    WorkspaceStartMethod.photoConvert => Icons.photo_camera_back_rounded,
  };
}

/// 중앙 workspace가 같은 공간을 보여주는 방식. 작업 종류가 아니라 View다 —
/// 전환해도 현재 프로젝트/선택/작업 목록/편집값은 그대로 유지된다.
enum WorkspaceViewMode { plan2d, isometric3d, perspective3d }

extension WorkspaceViewModeX on WorkspaceViewMode {
  String get label => switch (this) {
    WorkspaceViewMode.plan2d => '2D 평면도',
    WorkspaceViewMode.isometric3d => '3D 아이소',
    WorkspaceViewMode.perspective3d => '3D 투시',
  };
}

/// "선택 영역 편집" 카드의 도구 — 영역 생성 / 화면·영역 조작 / 편집 3그룹으로
/// 나뉜다([WorkspaceSelectionToolGroup] 참고).
enum WorkspaceSelectionTool {
  select,
  line,
  curve,
  circle,
  freeform,
  move,
  zoomIn,
  zoomOut,
  erase,
}

enum WorkspaceSelectionToolGroup { create, transform, edit }

extension WorkspaceSelectionToolX on WorkspaceSelectionTool {
  WorkspaceSelectionToolGroup get group => switch (this) {
    WorkspaceSelectionTool.select ||
    WorkspaceSelectionTool.line ||
    WorkspaceSelectionTool.curve ||
    WorkspaceSelectionTool.circle ||
    WorkspaceSelectionTool.freeform => WorkspaceSelectionToolGroup.create,
    WorkspaceSelectionTool.move ||
    WorkspaceSelectionTool.zoomIn ||
    WorkspaceSelectionTool.zoomOut => WorkspaceSelectionToolGroup.transform,
    WorkspaceSelectionTool.erase => WorkspaceSelectionToolGroup.edit,
  };

  String get label => switch (this) {
    WorkspaceSelectionTool.select => '선택',
    WorkspaceSelectionTool.line => '직선',
    WorkspaceSelectionTool.curve => '곡선',
    WorkspaceSelectionTool.circle => '원형',
    WorkspaceSelectionTool.freeform => '자유영역',
    WorkspaceSelectionTool.move => '이동',
    WorkspaceSelectionTool.zoomIn => '확대',
    WorkspaceSelectionTool.zoomOut => '축소',
    WorkspaceSelectionTool.erase => '지우기',
  };

  IconData get icon => switch (this) {
    WorkspaceSelectionTool.select => Icons.crop_free_rounded,
    WorkspaceSelectionTool.line => Icons.show_chart_rounded,
    WorkspaceSelectionTool.curve => Icons.gesture_rounded,
    WorkspaceSelectionTool.circle => Icons.circle_outlined,
    WorkspaceSelectionTool.freeform => Icons.crop_square_rounded,
    WorkspaceSelectionTool.move => Icons.pan_tool_alt_outlined,
    WorkspaceSelectionTool.zoomIn => Icons.zoom_in_rounded,
    WorkspaceSelectionTool.zoomOut => Icons.zoom_out_rounded,
    WorkspaceSelectionTool.erase => Icons.auto_fix_off_rounded,
  };
}

/// 작업 목록/3D marker가 공유하는 대상 종류. 종류에 따라 "사이즈" 필드와
/// "마감재 선택" 옵션이 달라진다.
enum WorkspaceTaskCategory { wall, floor, ceiling }

extension WorkspaceTaskCategoryX on WorkspaceTaskCategory {
  /// 이 종류에서 고를 수 있는 마감재 옵션(왼쪽부터 우선 노출).
  List<String> get finishOptions => switch (this) {
    WorkspaceTaskCategory.wall => const [
      '벽지',
      '페인트',
      '타일',
      '패널',
      '석재',
      '사용자 선택',
    ],
    WorkspaceTaskCategory.floor => const [
      '타일',
      '우드',
      '마루',
      '석재',
      '카펫',
      '사용자 선택',
    ],
    WorkspaceTaskCategory.ceiling => const ['페인트', '벽지', '패널', '사용자 선택'],
  };
}

/// 하나의 작업 대상(예: "① 거실 벽(TV 벽체)"). 중앙 3D marker와 하단 작업
/// 목록, 우측 작업 Tab이 전부 이 하나의 모델(과 같은 [id])을 공유해
/// 어느 쪽에서 선택해도 나머지가 함께 동기화된다.
@immutable
class WorkspaceTaskItem {
  const WorkspaceTaskItem({
    required this.id,
    required this.number,
    required this.name,
    required this.category,
    required this.finishLabel,
    required this.color,
    required this.markerPosition,
    this.heightMm,
    this.widthMm,
    this.thicknessMm,
    this.visible = true,
    this.locked = false,
  });

  /// 작업 목록/marker/작업 Tab 전체에서 이 작업을 식별하는 고유 값.
  final int id;

  /// 화면에 표시하는 순번(①, ② ...). rainbow accent 색상도 이 번호로 정한다.
  final int number;

  final String name;
  final WorkspaceTaskCategory category;
  final String finishLabel;
  final Color color;

  /// 중앙 3D 캔버스 위에서 marker를 놓을 위치(0.0~1.0 정규화 좌표).
  final Offset markerPosition;

  final double? heightMm;
  final double? widthMm;
  final double? thicknessMm;

  final bool visible;
  final bool locked;

  WorkspaceTaskItem copyWith({
    String? name,
    String? finishLabel,
    Color? color,
    double? heightMm,
    double? widthMm,
    double? thicknessMm,
    bool? visible,
    bool? locked,
  }) {
    return WorkspaceTaskItem(
      id: id,
      number: number,
      name: name ?? this.name,
      category: category,
      finishLabel: finishLabel ?? this.finishLabel,
      color: color ?? this.color,
      markerPosition: markerPosition,
      heightMm: heightMm ?? this.heightMm,
      widthMm: widthMm ?? this.widthMm,
      thicknessMm: thicknessMm ?? this.thicknessMm,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
    );
  }
}

/// 작업 목록/marker 번호(①②③...)에 쓰는 rainbow accent 순환 색상.
/// 화면 전체를 무지개색으로 채우지 않고, 번호 하나에만 제한적으로 사용한다.
const List<Color> workspaceMarkerColors = [
  Color(0xFFEC4899), // pink/red
  Color(0xFFFB923C), // orange
  Color(0xFFEAB308), // yellow
  Color(0xFF22C55E), // green
  Color(0xFF22D3EE), // cyan
  Color(0xFF6366F1), // blue/purple
];

Color workspaceMarkerColorFor(int number) =>
    workspaceMarkerColors[(number - 1) % workspaceMarkerColors.length];
