/// SS016 — MASTER UI 12(최종 ISO·투시도·결과 확인·내보내기). SS015([IsoRenderingScreen])가
/// [SsDataSlot.renderData]에 완료 표시를 남긴 뒤 넘어오는 마지막 화면이다. 3D geometry/카메라
/// 조작 엔진은 새로 만들지 않고 SS013([IsoEditorScreen])이 쓰는 것과 같은 [buildIsoEditorScene] +
/// [Space3DViewGpuV2](Orbit/Pan/Zoom/탭 선택이 이미 구현돼 있다)를 그대로 재사용한다 — 이 화면은
/// "보기 전용 검토"만 더한다(평면/정면/측면/ISO/투시 뷰 전환, 공간별 확인, 선택 요소에서 수정으로
/// 복귀, 재렌더링으로 이동, 최종 저장, 이미지 Export).
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../core/ss_editing.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_router.dart' show SsStageHeader;
import '../core/ss_stage.dart';
import '../models/cad_floor_plan.dart' show CadRoom;
import '../models/space_scene_v2.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_iso_design_extras.dart';
import '../models/ss_spatial_model.dart' show SSRoomType;
import '../services/iso_conversion_input_builder.dart' show sceneFromCadDataPayload;
import '../services/iso_conversion_service.dart' show kIsoDefaultCeilingHeightMm;
import '../services/ss_image_export_service.dart';
import '../services/ss_iso_editor_scene_builder.dart' show buildIsoEditorScene;
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';
import '../widgets/workspace/space_3d_view_gpu_v2.dart';

enum _FinalResultLoad { loading, loaded, missingInput, error }

class FinalResultScreen extends StatefulWidget {
  const FinalResultScreen({super.key, this.projectId, this.projectStore, this.exportService = const SsImageExportService()});

  /// 결과를 확인할 프로젝트 id.
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  /// 파일 내보내기(테스트에서 가짜 구현으로 교체 가능 — file_saver는 테스트 환경에 실제 플랫폼 채널이 없다).
  final SsImageExportService exportService;

  @override
  State<FinalResultScreen> createState() => _FinalResultScreenState();
}

class _FinalResultScreenState extends State<FinalResultScreen> {
  _FinalResultLoad _state = _FinalResultLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  SpaceSceneV2? _scene;
  List<CadRoom> _rooms = const [];
  List<String> _warnings = const [];

  Space3DCameraMode _cameraMode = Space3DCameraMode.isometric;
  SpaceObjectIdentityV2? _selected;
  final GlobalKey _captureKey = GlobalKey();

