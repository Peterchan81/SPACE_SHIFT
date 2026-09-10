import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/cad_workspace_state.dart';
import '../../models/floor_plan_file.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/space_scene.dart';
import '../../models/space_scene_v2.dart';
import '../../models/workspace_drawing_entity.dart';
import '../../models/workspace_task_item.dart';
import '../../models/workspace_viewport_transform.dart';
import '../../theme/space_shift_colors.dart';
import 'floor_plan_preview.dart';
import 'workspace_drawing_layer.dart';

/// 중앙 공간 이미지/3D 작업 화면.
///
/// 실제 3D 렌더링 엔진은 이번 작업 범위가 아니다 — 배경은
/// [FloorPlanPreview]가 업로드/분석/CAD 단계별 상태를 정직하게 보여주고,
/// 그 위에 "사용자가 실제로 만든 작업"의 번호 marker만 정규화 좌표
/// (0.0~1.0)로 겹쳐 보여주는 구조다. 분석 geometry(벽/공간/문·창)는
/// 사용자 작업이 아니므로 여기서 번호를 붙이지 않는다 — CAD
/// geometry 자체의 표시/선택은 [FloorPlanPreview] 안의 CAD 오버레이가
/// 담당한다.
///
/// CAD 표시 도구모음/분석 상태 안내는 더 이상 이 캔버스 위에 그리지
/// 않는다 — 도면을 가리는 문제가 있어 우측 "사용자 작업 환경"의
/// [FloorPlanStatusSection]으로 옮겼다. 중앙은 평면도 자체를 보는 화면으로
/// 최대한 단순하게 유지한다.
class WorkspaceCanvas extends StatelessWidget {
  const WorkspaceCanvas({
    super.key,
    required this.tasks,
    required this.selectedId,
    required this.onSelect,
    required this.viewMode,
    required this.floorPlanFile,
    required this.analysisResult,
    required this.cad,
    required this.cadCallbacks,
    required this.onPickFloorPlanFile,
    this.spaceScene,
    this.spaceSceneV2,
    this.spaceGenerationFailureMessage,
    this.generatedIsoImageBytes,
    this.isGeneratingIsoImage = false,
    this.onExitTo2D,
    this.space3DViewKey,
    this.isFullscreen3D = false,
    this.onToggleFullscreen3D,
    this.tool = WorkspaceSelectionTool.select,
    this.drawings = const [],
    this.selectedDrawingId,
    this.viewport = WorkspaceViewportTransform.identity,
    this.onCreateDrawing,
    this.onSelectDrawing,
    this.onViewportChanged,
    this.onCanvasSizeChanged,
  });

  final List<WorkspaceTaskItem> tasks;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  final WorkspaceViewMode viewMode;
  final FloorPlanFile? floorPlanFile;
  final FloorPlanAnalysisResult? analysisResult;
  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks cadCallbacks;
  final VoidCallback onPickFloorPlanFile;

  /// [CadWorkspaceCallbacks.onGenerate3D]가 실제로 만든 3D geometry —
  /// null이면(아직 생성 전) [FloorPlanPreview]가 준비 상태 안내를 보여준다.
  final SpaceScene? spaceScene;

  /// NOMPASS V2 WO — 실제로 화면에 렌더링하는 3D scene(값이 있으면
  /// [FloorPlanPreview]가 이 값을 우선한다). [spaceScene](V1)은 삭제하지
  /// 않고 계속 넘겨받되, 실기 화면 표시에는 더 이상 쓰이지 않는다.
  final SpaceSceneV2? spaceSceneV2;
  final String? spaceGenerationFailureMessage;

  /// V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO — GPT가 그려준 3D
  /// 아이소메트릭 이미지. 있으면 [FloorPlanPreview]가 [spaceSceneV2]
  /// (실시간 geometry, 그대로 보존)보다 우선 표시한다(§8).
  final Uint8List? generatedIsoImageBytes;
  final bool isGeneratingIsoImage;
  final VoidCallback? onExitTo2D;

  /// WO094 — 전체화면 3D 전환에도 같은 [Space3DViewGpuV2] State가
  /// 유지되도록 상위(FloorPlanWorkspaceScreen)와 공유하는 키/상태.
  /// [FloorPlanPreview]로 그대로 전달한다.
  final GlobalKey? space3DViewKey;
  final bool isFullscreen3D;
  final VoidCallback? onToggleFullscreen3D;

