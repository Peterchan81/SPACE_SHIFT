import 'package:flutter/material.dart';

import '../models/cad_floor_plan.dart';
import '../models/cad_workspace_state.dart';
import '../models/floor_plan_file.dart';
import '../models/floor_plan_geometry.dart';
import '../models/space_scene.dart';
import '../models/space_scene_v2.dart';
import '../models/workspace_drawing_entity.dart';
import '../models/workspace_task_item.dart';
import '../models/workspace_viewport_transform.dart';
import '../services/floor_plan_analysis_service.dart';
import '../services/floor_plan_upload_service.dart';
import '../services/gpt_floorplan_vision_service.dart';
import '../services/space_scene_builder.dart';
import '../services/space_scene_builder_v2.dart';
import '../services/vision_guided_spatial_model_builder.dart';
import '../services/vision_interpretation_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/workspace/ceiling_height_sheet.dart';
import '../widgets/workspace/settings_entry_button.dart';
import '../widgets/workspace/start_method_panel.dart';
import '../widgets/workspace/user_workspace_panel.dart';
import '../widgets/workspace/workspace_canvas.dart';
import '../widgets/workspace/workspace_task_list.dart';
import '../widgets/workspace/workspace_view_switcher.dart';
import 'photo_select_screen.dart';
import 'settings_screen.dart';

/// WO089 CORE EDITING — 작업 항목([WorkspaceTaskItem])과 사용자 도형
/// ([WorkspaceDrawingEntity]) 편집을 하나의 연대순 Undo/Redo 이력으로
/// 합치기 위한 스냅샷. 기존 [_undoStack]/[_redoStack] 구조(리스트를
/// 그대로 push/pop)를 그대로 재사용하되, 담는 내용만 tasks 하나에서
/// {tasks, drawings} 묶음으로 넓혔다 — 두 번째 Undo 스택을 새로 만들지
/// 않는다.
typedef _WorkspaceSnapshot = ({List<WorkspaceTaskItem> tasks, List<WorkspaceDrawingEntity> drawings});

/// 신규 MASTER 1번 — "평면도 업로드" 작업실이자, 로그인/회원가입 이후
/// 진입하는 신규 MASTER 메인 작업 화면.
///
/// 좌측 "시작 방식 선택" 3가지 중 이번 작업 범위는
/// [WorkspaceStartMethod.floorPlanUpload]의 실제 화면 구현이다.
/// - [WorkspaceStartMethod.drawManually](직접 그리기): 아직 실제 화면이
///   없어 선택 시 준비중 안내만 보여준다.
/// - [WorkspaceStartMethod.photoConvert](사진으로 변환): 기존
///   [PhotoSelectScreen](공간 사진 등록)의 카메라/갤러리 선택 기능을 그대로
///   재사용한다 — 화면을 다시 만들지 않고, 이 화면 위에 잠시 push했다가
///   완료/취소 시 다시 이 화면으로 돌아오는 방식으로 최소 연결한다.
///
/// 기존 [WorkspaceScreen](공간 작업실, 사진 기반 부분 영역 선택)과
/// [PhotoSelectScreen]은 코드/기능 모두 삭제하지 않고 그대로 보존한다 —
/// 다만 로그인 직후 자동으로 진입하는 기본 화면에서는 제외되고, 이 화면의
/// "사진으로 변환" 경로를 통해서만 진입한다.
class FloorPlanWorkspaceScreen extends StatefulWidget {
  const FloorPlanWorkspaceScreen({
    super.key,
    this.projectName = '새 프로젝트',
    this.demoMode = false,
    this.uploadService = const FloorPlanUploadService(),
    this.analysisService = const FloorPlanAnalysisService(),
    this.visionInterpretationService,
  });

  final String projectName;

  /// MASTER UI 디자인 검수/미리보기용으로만 데모 마커 6개와 첫 항목 선택을
  /// 미리 채워 넣는다(WO 8/9번). 로그인/회원가입에서 진입하는 실사용
  /// 경로는 이 값을 지정하지 않으므로 항상 false — 실제 사용자가 평면도를
  /// 올리기 전까지 작업 목록/마커는 비어 있어야 한다.
  final bool demoMode;

  final FloorPlanUploadService uploadService;
  final FloorPlanAnalysisService analysisService;

  /// GPT FLOORPLAN WO — 테스트가 실제 네트워크 호출 없이 GPT 응답을
  /// 흉내낼 수 있도록 주입 지점을 둔다. 지정하지 않으면(실사용 경로)
  /// [_createProductionVisionService]가 dart-define 설정에 따라 안전한
  /// 기본값 또는 실제 Edge Function 구현을 고른다.
  final VisionInterpretationService? visionInterpretationService;

  @override
  State<FloorPlanWorkspaceScreen> createState() =>
      _FloorPlanWorkspaceScreenState();
}

/// 2D 단순화 WO(6번) — "천장 높이 확인" 기본값. 기존 [ceilingHeightPresetsMm]
/// (2300/2400/2500/2700mm) 중 가장 널리 쓰이는 값을 골라, 분석 직후
/// 자동으로 채워 넣는다 — 사용자는 "확인"만 하면 되고, 다르면 기존
/// "천장고 입력" 시트에서 바꿀 수 있다.
const double kDefaultCeilingHeightMm = 2400;

/// GPT FLOORPLAN → STRUCTURED 2D → REAL 3D ISO FLOW WO §2 — pixel_wall_v4
/// (WO088 Raster→CAD 자동 벡터화 POC)는 더 이상 V1 production 분석
/// 경로가 아니다. 코드/테스트는 R&D 자산으로 그대로 보존하되(삭제하지
/// 않는다), 이 화면은 대신 GPT가 구조를 이해하고([VisionInterpretationService])
/// 기존 픽셀 evidence 정밀화([VisionGuidedSpatialModelBuilder] →
/// [HintedGeometryExtractor] → [TopologyValidator])로 최종 [SSSpatialModel]을
/// 만드는 파이프라인을 쓴다(§4). GPT Edge Function이 아직 배포되지
/// 않았으면([createVisionInterpretationService]가 안전한 기본값
/// [UnavailableVisionInterpretationService]를 돌려줌) 즉시 실패하고,
/// 호출부(§ 아래 [_startAnalysis])가 기존 geometry-only 분석 결과로
/// 정직하게 폴백한다 — 절대 죽지 않는다(§14).
VisionInterpretationService _createProductionVisionService() => createVisionInterpretationService();