  SsExportFormat _format = SsExportFormat.png;
  double _jpgQuality = 90;
  bool _chooseLocation = false;
  bool _exporting = false;
  SsExportJob? _exportJob;
  final TextEditingController _fileName = TextEditingController(text: 'space_shift_final_result');

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final pid = widget.projectId;
    if (pid == null) {
      setState(() => _state = _FinalResultLoad.error);
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _FinalResultLoad.error);
        return;
      }
      final cadSlot = project.data[SsDataSlot.cadData];
      if (cadSlot == null) {
        if (!mounted) return;
        setState(() {
          _store = store;
          _project = project;
          _state = _FinalResultLoad.missingInput;
        });
        return;
      }
      final cad = sceneFromCadDataPayload(cadSlot.payload);
      if (cad == null) {
        if (!mounted) return;
        setState(() => _state = _FinalResultLoad.error);
        return;
      }
      final isoSlot = project.data[SsDataSlot.isoData];
      final extras = SsIsoDesignExtras.tryFromJson(isoSlot?.payload['design']);
      final renderSlot = project.data[SsDataSlot.renderData];
      final warningsJson = renderSlot?.payload['warnings'];
      final warnings = warningsJson is List ? [for (final w in warningsJson) '$w'] : const <String>[];
      final scene = _tryBuildScene(cad, extras);
      if (!mounted) return;
      setState(() {
        _store = store;
        _project = project;
        _scene = scene;
        _rooms = cad.plan.rooms;
        _warnings = warnings;
        _state = _FinalResultLoad.loaded;
      });
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제 원인은 로그로 남기고
      // 사용자에게는 일반 안내만 보인다.
      debugPrint('FinalResultScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _FinalResultLoad.error);
    }
  }

  /// [buildIsoEditorScene]은 결정적 순수 함수라 몇 번을 다시 불러도 안전하다(SS013/SS015와 같은
  /// 재사용 — 새 3D 엔진을 만들지 않는다). 실패해도 존재하지 않는 3D를 지어내지 않고 조용히 null을
  /// 돌려준다(빈 scene 안내로 넘어간다).
  SpaceSceneV2? _tryBuildScene(SsCadScene cad, SsIsoDesignExtras extras) {
    try {
      final scene = buildIsoEditorScene(cad: cad, extras: extras, ceilingHeightMm: kIsoDefaultCeilingHeightMm);
      return scene;
    } catch (e, st) {
      debugPrint('FinalResultScreen._tryBuildScene 실패 (${e.runtimeType}): $e\n$st');
      return null;
    }
  }

  void _backToPreviousStage() {
    final project = _project;
    final previous = project == null ? null : SsFlows.previous(project.sourceType, SsStage.finalResult);
    final navigator = Navigator.of(context);
    if (previous == null) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    navigator.pushReplacementNamed(previous.routeName, arguments: widget.projectId);
  }

  /// §구현 범위 "선택 요소 또는 공간에서 수정작업으로 복귀" — 3D 디자인 화면(SS013)으로 돌아간다.
  /// 그 화면이 이미 전체 편집(마감재/가구/조명/설비)을 다루므로 여기서 다시 구현하지 않는다. 돌아오면
  /// 수정된 내용을 다시 읽도록 새로 불러온다.
  Future<void> _editSelected() async {
    await Navigator.of(context).pushNamed(SsStage.isoEditor.routeName, arguments: widget.projectId);
    if (!mounted) return;
    unawaited(_load());
  }

  /// §구현 범위 "수정 후 필요한 범위의 재렌더링 연결" — 3D 렌더링 화면(SS015)이 이미 "바뀐 디자인이면
  /// 자동으로 다시 렌더링, 최신이면 다시 렌더링하지 않음"을 판정하므로 그 화면으로 보내기만 한다.
  Future<void> _goRerender() async {
    await Navigator.of(context).pushNamed(SsStage.isoRendering.routeName, arguments: widget.projectId);
    if (!mounted) return;
    unawaited(_load());
  }

  Future<void> _saveFinal() async {
    final store = _store;
    final project = _project;
    if (store == null || project == null) return;
    try {
      await store.save(project);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('저장했습니다', key: Key('ssFinalResultSaveSnackbar')), duration: Duration(seconds: 2)));
    } catch (e, st) {
      debugPrint('FinalResultScreen 저장 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('저장하지 못했습니다. 다시 시도해주세요.', key: Key('ssFinalResultSaveFailSnackbar'))));
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    final name = _fileName.text.trim().isEmpty ? 'space_shift_final_result' : _fileName.text.trim();
    final job = SsExportJob(fileName: name, format: _format);
    setState(() {
      _exporting = true;
      _exportJob = job.started();
    });
    try {
      final bytes = await _captureBytes();
      if (bytes == null) {
        if (!mounted) return;
        setState(() {
          _exporting = false;
          _exportJob = job.failedWith('지금 화면을 이미지로 만들지 못했습니다. 다시 시도해주세요.');
        });
        return;
      }
      final savedTo = await widget.exportService.save(bytes, job, jpgQuality: _jpgQuality.round(), chooseLocation: _chooseLocation);
      if (!mounted) return;
      if (savedTo == null) {
        // 저장 위치 선택을 취소한 경우 — 실패가 아니라 그냥 처음 상태로 돌아간다.
        setState(() {
          _exporting = false;
          _exportJob = null;
        });
        return;
      }
      setState(() {
        _exporting = false;
        _exportJob = job.succeeded(savedTo);
      });
    } catch (e, st) {
      // 화면 캡처/로컬 파일 저장 실패를 "네트워크 오류"로 잘못 알리지 않는다 — 실제 원인은 로그로, 사용자에겐
      // 일반 안내만 보여준다.
      debugPrint('FinalResultScreen 내보내기 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportJob = job.failedWith('파일을 저장하지 못했습니다. 다시 시도해주세요.');
      });
    }
  }

  /// 지금 뷰어에 보이는 화면(현재 View 모드 그대로)을 PNG bytes로 캡처한다 — 실시간 3D라 미리 만들어
  /// 둔 이미지 bytes가 없으므로, 보이는 그대로를 [RepaintBoundary]로 찍는다.
  Future<Uint8List?> _captureBytes() async {
    final renderObject = _captureKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final image = await renderObject.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  @override
  void dispose() {
    _fileName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _FinalResultLoad.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('최종 결과를 불러오지 못했습니다.', key: Key('ssFinalResultLoadError'), style: TextStyle(color: SsMasterTheme.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(key: const Key('ssFinalResultBackFromError'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
          ],
        ),
      );
    }
    if (_state == _FinalResultLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssFinalResultLoading')));
    }
    if (_state == _FinalResultLoad.missingInput) {
      return Padding(
        key: const Key('ssFinalResultScreen'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SsStageHeader(stage: SsStage.finalResult),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '아직 완성된 3D ISO 디자인이 없습니다. 먼저 3D 디자인과 렌더링을 완료해 주세요.',
                      key: Key('ssFinalResultMissingInput'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SsMasterTheme.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(key: const Key('ssFinalResultBackToPrevious'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      key: const Key('ssFinalResultScreen'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(flex: 3, child: _buildViewer()), const SizedBox(width: 20), SizedBox(width: 340, child: _buildRightPanel())],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: SsStageHeader(stage: SsStage.finalResult)),
        IconButton(
          key: const Key('ssFinalResultBack'),
          tooltip: '이전 단계로 돌아가기',
          onPressed: _backToPreviousStage,
          icon: const Icon(Icons.arrow_back, color: SsMasterTheme.textSecondary),
        ),
      ],
    );
  }

  /// §구현 범위 "최종 realistic ISO 중심 표시" + "Orbit/Zoom/Pan" + "평면/정면/측면/ISO View 접근" +
  /// "Perspective(투시도) 확인" — 전부 이미 검증된 [Space3DViewGpuV2]가 한다(새 3D 엔진을 만들지
  /// 않는다). geometry가 하나도 없으면 지어내지 않고 정직하게 안내만 보인다(IsoEditorScreen과 같은 생각).
  Widget _buildViewer() {
    final scene = _scene;
    final hasScene = scene != null && !scene.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildViewModeBar(),
        const SizedBox(height: 10),
        Expanded(
          child: RepaintBoundary(
            key: _captureKey,
            child: Container(
              key: const Key('ssFinalResultViewerBox'),
              decoration: BoxDecoration(color: const Color(0xFF081628), borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
              clipBehavior: Clip.antiAlias,
              child: hasScene
                  ? Space3DViewGpuV2(
                      key: const Key('ssFinalResultSpace3D'),
                      scene: scene,
                      cameraMode: _cameraMode,
                      selectedObjectId: _selected?.objectId,
                      onObjectSelected: (id) => setState(() => _selected = id),
                    )
                  : const Center(
                      child: Text('표시할 3D 모델이 없습니다.', key: Key('ssFinalResultEmptyScene'), style: TextStyle(color: SsMasterTheme.textSecondary)),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  static const _viewModes = [
    (Space3DCameraMode.plan, '평면', Icons.grid_on),
    (Space3DCameraMode.front, '정면', Icons.crop_square_outlined),
    (Space3DCameraMode.side, '측면', Icons.view_sidebar_outlined),
    (Space3DCameraMode.isometric, 'ISO', Icons.view_in_ar_outlined),
    (Space3DCameraMode.perspective, '투시', Icons.visibility_outlined),
  ];

  Widget _buildViewModeBar() {
    return Container(
      key: const Key('ssFinalResultViewModeBar'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Wrap(
        spacing: 8,
        children: [
          for (final mode in _viewModes)
            ChoiceChip(
              key: Key('ssFinalResultView_${mode.$1.name}'),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(mode.$3, size: 14), const SizedBox(width: 4), Text(mode.$2, style: const TextStyle(fontSize: 12))],
              ),
              selected: _cameraMode == mode.$1,
              onSelected: (_) => setState(() => _cameraMode = mode.$1),
            ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return SingleChildScrollView(
      key: const Key('ssFinalResultSidePanel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_warnings.isNotEmpty) ...[_buildWarningsPanel(), const SizedBox(height: 14)],
          _buildSpacesPanel(),
          const SizedBox(height: 14),
          _buildSelectionPanel(),
          const SizedBox(height: 14),
          _buildExportPanel(),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('ssFinalResultSaveButton'),
              onPressed: () => unawaited(_saveFinal()),
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('최종 저장'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({Key? key, required String title, required Widget child}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)), const SizedBox(height: 10), child],
      ),
    );
  }

  Widget _buildWarningsPanel() {
    return _panel(
      key: const Key('ssFinalResultWarnings'),
      title: '안내',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in _warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: SsMasterTheme.neonCyan),
                  const SizedBox(width: 6),
                  Expanded(child: Text(w, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// §구현 범위 "공간별 확인" — 방 목록에서 고르면 그 바닥을 3D에서 강조한다(이미 있는
  /// [Space3DViewGpuV2.selectedObjectId] 하이라이트 메커니즘을 그대로 쓴다, 새로 만들지 않음).
  Widget _buildSpacesPanel() {
    return _panel(
      key: const Key('ssFinalResultSpacesPanel'),
      title: '공간별 확인',
      child: _rooms.isEmpty
          ? const Text('확인할 공간이 없습니다.', key: Key('ssFinalResultNoSpaces'), style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var i = 0; i < _rooms.length; i++) _buildSpaceRow(_rooms[i], i)]),
    );
  }

  Widget _buildSpaceRow(CadRoom room, int index) {
    final objectId = 'floor:${room.id}';
    final selected = _selected?.objectId == objectId;
    final rawName = room.name?.trim() ?? '';
    final label = rawName.isNotEmpty ? rawName : (room.roomType == SSRoomType.bathroom ? '욕실' : '공간 ${index + 1}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('ssFinalResultSpace_${room.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(
            () => _selected = SpaceObjectIdentityV2(objectId: objectId, sourceKind: SpaceElementKindV2.floor, sourceId: room.id, roomId: room.id),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(gradient: selected ? SsMasterTheme.selectedItem : null, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(Icons.door_back_door_outlined, size: 16, color: selected ? Colors.white : SsMasterTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 13, color: selected ? Colors.white : SsMasterTheme.textPrimary, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// MASTER UI 12 "수정작업 · 선택 요소/요소 속성" — 읽기 전용 요약만 보인다(실제 속성 편집은
  /// SS013/SS014의 몫, 여기서 다시 구현하지 않는다). "수정하러 가기"가 §구현 범위 "선택 요소 또는
  /// 공간에서 수정작업으로 복귀"를 한다.
  Widget _buildSelectionPanel() {
    final sel = _selected;
    return _panel(
      key: const Key('ssFinalResultSelectionPanel'),
      title: '선택 요소',
      child: sel == null
          ? const Text('요소를 선택해주세요.', key: Key('ssFinalResultNoSelection'), style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _selRow('종류', _kindLabel(sel.sourceKind), valueKey: const Key('ssFinalResultSelectedKind')),
                if (sel.dimensions?.heightMm != null) _selRow('높이', '${sel.dimensions!.heightMm!.round()}mm'),
                if (sel.dimensions?.widthMm != null) _selRow('폭', '${sel.dimensions!.widthMm!.round()}mm'),
                if (sel.dimensions?.thicknessMm != null) _selRow('두께', '${sel.dimensions!.thicknessMm!.round()}mm'),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('ssFinalResultEditSelected'),
                    onPressed: () => unawaited(_editSelected()),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('수정하러 가기'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _selRow(String label, String value, {Key? valueKey}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
        Text(value, key: valueKey, style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    ),
  );

  String _kindLabel(SpaceElementKindV2 kind) => switch (kind) {
    SpaceElementKindV2.wall => '벽',
    SpaceElementKindV2.floor => '바닥',
    SpaceElementKindV2.ceiling => '천장',
    SpaceElementKindV2.opening => '개구부',
    SpaceElementKindV2.furniture => '가구',
    SpaceElementKindV2.light => '조명',
    SpaceElementKindV2.other => '설비',
  };

  /// §구현 범위 "지원되는 ISO/렌더 이미지/결과 파일 Export" + "파일명/형식/저장 위치/성공·실패 UX" —
  /// 기존 [SsImageExportService](PNG/JPG, file_saver, SS007과 같은 서비스)를 그대로 재사용한다.
  Widget _buildExportPanel() {
    return _panel(
      key: const Key('ssFinalResultExportPanel'),
      title: '파일 내보내기',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('형식', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final f in const [SsExportFormat.png, SsExportFormat.jpg])
                ChoiceChip(
                  key: Key('ssFinalResultFormat_${f.name}'),
                  label: Text(f.label, style: const TextStyle(fontSize: 12)),
                  selected: _format == f,
                  onSelected: (_) => setState(() => _format = f),
                ),
            ],
          ),
          if (_format == SsExportFormat.jpg) ...[
            const SizedBox(height: 14),
            Text('화질 ${_jpgQuality.round()}', style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
            Slider(
              key: const Key('ssFinalResultJpgQuality'),
              value: _jpgQuality,
              min: 50,
              max: 100,
              divisions: 50,
              label: '${_jpgQuality.round()}',
              onChanged: (v) => setState(() => _jpgQuality = v),
            ),
          ],
          const SizedBox(height: 14),
          const Text('파일 이름', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            key: const Key('ssFinalResultFileName'),
            controller: _fileName,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(isDense: true, hintText: '파일 이름'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(key: const Key('ssFinalResultChooseLocation'), value: _chooseLocation, onChanged: (v) => setState(() => _chooseLocation = v ?? false)),
              const Expanded(child: Text('저장 위치 직접 선택', style: TextStyle(color: Colors.white, fontSize: 12))),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('ssFinalResultExportButton'),
              onPressed: _exporting ? null : () => unawaited(_export()),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(_exporting ? '내보내는 중…' : '내보내기'),
            ),
          ),
          if (_exportJob != null) ...[const SizedBox(height: 10), _buildExportStatusBanner(_exportJob!)],
          const SizedBox(height: 14),
          const Divider(color: SsMasterTheme.panelBorder),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('ssFinalResultRerenderButton'),
              onPressed: () => unawaited(_goRerender()),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('다시 렌더링'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportStatusBanner(SsExportJob job) {
    final (color, text) = switch (job.status) {
      SsExportStatus.exporting => (SsMasterTheme.neonBlue, '내보내는 중…'),
      SsExportStatus.succeeded => (Colors.greenAccent, '저장했습니다 (${job.fullName})'),
      SsExportStatus.failed => (Colors.redAccent, job.error ?? '내보내기에 실패했습니다.'),
      SsExportStatus.pending => (SsMasterTheme.textSecondary, '내보낼 준비가 되었습니다.'),
    };
    return Container(
      key: const Key('ssFinalResultExportStatus'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