  // WO089 CORE EDITING — 사용자 도형(직선/곡선/원형/자유영역) 편집 상태.
  // 2D 평면도 모드에서만 활성화한다(§ 범위 — 3D는 이번 WO 대상 아님).
  final WorkspaceSelectionTool tool;
  final List<WorkspaceDrawingEntity> drawings;
  final int? selectedDrawingId;
  final WorkspaceViewportTransform viewport;
  final ValueChanged<WorkspaceDrawingEntity>? onCreateDrawing;
  final ValueChanged<int?>? onSelectDrawing;
  final ValueChanged<WorkspaceViewportTransform>? onViewportChanged;
  final ValueChanged<Size>? onCanvasSizeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final floorPlan = cad.floorPlan;
          // V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO §2 — 번호
          // marker(①②③..., 아래 [_RoomNumberMarker])는 "색깔 공간
          // 박스/공간 번호" 계열의 옛 좌표 기반 CAD 표시 UX였다.
          // [cad.floorPlan]은 이제 화면에 보이는 이미지(AI Clean 2D
          // 또는 원본 사진)와 무관하게 3D 생성용 내부 데이터로만 쓰이므로,
          // 이 marker를 계속 그리면 (1) V1이 금지한 공간 번호가 다시
          // 노출되고 (2) floorPlan의 좌표계(원본 사진 픽셀 기준)가 실제
          // 화면에 보이는 이미지(AI가 새로 그린 별도 해상도의 이미지일
          // 수 있음)와 어긋나 위치도 맞지 않는다. [_RoomNumberMarker]/
          // [_polygonCentroid]는 삭제하지 않고 그대로 두되(추후 실시간
          // geometry 3D 강화 단계에서 재사용 가능), production 2D
          // 화면에서는 더 이상 그리지 않는다.

          // WO089 §5/§12 — viewport(pan/zoom)는 기존 콘텐츠(평면도 이미지/
          // room marker/작업 marker) 전체를 시각적으로만 이동/확대한다.
          // 이 Transform은 [WorkspaceDrawingLayer]를 감싸지 않는다 —
          // 감싸면 그 안의 GestureDetector가 받는 로컬 좌표가 이미
          // viewport만큼 역변환된 값이 되어, 그 레이어 내부에서 다시
          // viewport.invert()를 적용하면 이중 변환이 된다. 대신
          // [WorkspaceDrawingLayer]는 원본(미변환) 화면 좌표를 그대로 받고,
          // 자기 페인터 안에서 documentToScreen(= fit + viewport 합성)으로
          // 직접 그린다 — 그래서 두 레이어가 항상 같은 [viewport] 값 하나만
          // 보고 시각적으로 정확히 겹친다(§28 하나의 일관된 아키텍처).
          final existingContent = Stack(
            fit: StackFit.expand,
            children: [
              FloorPlanPreview(
                viewMode: viewMode,
                file: floorPlanFile,
                analysisResult: analysisResult,
                cad: cad,
                cadCallbacks: cadCallbacks,
                onPickFile: onPickFloorPlanFile,
                spaceScene: spaceScene,
                spaceSceneV2: spaceSceneV2,
                spaceGenerationFailureMessage: spaceGenerationFailureMessage,
                generatedIsoImageBytes: generatedIsoImageBytes,
                isGeneratingIsoImage: isGeneratingIsoImage,
                onExitTo2D: onExitTo2D,
                space3DViewKey: space3DViewKey,
                isFullscreen3D: isFullscreen3D,
                onToggleFullscreen3D: onToggleFullscreen3D,
              ),
              for (final task in tasks)
                if (task.visible)
                  Positioned(
                    left: task.markerPosition.dx * constraints.maxWidth - 16,
                    top: task.markerPosition.dy * constraints.maxHeight - 16,
                    child: _CanvasMarker(
                      task: task,
                      selected: task.id == selectedId,
                      onTap: () => onSelect(task.id),
                    ),
                  ),
            ],
          );

