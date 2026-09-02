import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/cad_workspace_state.dart';
import '../../models/floor_plan_file.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/space_scene.dart';
import '../../models/space_scene_v2.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'floor_plan_analysis_overlay.dart' show ContainFitTransform;
import 'floor_plan_preview.dart';

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

          return Stack(
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