class _FloorPlanWorkspaceScreenState extends State<FloorPlanWorkspaceScreen> {
  WorkspaceStartMethod _startMethod = WorkspaceStartMethod.floorPlanUpload;
  WorkspaceViewMode _viewMode = WorkspaceViewMode.plan2d;
  WorkspaceSelectionTool _tool = WorkspaceSelectionTool.select;

  late List<WorkspaceTaskItem> _tasks;
  int? _selectedTaskId;

  /// WO089 CORE EDITING — 사용자가 직접 만든 도형(직선/곡선/원형/
  /// 자유영역). [WorkspaceTaskItem]과는 별개 목록이다(§4 조사 결론 —
  /// 작업 항목은 marker 하나뿐이라 도형 geometry를 담을 수 없다).
  List<WorkspaceDrawingEntity> _drawings = [];
  int? _selectedDrawingId;
  int _nextDrawingId = 1;

  /// §5 — 2D pan/zoom 상태. 문서 좌표([Point2])는 절대 건드리지 않고
  /// 오직 이 transform만 바뀐다 — 그래서 Undo 이력에 넣지 않는다(§14).
  WorkspaceViewportTransform _viewport = WorkspaceViewportTransform.identity;

  /// §17 TAB TEST UI — 편집 모드/도형 개수/Zoom/선택 상태를 작게 보여주는
  /// 디버그 패널. 릴리스에서 숨길 수 있도록 토글 가능한 상태로 둔다.
  bool _showEditDebugInfo = true;

  FloorPlanFile? _floorPlanFile;
  FloorPlanAnalysisPhase _analysisPhase = FloorPlanAnalysisPhase.notStarted;
  FloorPlanAnalysisStep? _analysisStep;
  FloorPlanAnalysisResult? _analysisResult;
  String? _analysisFailureMessage;

  /// 분석 결과를 편집 가능한 CAD geometry로 옮긴 것 — 분석 geometry는
  /// 사용자 작업이 아니므로 [_tasks]와는 완전히 분리된 상태로 관리한다
  /// (WO 1/2/12번).
  CadFloorPlan? _cadFloorPlan;
  String? _selectedCadObjectId;
  final List<CadFloorPlan> _cadUndoStack = [];

  FloorPlanDisplayMode _displayMode = FloorPlanDisplayMode.cad;
  bool _debugOverlay = false;

  bool _calibrating = false;
  String? _calibrationWallId;
  Point2? _calibrationStart;
  Point2? _calibrationEnd;
  double? _calibrationPixelLength;
  FloorPlanScale? _scale;
  double? _ceilingHeightMm;

  /// 실제로 생성된 3D 공간 — [_onGenerate3D]가 성공했을 때만 채워진다.
  /// viewMode가 3D여도 이 값이 null이면 아직 생성 전(또는 생성 실패)
  /// 이라는 뜻이라 [FloorPlanPreview]가 준비 상태 안내를 계속 보여준다.
  SpaceScene? _spaceScene;

  /// NOMPASS V2 WO — 실제 화면에 보여주는 3D는 이제 [buildSpaceSceneV2]
  /// 결과다([_spaceScene]/V1 렌더러는 삭제하지 않고 그대로 남겨 두되
  /// (WO "기존 구현 삭제 금지"), 사용자가 실기로 확인하는 화면은 V2로
  /// 교체한다 — 병렬로만 만들고 아무 데서도 안 쓰면 실기 검증 자체가
  /// 불가능하다).
  SpaceSceneV2? _spaceSceneV2;
  String? _spaceGenerationFailureMessage;