          final showDrawingLayer =
              viewMode == WorkspaceViewMode.plan2d && !cad.calibrating;
          final documentSize = floorPlan != null
              ? Size(
                  floorPlan.sourceWidthPx.toDouble(),
                  floorPlan.sourceHeightPx.toDouble(),
                )
              : Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            fit: StackFit.expand,
            children: [
              Transform(
                transform: Matrix4.identity()
                  ..translateByDouble(
                    viewport.offset.dx,
                    viewport.offset.dy,
                    0,
                    1,
                  )
                  ..scaleByDouble(
                    viewport.scale,
                    viewport.scale,
                    viewport.scale,
                    1,
                  ),
                child: existingContent,
              ),
              if (showDrawingLayer)
                WorkspaceDrawingLayer(
                  tool: tool,
                  drawings: drawings,
                  selectedDrawingId: selectedDrawingId,
                  viewport: viewport,
                  documentSize: documentSize,
                  onCreateDrawing: onCreateDrawing ?? (_) {},
                  onSelectDrawing: (id) {
                    onSelectDrawing?.call(id);
                    // WO089 CORE EDITING — 사용자 도형을 선택하면, 화면에
                    // 동시에 CAD 벽/공간이 "선택된 채"로 남아 두 선택
                    // 상태가 우측 패널에서 충돌해 보이지 않도록 CAD
                    // 선택은 비운다(아래 onSelectTapMiss가 반대 방향—
                    // CAD geometry를 선택하면 도형 선택을 건드리지 않는
                    // 이유는, 그쪽은 이 레이어가 자기 도형에서 못 찾았을
                    // 때만 위임되는 "탭이 아무 데도 없었다"는 신호라
                    // 이미 도형 선택이 null인 경로이기 때문이다).
                    if (id != null) cadCallbacks.onSelectObject(null);
                  },
                  onViewportChanged: onViewportChanged ?? (_) {},
                  onCanvasSizeChanged: onCanvasSizeChanged,
                  // V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO §2 —
                  // WO089에서는 이 레이어가 자기 도형에서 못 찾은 탭을
                  // 기존 CadFloorPlanOverlay의 벽/문·창/공간 탭 선택으로
                  // 위임했다. 이제 [floorPlan]은 화면에 보이는 이미지(AI
                  // Clean 2D 또는 원본 사진)와 다른 좌표계(항상 원본 사진
                  // 픽셀 기준)를 갖는 내부 3D 전용 데이터라, 화면에 보이는
                  // 좌표로 그 hit-test를 그대로 재사용하면 (1) 위치가
                  // 어긋나고 (2) 선택되면 V1이 금지한 CAD 요소 정보 패널이
                  // 다시 노출된다. onSelectTapMiss를 생략하면 자기 도형에
                  // 없는 탭은 조용히 무시된다(안전한 기본값).
                ),
            ],
          );
        },
      ),
    );
  }
}

/// polygon의 산술 평균(중심) — [CadRoom.polygon]이 지금은 항상 4점
/// 경계 사각형이라 정확히 기하 중심과 같지만, 향후 실제 윤곽(N점)으로
/// 바뀌어도 그대로 동작하도록 점 개수에 의존하지 않게 계산한다.
Point2 _polygonCentroid(List<Point2> polygon) {
  if (polygon.isEmpty) return const Point2(0.5, 0.5);
  var sx = 0.0, sy = 0.0;
  for (final p in polygon) {
    sx += p.x;
    sy += p.y;
  }
  return Point2(sx / polygon.length, sy / polygon.length);
}

class _RoomNumberMarker extends StatelessWidget {
  const _RoomNumberMarker({
    required this.number,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int number;

  /// PC2 2D CAD 재조사 WO — 이 방 polygon의 연한 fill과 같은
  /// [SpaceShiftColors.roomAccentColorFor] 색. 선택되지 않은 상태의
  /// 번호 배지 테두리/글자에 그대로 써서, "이 번호 = 도면 위 이
  /// 색으로 칠해진 영역"이라는 대응을 색으로도 보여준다. 선택 상태는
  /// 기존과 동일하게 앱 공통 selectionAccent로 강조해 방 색과 헷갈리지
  /// 않게 한다.
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unselectedColor = color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? SpaceShiftColors.selectionAccent : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : unselectedColor,
            width: selected ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
            ),
          ],
        ),
        child: Text(
          '$number',
          style: TextStyle(
            color: selected ? Colors.white : unselectedColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _CanvasMarker extends StatelessWidget {
  const _CanvasMarker({
    required this.task,
    required this.selected,
    required this.onTap,
  });

  final WorkspaceTaskItem task;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = workspaceMarkerColorFor(task.number);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 3 : 2),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: selected ? 0.55 : 0.3),
              blurRadius: selected ? 12 : 6,
              spreadRadius: selected ? 2 : 0,
            ),
          ],
        ),
        child: Text(
          '${task.number}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
