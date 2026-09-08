import 'dart:math' as math;

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
import 'cad_floor_plan_overlay.dart' show cadFloorPlanHitTest;
import 'floor_plan_analysis_overlay.dart' show ContainFitTransform;
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
    this.onExitTo2D,
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
  final VoidCallback? onExitTo2D;

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
          final showRoomMarkers =
              viewMode == WorkspaceViewMode.plan2d &&
              floorPlan != null &&
              !cad.calibrating;
          final transform = showRoomMarkers
              ? ContainFitTransform.compute(
                  Size(constraints.maxWidth, constraints.maxHeight),
                  Size(
                    floorPlan.sourceWidthPx.toDouble(),
                    floorPlan.sourceHeightPx.toDouble(),
                  ),
                )
              : null;

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
                onExitTo2D: onExitTo2D,
              ),
              // 실기 FAIL 재수정 WO(3번) — "각 공간이 도면의 어디인지 알 수
              // 없다"는 신고 대응. 우측 목록과 같은 번호(①②③...)를 room
              // polygon 중심에 표시하고, 탭하면 같은 selectObject 콜백으로
              // 선택돼 우측 목록과 자동으로 동기화된다(별도 selection 상태를
              // 새로 만들지 않는다 — 기존 CadFloorPlanOverlay 선택 하이라이트
              // 재사용).
              if (transform != null && floorPlan != null)
                for (var i = 0; i < floorPlan.rooms.length; i++)
                  Builder(
                    builder: (context) {
                      final room = floorPlan.rooms[i];
                      final centroid = _polygonCentroid(room.polygon);
                      final screenPos = transform.mapNormalized(centroid);
                      return Positioned(
                        left: screenPos.dx - 14,
                        top: screenPos.dy - 14,
                        child: _RoomNumberMarker(
                          number: i + 1,
                          color: SpaceShiftColors.roomAccentColorFor(i),
                          selected: room.id == cad.selectedObjectId,
                          onTap: () => cadCallbacks.onSelectObject(room.id),
                        ),
                      );
                    },
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
                  onSelectTapMiss: (doc) {
                    // WO089 CORE EDITING — 이 레이어가 기존
                    // CadFloorPlanOverlay 위에 얹혀 모든 탭을 먼저
                    // 받는다(§28, 하나의 gesture 소유자). 자기 도형에
                    // 아무 것도 없으면, 원래 CadFloorPlanOverlay의
                    // onTapUp이 하던 벽/문·창/공간 탭 선택을 그대로
                    // 재현해 위임한다 — 그렇지 않으면 이 레이어가 opaque로
                    // 모든 탭을 가로채 기존 CAD 선택 기능이 완전히
                    // 죽는다(실제로 겪은 회귀).
                    if (doc == null || floorPlan == null) {
                      cadCallbacks.onSelectObject(null);
                      return;
                    }
                    final fitForHit =
                        transform ??
                        ContainFitTransform.compute(
                          Size(constraints.maxWidth, constraints.maxHeight),
                          Size(
                            floorPlan.sourceWidthPx.toDouble(),
                            floorPlan.sourceHeightPx.toDouble(),
                          ),
                        );
                    final shortSide = math.min(
                      fitForHit.rect.width,
                      fitForHit.rect.height,
                    );
                    final tolerance = shortSide > 0 ? 14.0 / shortSide : 0.03;
                    cadCallbacks.onSelectObject(
                      cadFloorPlanHitTest(floorPlan, doc, tolerance: tolerance),
                    );
                  },
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