  final List<_WorkspaceSnapshot> _undoStack = [];
  final List<_WorkspaceSnapshot> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _tasks = widget.demoMode ? _demoTasks() : const [];
    _selectedTaskId = _tasks.isEmpty ? null : _tasks.first.id;
  }

  /// "① 평면도 업로드" 카드/캔버스의 업로드 버튼 공용 핸들러. 새 파일을
  /// 고르면 이전 파일에 대한 분석/CAD/축척/천장고 상태는 더 이상 유효하지
  /// 않으므로 함께 초기화한다. 사용자가 이미 만들어 둔 실제 작업
  /// ([_tasks])은 파일 재선택만으로는 지우지 않는다(도면 보정과 사용자
  /// 작업은 서로 다른 개념이므로, WO 8번).
  Future<void> _pickFloorPlan() async {
    final file = await widget.uploadService.pickFloorPlanFile();
    if (file == null || !mounted) return;
    setState(() {
      _floorPlanFile = file;
      _analysisPhase = FloorPlanAnalysisPhase.notStarted;
      _analysisStep = null;
      _analysisResult = null;
      _analysisFailureMessage = null;
      _cadFloorPlan = null;
      _selectedCadObjectId = null;
      _cadUndoStack.clear();
      _displayMode = FloorPlanDisplayMode.cad;
      _debugOverlay = false;
      _calibrating = false;
      _calibrationWallId = null;
      _calibrationStart = null;
      _calibrationEnd = null;
      _calibrationPixelLength = null;
      _scale = null;
      _ceilingHeightMm = null;
      _spaceScene = null;
      _spaceSceneV2 = null;
      _spaceGenerationFailureMessage = null;
      _viewMode = WorkspaceViewMode.plan2d;
    });
  }

  VisionInterpretationService get _visionService =>
      widget.visionInterpretationService ?? _createProductionVisionService();

  /// "평면도 분석 시작" — 실제 CV 파이프라인(FloorPlanAnalysisService)을
  /// 호출해 벽/공간/문·창 후보를 계산하고, 편집 가능한 CAD geometry로
  /// 변환한다. 분석 직후에는 작업 목록에 아무 것도 추가하지 않는다 —
  /// 작업은 사용자가 실제로 만들 때만 생긴다(WO 2번). 실패하면 원본
  /// 이미지는 그대로 두고 실패 이유만 보여준다(가짜 분석 완료를 만들지
  /// 않는다).
  Future<void> _startAnalysis() async {
    final file = _floorPlanFile;
    if (file == null) return;

    setState(() {
      _analysisPhase = FloorPlanAnalysisPhase.analyzing;
      _analysisStep = FloorPlanAnalysisStep.preparingAndWalls;
      _analysisFailureMessage = null;
    });

    final outcome = await widget.analysisService.analyze(
      file,
      onStep: (step) {
        if (mounted) setState(() => _analysisStep = step);
      },
    );
    if (!mounted) return;

    if (outcome.isSuccess) {
      final result = outcome.result!;
      // GPT FLOORPLAN WO §2/§4 — 이제 기본 geometry-only 분석
      // (FloorPlanAnalysisService)을 먼저 안전한 baseline으로 확보해
      // 두고, GPT 구조 이해 파이프라인이 실제로 벽/공간을 만들어내면
      // 그 결과로 교체한다. GPT가 아직 설정되지 않았거나 실패해도
      // 화면은 절대 비지 않는다 — 항상 이 baseline이 남는다(§14).
      var cadFloorPlan = buildCadFloorPlan(result);
      try {
        final model = await VisionGuidedSpatialModelBuilder(
          visionService: _visionService,
        ).build(file.bytes!);
        if (model.walls.isNotEmpty || model.spaces.isNotEmpty) {
          cadFloorPlan = buildCadFloorPlanFromSpatialModel(model);
        } else {
          cadFloorPlan = cadFloorPlan.copyWithWarnings([
            ...cadFloorPlan.warnings,
            '평면도 구조를 자동으로 확인하지 못해 기본 분석 결과를 사용했습니다.',
          ]);
        }
      } catch (_) {
        // GPT 평면도 이해가 아직 설정되지 않았거나(Edge Function URL
        // 미배포) 네트워크/응답 오류로 실패한 경우 — 원본 예외 내용은
        // 사용자에게 노출하지 않고(이 프로젝트의 "원본 예외 비노출"
        // 관례), 이미 확보해 둔 geometry-only baseline을 그대로 쓴다.
        cadFloorPlan = cadFloorPlan.copyWithWarnings([
          ...cadFloorPlan.warnings,
          '평면도 구조 이해 기능을 사용할 수 없어 기본 분석 결과를 사용했습니다.',
        ]);
      }
      setState(() {
        _analysisPhase = FloorPlanAnalysisPhase.completed;
        _analysisResult = result;
        _analysisStep = null;
        _cadFloorPlan = cadFloorPlan;
        _selectedCadObjectId = null;
        _cadUndoStack.clear();
        // 2D 단순화 WO — 사용자가 이미 직접 보정한 축척은 절대 덮어쓰지
        // 않는다([resolveAutoScale] 참고). 처음 분석이라면 문 기준
        // 추정 또는(그마저 없으면) "알 수 없음" 임시 기준으로 자동
        // 채워, 사용자가 기준점을 직접 찍지 않아도 3D로 진행할 수 있게
        // 한다(핵심 원칙: "일단 만들어주고 정확도는 나중에").
        _scale = resolveAutoScale(cadFloorPlan, _scale);
        _ceilingHeightMm ??= kDefaultCeilingHeightMm;
        // 재분석으로 geometry 자체가 바뀌었을 수 있어, 이전 3D 결과는
        // 더 이상 지금 도면과 일치한다고 보장할 수 없다 — 다시 만들어야
        // 한다(가짜로 그대로 두지 않는다).
        _spaceScene = null;
        _spaceSceneV2 = null;
        _spaceGenerationFailureMessage = null;
      });
    } else {
      setState(() {
        _analysisPhase = FloorPlanAnalysisPhase.failed;
        _analysisFailureMessage = outcome.message;
        _analysisStep = null;
      });
    }
  }

  CadWall? get _selectedCadWall {
    final plan = _cadFloorPlan;
    final id = _selectedCadObjectId;
    if (plan == null || id == null) return null;
    for (final wall in plan.walls) {
      if (wall.id == id) return wall;
    }
    return null;
  }

  CadOpening? get _selectedCadOpening {
    final plan = _cadFloorPlan;
    final id = _selectedCadObjectId;
    if (plan == null || id == null) return null;
    for (final opening in plan.openings) {
      if (opening.id == id) return opening;
    }
    return null;
  }

  CadRoom? get _selectedCadRoom {
    final plan = _cadFloorPlan;
    final id = _selectedCadObjectId;
    if (plan == null || id == null) return null;
    for (final room in plan.rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  /// CAD geometry(벽/공간/문·창) 선택 — 사용자 작업 선택과는 별개의
  /// 상태이므로, 하나가 선택되면 다른 하나는 비운다(WO 12번, 우측 패널이
  /// 둘 중 하나만 보여줄 수 있게).
  void _onSelectCadObject(String? id) {
    setState(() {
      _selectedCadObjectId = id;
      if (id != null) _selectedTaskId = null;
    });
  }

  void _mutateCad(CadFloorPlan Function(CadFloorPlan) mutator) {
    final plan = _cadFloorPlan;
    if (plan == null) return;
    setState(() {
      _cadUndoStack.add(plan);
      _cadFloorPlan = mutator(plan);
    });
  }

  void _undoCad() {
    if (_cadUndoStack.isEmpty) return;
    setState(() => _cadFloorPlan = _cadUndoStack.removeLast());
  }

  void _onWallEndpointChanged(String wallId, bool isStart, Point2 newPosition) {
    _mutateCad(
      (plan) => plan.copyWithWalls([
        for (final wall in plan.walls)
          if (wall.id == wallId)
            wall.copyWith(
              start: isStart ? newPosition : null,
              end: isStart ? null : newPosition,
              edited: true,
              source: CadElementSource.userEdited,
            )
          else
            wall,
      ]),
    );
  }

  void _deleteSelectedCadObject() {
    final id = _selectedCadObjectId;
    final plan = _cadFloorPlan;
    if (id == null || plan == null) return;
    setState(() {
      _cadUndoStack.add(plan);
      _cadFloorPlan = CadFloorPlan(
        sourceWidthPx: plan.sourceWidthPx,
        sourceHeightPx: plan.sourceHeightPx,
        walls: plan.walls.where((w) => w.id != id).toList(),
        openings: plan.openings.where((o) => o.id != id).toList(),
        rooms: plan.rooms.where((r) => r.id != id).toList(),
        warnings: plan.warnings,
        objectCandidates: plan.objectCandidates,
      );
      _selectedCadObjectId = null;
    });
  }

  /// 선택된 CAD geometry로부터 실제 사용자 작업을 하나 만든다 — 이때
  /// 비로소 작업 번호(①②③...)가 부여된다(WO 12번). geometry id와 새로
  /// 만들어지는 작업 id/번호는 서로 다른 식별자로 완전히 분리된다.
  void _createWorkItemFromCad() {
    final wall = _selectedCadWall;
    final opening = _selectedCadOpening;
    final room = _selectedCadRoom;
    if (wall == null && opening == null && room == null) return;

    late final String name;
    late final WorkspaceTaskCategory category;
    late final Offset markerPosition;
    Color color = SpaceShiftColors.selectionAccent;

    if (wall != null) {
      name = wall.wallType == CadWallType.exterior ? '외벽 작업' : '내벽 작업';
      category = WorkspaceTaskCategory.wall;
      markerPosition = Offset(
        (wall.start.x + wall.end.x) / 2,
        (wall.start.y + wall.end.y) / 2,
      );
      color = const Color(0xFFB98A5C);
    } else if (opening != null) {
      name = opening.type == OpeningType.door ? '문 작업' : '창 작업';
      category = opening.type == OpeningType.door
          ? WorkspaceTaskCategory.door
          : WorkspaceTaskCategory.window;
      markerPosition = Offset(opening.center.x, opening.center.y);
      color = const Color(0xFFD8C3A5);
    } else {
      name = '공간 작업';
      category = WorkspaceTaskCategory.floor;
      var sx = 0.0, sy = 0.0;
      for (final p in room!.polygon) {
        sx += p.x;
        sy += p.y;
      }
      markerPosition = Offset(
        sx / room.polygon.length,
        sy / room.polygon.length,
      );
      color = const Color(0xFFE3E7E9);
    }

    final nextId = _tasks.isEmpty
        ? 1
        : _tasks.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
    final nextNumber = _tasks.length + 1;
    // GPT FLOORPLAN WO §11 — 이 작업이 어느 CAD geometry에서 왔는지
    // 기억해 둔다. "3D 아이소 만들기"가 이 값으로 사용자가 고른 색을
    // 해당 벽/공간의 3D 기본 재질보다 우선 적용한다(_applyMaterialOverrides).
    final sourceCadId = wall?.id ?? opening?.id ?? room?.id;

    _mutate(
      (tasks) => [
        ...tasks,
        WorkspaceTaskItem(
          id: nextId,
          number: nextNumber,
          name: name,
          category: category,
          finishLabel: category.finishOptions.first,
          color: color,
          markerPosition: markerPosition,
          sourceCadId: sourceCadId,
        ),
      ],
    );
    setState(() {
      _selectedTaskId = nextId;
      _selectedCadObjectId = null;
    });
  }

  void _onDisplayModeChanged(FloorPlanDisplayMode mode) {
    setState(() => _displayMode = mode);
  }

  void _onToggleDebugOverlay() {
    setState(() => _debugOverlay = !_debugOverlay);
  }

  void _onStartCalibration() {
    setState(() {
      _calibrating = !_calibrating;
      _calibrationWallId = null;
      _calibrationStart = null;
      _calibrationEnd = null;
      _calibrationPixelLength = null;
    });
  }

  /// 실기 FAIL 재수정 WO(11/12번) — 기준점 2개를 따로따로 탭하던 방식을
  /// 버리고, 벽 구간을 직접 drag해서 고른다. 실제 [CadWall]을 찾았으면
  /// 그 벽 전체 길이를 쓰고(WO 15번 — wall 객체 우선), 못 찾았을 때만
  /// 드래그 두 점의 직선 거리로 폴백한다.
  void _onCalibrationDragEnd(Point2 dragStart, Point2 dragEnd, String? wallId) {
    final plan = _cadFloorPlan;
    if (plan == null) return;

    CadWall? wall;
    if (wallId != null) {
      for (final w in plan.walls) {
        if (w.id == wallId) {
          wall = w;
          break;
        }
      }
    }

    final start = wall?.start ?? dragStart;
    final end = wall?.end ?? dragEnd;
    final pixelLength = plan.pixelDistance(start, end);
    if (pixelLength <= 0) return;

    setState(() {
      _calibrationWallId = wall?.id;
      _calibrationStart = start;
      _calibrationEnd = end;
      _calibrationPixelLength = pixelLength;
      // 찾은 벽을 화면에도 강조 표시한다(기존 선택 하이라이트 재사용).
      _selectedCadObjectId = wall?.id;
    });
  }

  void _onCancelCalibrationSelection() {
    setState(() {
      _calibrationWallId = null;
      _calibrationStart = null;
      _calibrationEnd = null;
      _calibrationPixelLength = null;
    });
  }

  /// 사용자가 실제 치수(mm)를 입력해 [치수 적용]을 눌렀을 때 — 벽/공간별·
  /// 전체 면적·3D 크기가 전부 이 새 축척(measured)으로 다시 계산된다
  /// (같은 [_scale] 필드를 참조하는 모든 계산이 자동으로 갱신됨, WO
  /// 14번).
  void _onApplyCalibrationLength(double realMm) {
    final start = _calibrationStart;
    final end = _calibrationEnd;
    final pixelLength = _calibrationPixelLength;
    if (start == null ||
        end == null ||
        pixelLength == null ||
        pixelLength <= 0) {
      return;
    }
    setState(() {
      _scale = FloorPlanScale(
        mmPerPixel: realMm / pixelLength,
        referenceStart: start,
        referenceEnd: end,
        referenceLengthMm: realMm,
        source: ScaleSource.measured,
      );
      _calibrating = false;
      _calibrationWallId = null;
      _calibrationStart = null;
      _calibrationEnd = null;
      _calibrationPixelLength = null;
    });
  }

  Future<void> _onSetCeilingHeight() async {
    final value = await showCeilingHeightSheet(
      context,
      initialMm: _ceilingHeightMm,
    );
    if (!mounted || value == null) return;
    setState(() => _ceilingHeightMm = value);
  }

  void _onCeilingHeightPresetSelected(double mm) {
    setState(() => _ceilingHeightMm = mm);
  }

  /// 2D 정확도 개선 WO(4번) — 공간 이름을 사용자가 직접 바꾼다.
  void _onRenameRoom(String roomId, String name) {
    final plan = _cadFloorPlan;
    if (plan == null) return;
    final trimmed = name.trim();
    setState(() {
      _cadFloorPlan = CadFloorPlan(
        sourceWidthPx: plan.sourceWidthPx,
        sourceHeightPx: plan.sourceHeightPx,
        walls: plan.walls,
        openings: plan.openings,
        rooms: [
          for (final room in plan.rooms)
            if (room.id == roomId)
              room.withName(trimmed.isEmpty ? null : trimmed)
            else
              room,
        ],
        warnings: plan.warnings,
        objectCandidates: plan.objectCandidates,
      );
    });
  }

  /// GPT FLOORPLAN WO §11 — "작업으로 추가"로 만들어진 [WorkspaceTaskItem]
  /// 중 사용자가 색을 바꾼(원래 카테고리 기본색과 달라진) 것이 있으면,
  /// 그 원본 CAD 벽/공간([WorkspaceTaskItem.sourceCadId])에
  /// [CadWall.materialOverride]/[CadRoom.materialOverride]로 실어 보낸다.
  /// 3D 빌더([space_scene_builder_v2.dart])는 이 override가 있으면 항상
  /// roomType 기반 기본 재질보다 우선한다 — "사용자 override가 있으면
  /// default보다 우선한다"는 원칙을 실제 데이터 경로로 연결한다.
  CadFloorPlan _applyMaterialOverrides(CadFloorPlan plan) {
    final overrideById = {
      for (final task in _tasks)
        if (task.sourceCadId != null) task.sourceCadId!: task.color,
    };
    if (overrideById.isEmpty) return plan;
    return CadFloorPlan(
      sourceWidthPx: plan.sourceWidthPx,
      sourceHeightPx: plan.sourceHeightPx,
      walls: [
        for (final wall in plan.walls)
          overrideById.containsKey(wall.id)
              ? wall.copyWith(materialOverride: overrideById[wall.id])
              : wall,
      ],
      openings: plan.openings,
      rooms: [
        for (final room in plan.rooms)
          overrideById.containsKey(room.id)
              ? room.withMaterialOverride(overrideById[room.id])
              : room,
      ],
      warnings: plan.warnings,
      objectCandidates: plan.objectCandidates,
    );
  }

  /// [3D 아이소 만들기] — geometry/축척/천장고가 모두 준비됐을 때만
  /// 눌릴 수 있다. NOMPASS V2 WO — 실제 화면에 표시하는 3D는
  /// [buildSpaceSceneV2]로 만든다(V1 [buildSpaceScene]은 삭제하지 않고
  /// 그대로 계속 계산해 둔다 — "기존 구현 삭제 금지", 필요하면 언제든
  /// 되돌릴 수 있다). 생성에 실패하면(예: geometry가 비정상) 2D 화면을
  /// 유지하고 이유를 보여준다(viewMode를 바꾸지 않는다).
  void _onGenerate3D() {
    final plan = _cadFloorPlan;
    final scale = _scale;
    final ceilingHeightMm = _ceilingHeightMm;
    if (!_cadWorkspaceState.isReadyFor3D ||
        plan == null ||
        scale == null ||
        ceilingHeightMm == null) {
      return;
    }

    final planWithMaterials = _applyMaterialOverrides(plan);
    final scene = buildSpaceScene(
      plan: planWithMaterials,
      scale: scale,
      ceilingHeightMm: ceilingHeightMm,
    );
    final sceneV2 = buildSpaceSceneV2(
      plan: planWithMaterials,
      scale: scale,
      ceilingHeightMm: ceilingHeightMm,
    );
    if (sceneV2.isEmpty) {
      setState(() {
        _spaceScene = null;
        _spaceSceneV2 = null;
        _spaceGenerationFailureMessage =
            '벽/바닥 geometry를 3D로 옮기지 못했습니다 — 도면에서 실제로 인식된 '
            '벽/공간이 없는 것 같습니다.';
      });
      return;
    }

    setState(() {
      _spaceScene = scene.isEmpty ? null : scene;
      _spaceSceneV2 = sceneV2;
      _spaceGenerationFailureMessage = null;
      _viewMode = WorkspaceViewMode.isometric3d;
    });
  }

  /// "다시 분석" — 이미 CAD를 사용자가 보정한 적이 있다면(실행취소 스택이
  /// 비어있지 않다면) 재분석으로 그 보정 내용이 사라질 수 있으므로 먼저
  /// 확인을 받는다(WO 22번). 보정 이력이 없으면 바로 분석을 다시
  /// 시작한다.
  Future<void> _onReanalyzeRequested() async {
    if (_cadUndoStack.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('다시 분석하시겠습니까?'),
          content: const Text(
            '다시 분석하면 지금까지 보정한 CAD 내용(벽 끝점 이동, 삭제 등)이 사라지고 '
            '새 분석 결과로 다시 채워집니다. 계속할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('다시 분석'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _startAnalysis();
  }

  CadWorkspaceState get _cadWorkspaceState => CadWorkspaceState(
    floorPlan: _cadFloorPlan,
    selectedObjectId: _selectedCadObjectId,
    displayMode: _displayMode,
    debugOverlay: _debugOverlay,
    calibrating: _calibrating,
    calibrationWallId: _calibrationWallId,
    calibrationStart: _calibrationStart,
    calibrationEnd: _calibrationEnd,
    calibrationPixelLength: _calibrationPixelLength,
    scale: _scale,
    ceilingHeightMm: _ceilingHeightMm,
  );

  CadWorkspaceCallbacks get _cadWorkspaceCallbacks => CadWorkspaceCallbacks(
    onSelectObject: _onSelectCadObject,
    onWallEndpointChanged: _onWallEndpointChanged,
    onDisplayModeChanged: _onDisplayModeChanged,
    onToggleDebugOverlay: _onToggleDebugOverlay,
    onCalibrationDragEnd: _onCalibrationDragEnd,
    onStartCalibration: _onStartCalibration,
    onApplyCalibrationLength: _onApplyCalibrationLength,
    onCancelCalibrationSelection: _onCancelCalibrationSelection,
    onSetCeilingHeight: _onSetCeilingHeight,
    onCeilingHeightPresetSelected: _onCeilingHeightPresetSelected,
    onGenerate3D: _onGenerate3D,
    onRenameRoom: _onRenameRoom,
  );

  static List<WorkspaceTaskItem> _demoTasks() => [
    const WorkspaceTaskItem(
      id: 1,
      number: 1,
      name: '거실 벽 (TV 벽체)',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '패널',
      color: Color(0xFFB98A5C),
      markerPosition: Offset(0.28, 0.32),
      heightMm: 2700,
      widthMm: 3600,
      thicknessMm: 120,
    ),
    const WorkspaceTaskItem(
      id: 2,
      number: 2,
      name: '거실 바닥',
      category: WorkspaceTaskCategory.floor,
      finishLabel: '마루',
      color: Color(0xFFCDA073),
      markerPosition: Offset(0.5, 0.72),
      heightMm: 0,
      widthMm: 4200,
      thicknessMm: 15,
    ),
    const WorkspaceTaskItem(
      id: 3,
      number: 3,
      name: '안방 벽',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '벽지',
      color: Color(0xFFF2EEE9),
      markerPosition: Offset(0.72, 0.28),
      heightMm: 2700,
      widthMm: 3000,
      thicknessMm: 120,
    ),
    const WorkspaceTaskItem(
      id: 4,
      number: 4,
      name: '욕실 벽',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '타일',
      color: Color(0xFFE3E7E9),
      markerPosition: Offset(0.34, 0.58),
      heightMm: 2400,
      widthMm: 2000,
      thicknessMm: 100,
    ),
    const WorkspaceTaskItem(
      id: 5,
      number: 5,
      name: '침실 벽',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '페인트',
      color: Color(0xFFEDE6DC),
      markerPosition: Offset(0.6, 0.52),
      heightMm: 2700,
      widthMm: 3200,
      thicknessMm: 120,
    ),
    const WorkspaceTaskItem(
      id: 6,
      number: 6,
      name: '서재 벽',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '석재',
      color: Color(0xFFA9ADB2),
      markerPosition: Offset(0.8, 0.62),
      heightMm: 2700,
      widthMm: 2600,
      thicknessMm: 130,
    ),
  ];

  WorkspaceTaskItem? get _selectedTask =>
      _tasks.where((task) => task.id == _selectedTaskId).firstOrNull;

  _WorkspaceSnapshot get _currentSnapshot => (tasks: List.of(_tasks), drawings: List.of(_drawings));

  void _mutate(
    List<WorkspaceTaskItem> Function(List<WorkspaceTaskItem>) mutator,
  ) {
    setState(() {
      _undoStack.add(_currentSnapshot);
      _redoStack.clear();
      _tasks = mutator(List.of(_tasks));
    });
  }

  /// WO089 CORE EDITING — [_mutate]와 정확히 같은 패턴(스냅샷 push →
  /// redo 비우기 → 실제 변경)을 도형 목록에 적용한다. 같은
  /// [_undoStack]/[_redoStack]을 공유해 작업 항목 편집과 도형 편집이
  /// 하나의 연대순 Undo 이력으로 합쳐진다(기존 UI에 두 번째 Undo 버튼을
  /// 새로 만들지 않는다).
  void _mutateDrawings(
    List<WorkspaceDrawingEntity> Function(List<WorkspaceDrawingEntity>) mutator,
  ) {
    setState(() {
      _undoStack.add(_currentSnapshot);
      _redoStack.clear();
      _drawings = mutator(List.of(_drawings));
    });
  }

  void _createDrawing(WorkspaceDrawingEntity draft) {
    setState(() {
      _undoStack.add(_currentSnapshot);
      _redoStack.clear();
      final entity = WorkspaceDrawingEntity(
        id: _nextDrawingId++,
        type: draft.type,
        points: draft.points,
        createdAt: draft.createdAt,
        updatedAt: draft.updatedAt,
      );
      _drawings = [..._drawings, entity];
      _selectedDrawingId = entity.id;
    });
  }

  void _restoreSnapshot(_WorkspaceSnapshot snapshot) {
    _tasks = snapshot.tasks;
    _drawings = snapshot.drawings;
    if (_selectedTaskId != null && !_tasks.any((t) => t.id == _selectedTaskId)) {
      _selectedTaskId = null;
    }
    if (_selectedDrawingId != null && !_drawings.any((d) => d.id == _selectedDrawingId)) {
      _selectedDrawingId = null;
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(_currentSnapshot);
      _restoreSnapshot(_undoStack.removeLast());
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(_currentSnapshot);
      _restoreSnapshot(_redoStack.removeLast());
    });
  }

  void _selectDrawing(int? id) => setState(() => _selectedDrawingId = id);

  /// "지우기" 도구/선택된 도형 삭제 — 기존 [_deleteSelected](작업 항목
  /// 삭제)와 같은 원칙으로, 항상 Undo 이력에 남긴다.
  void _deleteSelectedDrawing() {
    final id = _selectedDrawingId;
    if (id == null) return;
    _mutateDrawings((drawings) => drawings.where((d) => d.id != id).toList());
    setState(() => _selectedDrawingId = null);
  }

  void _resetViewport() => setState(() => _viewport = WorkspaceViewportTransform.identity);

  /// [WorkspaceDrawingLayer.onCanvasSizeChanged]가 보고한 실측 크기 —
  /// §13 확대/축소 버튼이 화면 중심을 기준으로 zoom하는 데 쓴다.
  Size _canvasSize = const Size(800, 600);

  void _zoomStep(double factor) {
    setState(() {
      final center = Offset(_canvasSize.width / 2, _canvasSize.height / 2);
      _viewport = _viewport.zoomBy(factor, focalPoint: center);
    });
  }

  /// §13/§20 — 확대/축소/지우기는 "도구 모드"가 아니라 눌렀을 때 바로
  /// 실행되는 1회성 동작이다(그 외 도구는 기존과 동일하게 활성 모드를
  /// 바꾼다).
  void _onToolSelected(WorkspaceSelectionTool tool) {
    switch (tool) {
      case WorkspaceSelectionTool.zoomIn:
        _zoomStep(1.25);
      case WorkspaceSelectionTool.zoomOut:
        _zoomStep(0.8);
      case WorkspaceSelectionTool.erase:
        _deleteSelectedDrawing();
      case WorkspaceSelectionTool.select:
      case WorkspaceSelectionTool.line:
      case WorkspaceSelectionTool.curve:
      case WorkspaceSelectionTool.circle:
      case WorkspaceSelectionTool.freeform:
      case WorkspaceSelectionTool.move:
        setState(() => _tool = tool);
    }
  }

  void _updateSelected(WorkspaceTaskItem Function(WorkspaceTaskItem) update) {
    final id = _selectedTaskId;
    if (id == null) return;
    _mutate(
      (tasks) => [
        for (final task in tasks)
          if (task.id == id) update(task) else task,
      ],
    );
  }

  void _onStartMethodSelected(WorkspaceStartMethod method) {
    if (method == WorkspaceStartMethod.floorPlanUpload) {
      setState(() => _startMethod = method);
    } else if (method == WorkspaceStartMethod.drawManually) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${method.title}"은(는) 준비 중입니다. 곧 지원할 예정입니다.')),
      );
    } else {
      _openPhotoConvert();
    }
  }

  /// "사진으로 변환" — 기존 [PhotoSelectScreen]의 카메라/갤러리 선택 기능을
  /// 화면을 다시 만들지 않고 그대로 불러온다. 이 화면 위에 push하므로
  /// 완료/뒤로가기 모두 이 MASTER 화면으로 돌아온다.
  Future<void> _openPhotoConvert() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PhotoSelectScreen(),
        settings: const RouteSettings(name: 'photo_select'),
      ),
    );
  }

  /// 좌측 하단 "설정" — MASTER 공통 기능이라 시작 방식과 무관하게 항상
  /// 같은 자리에서 진입한다. push로 열어 뒤로가기 시 이 화면의 State가
  /// 그대로 남아있게 해, 업로드한 평면도/View/선택 상태가 초기화되지
  /// 않는다.
  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final task = _selectedTask;

    // 실기 FAIL 재수정 WO(2번) — "3D 아이소 → 2D 평면도로 돌아가기"를
    // Android system back(제스처/버튼)에서도 지원한다. 3D 상태일 때는
    // 화면을 나가지 않고 2D로만 되돌린다 — 이미 분석/생성된 데이터는
    // 그대로 유지된다(canPop=false로 상위 pop 자체를 막고, 여기서
    // "단계만" 이동한다).
    return PopScope(
      canPop: _viewMode == WorkspaceViewMode.plan2d,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_viewMode != WorkspaceViewMode.plan2d) {
          setState(() => _viewMode = WorkspaceViewMode.plan2d);
        }
      },
      child: Scaffold(
        backgroundColor: SpaceShiftColors.background,
        appBar: AppBar(
          title: const Text('평면도 업로드 작업실'),
          backgroundColor: SpaceShiftColors.background,
          foregroundColor: SpaceShiftColors.textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 800;
                return isWide ? _buildWideBody(task) : _buildNarrowBody(task);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideBody(WorkspaceTaskItem? task) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: StartMethodPanel(
                    selected: _startMethod,
                    onSelected: _onStartMethodSelected,
                    floorPlanFile: _floorPlanFile,
                    onPickFloorPlanFile: _pickFloorPlan,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SettingsEntryButton(onTap: _openSettings),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _buildCenterColumn(task)),
        const SizedBox(width: 16),
        SizedBox(
          width: 320,
          child: UserWorkspacePanel(
            task: task,
            projectName: widget.projectName,
            taskCount: _tasks.length,
            visibleTaskCount: _tasks.where((t) => t.visible).length,
            viewMode: _viewMode,
            hasFloorPlanFile: _floorPlanFile != null,
            analysisPhase: _analysisPhase,
            analysisStep: _analysisStep,
            analysisResult: _analysisResult,
            analysisFailureMessage: _analysisFailureMessage,
            onReanalyze: _onReanalyzeRequested,
            cad: _cadWorkspaceState,
            cadCallbacks: _cadWorkspaceCallbacks,
            selectedTool: _tool,
            onToolSelected: _onToolSelected,
            onToggleVisible: () =>
                _updateSelected((t) => t.copyWith(visible: !t.visible)),
            onToggleLocked: () =>
                _updateSelected((t) => t.copyWith(locked: !t.locked)),
            onRename: () => _showRenameDialog(task),
            onDuplicate: _duplicateSelected,
            onDelete: _deleteSelected,
            onHeightChanged: (value) =>
                _updateSelected((t) => t.copyWith(heightMm: value)),
            onWidthChanged: (value) =>
                _updateSelected((t) => t.copyWith(widthMm: value)),
            onThicknessChanged: (value) =>
                _updateSelected((t) => t.copyWith(thicknessMm: value)),
            onFinishSelected: (value) =>
                _updateSelected((t) => t.copyWith(finishLabel: value)),
            onColorChanged: (value) =>
                _updateSelected((t) => t.copyWith(color: value)),
            canUndo: _undoStack.isNotEmpty,
            canRedo: _redoStack.isNotEmpty,
            onUndo: _undo,
            onRedo: _redo,
            analysisDebugStats: _analysisResult?.debugStats,
            selectedCadWall: _selectedCadWall,
            selectedCadOpening: _selectedCadOpening,
            selectedCadRoom: _selectedCadRoom,
            cadScale: _scale,
            cadSourceWidthPx: _cadFloorPlan?.sourceWidthPx ?? 0,
            cadSourceHeightPx: _cadFloorPlan?.sourceHeightPx ?? 0,
            canUndoCad: _cadUndoStack.isNotEmpty,
            onUndoCad: _undoCad,
            onDeleteCad: _deleteSelectedCadObject,
            onCreateWorkItemFromCad: _createWorkItemFromCad,
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowBody(WorkspaceTaskItem? task) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StartMethodPanel(
            selected: _startMethod,
            onSelected: _onStartMethodSelected,
            floorPlanFile: _floorPlanFile,
            onPickFloorPlanFile: _pickFloorPlan,
          ),
          const SizedBox(height: 12),
          SettingsEntryButton(onTap: _openSettings),
          const SizedBox(height: 16),
          Center(
            child: WorkspaceViewSwitcher(
              selected: _viewMode,
              onSelected: (mode) => setState(() => _viewMode = mode),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: WorkspaceCanvas(
              tasks: _tasks,
              selectedId: _selectedTaskId,
              onSelect: (id) => setState(() {
                _selectedTaskId = id;
                _selectedCadObjectId = null;
              }),
              viewMode: _viewMode,
              floorPlanFile: _floorPlanFile,
              analysisResult: _analysisResult,
              cad: _cadWorkspaceState,
              cadCallbacks: _cadWorkspaceCallbacks,
              onPickFloorPlanFile: _pickFloorPlan,
              spaceScene: _spaceScene,
              spaceSceneV2: _spaceSceneV2,
              spaceGenerationFailureMessage: _spaceGenerationFailureMessage,
              onExitTo2D: () =>
                  setState(() => _viewMode = WorkspaceViewMode.plan2d),
              tool: _tool,
              drawings: _drawings,
              selectedDrawingId: _selectedDrawingId,
              viewport: _viewport,
              onCreateDrawing: _createDrawing,
              onSelectDrawing: _selectDrawing,
              onViewportChanged: (v) => setState(() => _viewport = v),
              onCanvasSizeChanged: (s) => _canvasSize = s,
            ),
          ),
          if (_showEditDebugInfo)
            _EditDebugInfoBar(
              tool: _tool,
              drawingCount: _drawings.length,
              zoomPercent: (_viewport.scale * 100).round(),
              selectedId: _selectedDrawingId,
              onTap: _resetViewport,
              onLongPress: () => setState(() => _showEditDebugInfo = false),
            ),
          const SizedBox(height: 12),
          WorkspaceTaskList(
            tasks: _tasks,
            selectedId: _selectedTaskId,
            onSelect: (id) => setState(() {
              _selectedTaskId = id;
              _selectedCadObjectId = null;
            }),
            onToggleVisible: (id) => _mutate(
              (tasks) => [
                for (final t in tasks)
                  if (t.id == id) t.copyWith(visible: !t.visible) else t,
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 560,
            child: UserWorkspacePanel(
              task: task,
              projectName: widget.projectName,
              taskCount: _tasks.length,
              visibleTaskCount: _tasks.where((t) => t.visible).length,
              viewMode: _viewMode,
              hasFloorPlanFile: _floorPlanFile != null,
              analysisPhase: _analysisPhase,
              analysisStep: _analysisStep,
              analysisResult: _analysisResult,
              analysisFailureMessage: _analysisFailureMessage,
              onReanalyze: _onReanalyzeRequested,
              cad: _cadWorkspaceState,
              cadCallbacks: _cadWorkspaceCallbacks,
              selectedTool: _tool,
              onToolSelected: _onToolSelected,
              onToggleVisible: () =>
                  _updateSelected((t) => t.copyWith(visible: !t.visible)),
              onToggleLocked: () =>
                  _updateSelected((t) => t.copyWith(locked: !t.locked)),
              onRename: () => _showRenameDialog(task),
              onDuplicate: _duplicateSelected,
              onDelete: _deleteSelected,
              onHeightChanged: (value) =>
                  _updateSelected((t) => t.copyWith(heightMm: value)),
              onWidthChanged: (value) =>
                  _updateSelected((t) => t.copyWith(widthMm: value)),
              onThicknessChanged: (value) =>
                  _updateSelected((t) => t.copyWith(thicknessMm: value)),
              onFinishSelected: (value) =>
                  _updateSelected((t) => t.copyWith(finishLabel: value)),
              onColorChanged: (value) =>
                  _updateSelected((t) => t.copyWith(color: value)),
              canUndo: _undoStack.isNotEmpty,
              canRedo: _redoStack.isNotEmpty,
              onUndo: _undo,
              onRedo: _redo,
              analysisDebugStats: _analysisResult?.debugStats,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterColumn(WorkspaceTaskItem? task) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: WorkspaceViewSwitcher(
            selected: _viewMode,
            onSelected: (mode) => setState(() => _viewMode = mode),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: WorkspaceCanvas(
            tasks: _tasks,
            selectedId: _selectedTaskId,
            onSelect: (id) => setState(() {
              _selectedTaskId = id;
              _selectedCadObjectId = null;
            }),
            viewMode: _viewMode,
            floorPlanFile: _floorPlanFile,
            analysisResult: _analysisResult,
            cad: _cadWorkspaceState,
            cadCallbacks: _cadWorkspaceCallbacks,
            onPickFloorPlanFile: _pickFloorPlan,
            spaceScene: _spaceScene,
            spaceSceneV2: _spaceSceneV2,
            spaceGenerationFailureMessage: _spaceGenerationFailureMessage,
            onExitTo2D: () =>
                setState(() => _viewMode = WorkspaceViewMode.plan2d),
            tool: _tool,
            drawings: _drawings,
            selectedDrawingId: _selectedDrawingId,
            viewport: _viewport,
            onCreateDrawing: _createDrawing,
            onSelectDrawing: _selectDrawing,
            onViewportChanged: (v) => setState(() => _viewport = v),
            onCanvasSizeChanged: (s) => _canvasSize = s,
          ),
        ),
        if (_showEditDebugInfo)
          _EditDebugInfoBar(
            tool: _tool,
            drawingCount: _drawings.length,
            zoomPercent: (_viewport.scale * 100).round(),
            selectedId: _selectedDrawingId,
            onTap: _resetViewport,
            onLongPress: () => setState(() => _showEditDebugInfo = false),
          ),
        const SizedBox(height: 12),
        WorkspaceTaskList(
          tasks: _tasks,
          selectedId: _selectedTaskId,
          onSelect: (id) => setState(() {
            _selectedTaskId = id;
            _selectedCadObjectId = null;
          }),
          onToggleVisible: (id) => _mutate(
            (tasks) => [
              for (final t in tasks)
                if (t.id == id) t.copyWith(visible: !t.visible) else t,
            ],
          ),
        ),
      ],
    );
  }

  void _duplicateSelected() {
    final task = _selectedTask;
    if (task == null) return;
    _mutate((tasks) {
      final nextNumber = tasks.length + 1;
      final nextId = tasks.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
      final copy = WorkspaceTaskItem(
        id: nextId,
        number: nextNumber,
        name: '${task.name} 사본',
        category: task.category,
        finishLabel: task.finishLabel,
        color: task.color,
        markerPosition: task.markerPosition + const Offset(0.04, 0.04),
        heightMm: task.heightMm,
        widthMm: task.widthMm,
        thicknessMm: task.thicknessMm,
      );
      return [...tasks, copy];
    });
    setState(() => _selectedTaskId = _tasks.last.id);
  }

  void _deleteSelected() {
    final id = _selectedTaskId;
    if (id == null) return;
    _mutate((tasks) => tasks.where((t) => t.id != id).toList());
    setState(() => _selectedTaskId = null);
  }

  Future<void> _showRenameDialog(WorkspaceTaskItem? task) async {
    if (task == null) return;
    final controller = TextEditingController(text: task.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      _updateSelected((t) => t.copyWith(name: result));
    }
  }
}

/// WO089 §17 TAB TEST UI — Galaxy Tab에서 편집 상태를 즉시 확인할 수
/// 있는 작은 표시줄. 화면을 가리지 않도록 한 줄, 작은 글씨로만 표시하고
/// (§17), [_showEditDebugInfo]로 언제든 끌 수 있다(릴리스에서 숨기는
/// 구조).
class _EditDebugInfoBar extends StatelessWidget {
  const _EditDebugInfoBar({
    required this.tool,
    required this.drawingCount,
    required this.zoomPercent,
    required this.selectedId,
    required this.onTap,
    required this.onLongPress,
  });

  final WorkspaceSelectionTool tool;
  final int drawingCount;
  final int zoomPercent;
  final int? selectedId;

  /// 탭하면 zoom/pan을 초기화한다(§12 "reset/fit behavior").
  final VoidCallback onTap;

  /// 길게 누르면 이 표시줄 자체를 숨긴다(§17 "release에서 숨길 수 있는
  /// debug flag 구조").
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          '편집 모드: ${tool.label}  ·  도형: $drawingCount  ·  Zoom: $zoomPercent%(탭=초기화)  ·  선택: ${selectedId ?? '없음'}',
          style: const TextStyle(fontSize: 10, color: Colors.black45),
        ),
      ),
    );
  }
}
