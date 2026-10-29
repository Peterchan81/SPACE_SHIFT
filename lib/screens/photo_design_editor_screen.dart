/// SS006 — MASTER UI 4-2(실제 공간 이미지 AI 디자인 에디터). 사용자가 실제 공간 사진을 올리고 그 사진
/// 위에서 직접 인테리어 디자인(객체 선택/삭제/복원, 가구 추가·교체·이동, 벽·바닥·천장 재질·색상, 조명,
/// 벽체 개구부)을 지시하는 화면이다. 이 FLOW(SsSourceType.imageTransform)는 CAD/3D FLOW와 분리된다
/// (SsFlows 주석 참고). 공통 상단바([SsTopBar])·좌측 메뉴([SsNavRail])는 [SsRouter]가 [SsStageScreen]으로
/// 이미 감싸준다 — 이 화면은 그 안쪽(도구모음+캔버스+우측 패널+하단 바)만 그린다.
///
/// 실제 AI 픽셀 재생성(배경 복원·재질 적용 결과 이미지 만들기)은 다음 단계 SS007(이미지 AI 렌더링)이
/// 한다 — 이 화면은 "무엇을 바꿀지" 지시를 만들고 Before/After·Undo/Redo/History로 확인·되돌릴 수 있게
/// 하는 것까지가 범위다(§ 구현 범위). 원본 사진은 [SsProject.sourceData]에 한 번만 저장되어 항상 보존되고
/// (§5), 편집 지시는 [SsProject.userCorrections]에 커밋마다 자동저장된다(DirectDrawScreen과 같은 패턴).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/ss_photo_editor_controller.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_stage.dart';
import '../models/ss_photo_scene.dart';
import '../services/image_picker_service.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';

enum _PhotoLoad { loading, loaded, error }

enum _RightTab { objects, finish, opening, furniture, lighting }

const List<String> _kFurnitureCatalog = ['소파', '암체어', '사이드테이블', '러그', '스탠드 조명', '책장'];

const List<(String, String, int)> _kMaterialSwatches = [
  ('ivory', '아이보리', 0xFFEFE7DA),
  ('lightGray', '라이트그레이', 0xFFD9DEE3),
  ('beige', '베이지', 0xFFE3C9A6),
  ('gray', '그레이', 0xFFB7BDC4),
  ('darkGray', '다크그레이', 0xFF6E7479),
  ('walnut', '월넛', 0xFF8B5A2B),
];

const List<(String, String, double, double)> _kLightingPresets = [
  ('warmCozy', '따뜻한 조명', 0.8, 0.6),
  ('coolBright', '시원한 조명', 0.2, 0.9),
  ('natural', '자연광', 0.5, 0.7),
  ('dim', '은은한 조명', 0.6, 0.3),
];

class PhotoDesignEditorScreen extends StatefulWidget {
  const PhotoDesignEditorScreen({super.key, this.projectId, this.projectStore, this.imagePickerService = const ImagePickerService()});

  /// 연 프로젝트 id(없으면 프로젝트 없이 맛보기만 — 자동저장은 하지 않는다).
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  /// 초기 사진 업로드에 쓴다(테스트에서 가짜 구현으로 교체 가능 — PhotoSelectScreen과 같은 패턴).
  final ImagePickerService imagePickerService;

  @override
  State<PhotoDesignEditorScreen> createState() => _PhotoDesignEditorScreenState();
}

class _PhotoDesignEditorScreenState extends State<PhotoDesignEditorScreen> {
  _PhotoLoad _state = _PhotoLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  SsAutosaveController? _autosave;
  SsPhotoEditorController? _editor;
  double _imageAspect = 4 / 3;
  bool _isUploading = false;
  _RightTab _rightTab = _RightTab.objects;
  SsPhotoSurface _selectedSurface = SsPhotoSurface.wall;
  String? _pendingFurnitureName;
  SsPhotoOpeningKind? _pendingOpeningKind;
  bool _aiRestoreBackground = true;
  final TextEditingController _memo = TextEditingController();
  final TransformationController _viewTransform = TransformationController();
  Offset _dragAccumulatedPx = Offset.zero;

  @override
  void initState() {
    super.initState();
    if (widget.projectId == null) {
      _state = _PhotoLoad.loaded;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final pid = widget.projectId!;
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _PhotoLoad.error);
        return;
      }
      final b64 = project.data[SsDataSlot.sourceData]?.payload['imageBase64'];
      Uint8List? bytes;
      if (b64 is String) {
        try {
          bytes = base64Decode(b64);
        } catch (e, st) {
          // 저장된 원본이 깨졌다고 네트워크 오류로 오분류하지 않는다 — 실제 원인은 로그로 남긴다.
          debugPrint('PhotoDesignEditorScreen 원본 사진 디코딩 실패 (${e.runtimeType}): $e\n$st');
        }
      }
      if (!mounted) return;
      final decoded = bytes;
      setState(() {
        _store = store;
        _project = project;
        if (decoded != null) {
          _autosave = SsAutosaveController(store: store, project: project);
          final scene = SsPhotoScene.fromEditJson(decoded, project.data[SsDataSlot.userCorrections]?.payload['edit']);
          _editor = SsPhotoEditorController(initialScene: scene)..history.addListener(_onCommitted);
          _imageAspect = _computeAspect(decoded);
        }
        _state = _PhotoLoad.loaded;
      });
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제 원인은 로그로, 사용자에겐 일반 안내만.
      debugPrint('PhotoDesignEditorScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _PhotoLoad.error);
    }
  }

  double _computeAspect(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.height > 0) return decoded.width / decoded.height;
    } catch (e, st) {
      debugPrint('PhotoDesignEditorScreen 사진 크기 분석 실패 (${e.runtimeType}): $e\n$st');
    }
    return 4 / 3;
  }

  /// History에 실제로 커밋된 변경만 자동저장한다(드래그 중 미리보기 프레임마다는 저장하지 않는다).
  void _onCommitted() {
    final autosave = _autosave;
    final editor = _editor;
    if (autosave == null || editor == null) return;
    final updated = autosave.project.withStageData(
      SsDataSlot.userCorrections,
      {'kind': 'photoEdit', 'edit': editor.scene.toEditJson()},
      label: editor.history.currentStep.label,
    );
    _project = updated;
    autosave.update(updated);
  }

  Future<void> _uploadInitialPhoto() async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    try {
      final bytes = await widget.imagePickerService.pickGalleryImage();
      if (bytes == null) return;
      final aspect = _computeAspect(bytes);
      _editor?.history.removeListener(_onCommitted);
      _editor?.dispose();
      final editor = SsPhotoEditorController(initialScene: SsPhotoScene(imageBytes: bytes))..history.addListener(_onCommitted);
      var project = _project;
      if (project != null && project.data[SsDataSlot.sourceData] == null) {
        try {
          project = project.withSource({'imageBase64': base64Encode(bytes)}, label: '원본 사진');
          final store = _store ?? widget.projectStore ?? await SsProjectStoreProvider.instance.store();
          _store = store;
          final autosave = SsAutosaveController(store: store, project: project);
          _autosave = autosave;
          await autosave.saveNow();
        } catch (e, st) {
          debugPrint('PhotoDesignEditorScreen 원본 사진 저장 실패 (${e.runtimeType}): $e\n$st');
        }
      }
      if (!mounted) return;
      setState(() {
        _project = project;
        _editor = editor;
        _imageAspect = aspect;
      });
    } catch (e, st) {
      debugPrint('PhotoDesignEditorScreen 사진 업로드 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('사진을 불러오지 못했습니다. 다시 시도해주세요.')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _goNext() async {
    final project = _project;
    final autosave = _autosave;
    if (project == null || autosave == null || _editor == null) return;
    await autosave.saveNow();
    final current = autosave.project;
    final next = SsFlows.next(current.sourceType, current.currentStage);
    if (next == null) return;
    final moved = current.moveTo(next);
    try {
      await (_store ?? autosave.store).save(moved);
    } catch (e, st) {
      debugPrint('PhotoDesignEditorScreen._goNext 저장 실패 (${e.runtimeType}): $e\n$st');
    }
    if (!mounted) return;
    await Navigator.of(context).pushNamed(next.routeName, arguments: project.info.id);
  }

  void _zoomBy(double factor) {
    setState(() => _viewTransform.value = _viewTransform.value.clone()..scale(factor));
  }

  void _resetView() {
    setState(() => _viewTransform.value = Matrix4.identity());
  }

  void _handleCanvasTap(SsPhotoEditorController editor, Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final norm = Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));
    switch (editor.tool) {
      case SsPhotoTool.select:
        editor.selectAt(norm);
      case SsPhotoTool.erase:
        editor.selectAt(norm);
        if (!editor.selection.isEmpty) editor.deleteSelected(aiRestoreBackground: _aiRestoreBackground);
      case SsPhotoTool.furnitureAdd:
        final name = _pendingFurnitureName;
        if (name == null) break;
        if (!editor.selection.isEmpty) {
          editor.replaceSelectedFurniture(name);
        } else {
          editor.addFurnitureAt(norm, name: name);
        }
      case SsPhotoTool.opening:
        final kind = _pendingOpeningKind;
        if (kind != null) editor.addOpeningAt(kind, norm);
      case SsPhotoTool.move:
      case SsPhotoTool.restore:
      case SsPhotoTool.retexture:
      case SsPhotoTool.colorChange:
        break;
    }
  }

  @override
  void dispose() {
    _editor?.history.removeListener(_onCommitted);
    _editor?.dispose();
    _autosave?.dispose();
    _memo.dispose();
    _viewTransform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _PhotoLoad.error) {
      return const Center(
        child: Text(
          '사진 작업을 불러오지 못했습니다. 프로젝트 관리에서 다시 열어주세요.',
          key: Key('ssPhotoLoadError'),
          style: TextStyle(color: SsMasterTheme.textSecondary),
        ),
      );
    }
    if (_state == _PhotoLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssPhotoLoading')));
    }
    final editor = _editor;
    if (editor == null) {
      return _buildUploadPrompt();
    }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) unawaited(_autosave?.saveNow());
      },
      child: ListenableBuilder(
        listenable: editor,
        builder: (context, _) => Column(
          key: const Key('ssPhotoScreen'),
          children: [
            _buildTopToolbar(editor),
            const Divider(height: 1, color: SsMasterTheme.panelBorder),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildCanvasArea(editor)),
                  Container(width: 1, color: SsMasterTheme.panelBorder),
                  _buildRightPanel(editor),
                ],
              ),
            ),
            const Divider(height: 1, color: SsMasterTheme.panelBorder),
            _buildBottomBar(editor),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('ssPhotoUploadPrompt'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_photo_alternate_outlined, size: 56, color: SsMasterTheme.textSecondary),
            const SizedBox(height: 16),
            const Text('실제 공간 사진을 올려주세요', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('사진 속 가구·마감·조명을 그대로 디자인할 수 있어요.', style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              key: const Key('ssPhotoUploadButton'),
              onPressed: _isUploading ? null : () => unawaited(_uploadInitialPhoto()),
              icon: const Icon(Icons.upload_outlined),
              label: Text(_isUploading ? '불러오는 중…' : '사진 선택'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopToolbar(SsPhotoEditorController editor) {
    return Container(
      key: const Key('ssPhotoTopToolbar'),
      height: 88,
      color: SsMasterTheme.panel,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _PhotoToolButton(toolKey: 'select', icon: Icons.near_me_outlined, label: '선택', selected: editor.tool == SsPhotoTool.select, onTap: () => editor.setTool(SsPhotoTool.select)),
            _PhotoToolButton(toolKey: 'move', icon: Icons.open_with, label: '이동', selected: editor.tool == SsPhotoTool.move, onTap: () => editor.setTool(SsPhotoTool.move)),
            _PhotoToolButton(toolKey: 'erase', icon: Icons.delete_outline, label: '지우기', selected: editor.tool == SsPhotoTool.erase, onTap: () => editor.setTool(SsPhotoTool.erase)),
            _PhotoToolButton(
              toolKey: 'restore',
              icon: Icons.restore,
              label: '복원',
              selected: editor.tool == SsPhotoTool.restore,
              onTap: () {
                editor.setTool(SsPhotoTool.restore);
                editor.restoreSelected();
                setState(() => _rightTab = _RightTab.objects);
              },
            ),
            _PhotoToolButton(
              toolKey: 'retexture',
              icon: Icons.texture_outlined,
              label: '재질 변경',
              selected: editor.tool == SsPhotoTool.retexture,
              onTap: () {
                editor.setTool(SsPhotoTool.retexture);
                setState(() => _rightTab = _RightTab.finish);
              },
            ),
            _PhotoToolButton(
              toolKey: 'colorChange',
              icon: Icons.palette_outlined,
              label: '색상 변경',
              selected: editor.tool == SsPhotoTool.colorChange,
              onTap: () {
                editor.setTool(SsPhotoTool.colorChange);
                setState(() => _rightTab = _RightTab.finish);
              },
            ),
            _PhotoToolButton(
              toolKey: 'opening',
              icon: Icons.door_sliding_outlined,
              label: '구멍 뚫기',
              selected: editor.tool == SsPhotoTool.opening,
              onTap: () {
                editor.setTool(SsPhotoTool.opening);
                setState(() => _rightTab = _RightTab.opening);
              },
            ),
            _PhotoToolButton(
              toolKey: 'furnitureAdd',
              icon: Icons.chair_outlined,
              label: '가구 추가',
              selected: editor.tool == SsPhotoTool.furnitureAdd,
              onTap: () {
                editor.setTool(SsPhotoTool.furnitureAdd);
                setState(() => _rightTab = _RightTab.furniture);
              },
            ),
            const SizedBox(width: 10),
            IconButton(key: const Key('ssPhotoUndo'), onPressed: editor.canUndo ? editor.undo : null, icon: const Icon(Icons.undo), color: SsMasterTheme.textSecondary),
            IconButton(key: const Key('ssPhotoRedo'), onPressed: editor.canRedo ? editor.redo : null, icon: const Icon(Icons.redo), color: SsMasterTheme.textSecondary),
            const SizedBox(width: 8),
            IconButton(key: const Key('ssPhotoZoomOut'), onPressed: () => _zoomBy(0.85), icon: const Icon(Icons.zoom_out), color: SsMasterTheme.textSecondary),
            IconButton(key: const Key('ssPhotoZoomIn'), onPressed: () => _zoomBy(1.15), icon: const Icon(Icons.zoom_in), color: SsMasterTheme.textSecondary),
            IconButton(key: const Key('ssPhotoFit'), onPressed: _resetView, icon: const Icon(Icons.fit_screen_outlined), color: SsMasterTheme.textSecondary),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const Key('ssPhotoBeforeAfterToggle'),
              onPressed: editor.toggleBeforeAfter,
              icon: Icon(editor.showOriginal ? Icons.visibility_outlined : Icons.compare_outlined, size: 18),
              label: Text(editor.showOriginal ? '원본(Before)' : '현재(After)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasArea(SsPhotoEditorController editor) {
    final scene = editor.scene;
    return Container(
      color: const Color(0xFF081628),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: AspectRatio(
          aspectRatio: _imageAspect,
          child: InteractiveViewer(
            key: const Key('ssPhotoViewer'),
            transformationController: _viewTransform,
            panEnabled: editor.tool != SsPhotoTool.move,
            scaleEnabled: true,
            minScale: 1,
            maxScale: 5,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return GestureDetector(
                  key: const Key('ssPhotoCanvas'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) => _handleCanvasTap(editor, details.localPosition, size),
                  onPanStart: editor.tool == SsPhotoTool.move
                      ? (_) {
                          _dragAccumulatedPx = Offset.zero;
                          editor.beginDrag();
                        }
                      : null,
                  onPanUpdate: editor.tool == SsPhotoTool.move
                      ? (d) {
                          if (!editor.isDragging || size.width <= 0 || size.height <= 0) return;
                          _dragAccumulatedPx += d.delta;
                          editor.updateDrag(_dragAccumulatedPx.dx / size.width, _dragAccumulatedPx.dy / size.height);
                        }
                      : null,
                  onPanEnd: editor.tool == SsPhotoTool.move
                      ? (_) {
                          if (editor.isDragging) editor.endDrag();
                        }
                      : null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(scene.imageBytes, fit: BoxFit.fill, gaplessPlayback: true),
                      if (!editor.showOriginal) ..._buildOverlays(editor, scene, size),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildOverlays(SsPhotoEditorController editor, SsPhotoScene scene, Size size) {
    final selectedId = editor.selection.isEmpty ? null : int.tryParse(editor.selection.objectId);
    return [
      for (final o in scene.visibleObjects)
        Positioned(
          left: o.x * size.width,
          top: o.y * size.height,
          width: o.width * size.width,
          height: o.height * size.height,
          child: Container(
            key: Key('ssPhotoObject_${o.id}'),
            decoration: BoxDecoration(
              border: Border.all(color: o.id == selectedId ? SsMasterTheme.neonBlue : Colors.white54, width: o.id == selectedId ? 2.5 : 1.2),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.topLeft,
            child: o.id == selectedId
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: SsMasterTheme.neonBlue,
                    child: Text(o.name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  )
                : null,
          ),
        ),
      for (final o in scene.removedObjects)
        Positioned(
          left: o.x * size.width,
          top: o.y * size.height,
          width: o.width * size.width,
          height: o.height * size.height,
          child: Container(
            key: Key('ssPhotoRemoved_${o.id}'),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              border: Border.all(color: SsMasterTheme.neonOrange, width: 1.2),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              o.aiRestoreBackground ? 'AI 배경 복원 중' : '삭제됨',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),
      for (final o in scene.openings)
        Positioned(
          left: o.x * size.width,
          top: o.y * size.height,
          width: o.width * size.width,
          height: o.height * size.height,
          child: Container(
            key: Key('ssPhotoOpening_${o.id}'),
            decoration: BoxDecoration(border: Border.all(color: SsMasterTheme.neonCyan, width: 1.5), borderRadius: BorderRadius.circular(4)),
            alignment: Alignment.bottomCenter,
            child: Text(o.kind.label, style: const TextStyle(color: SsMasterTheme.neonCyan, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
      if (!editor.selection.isEmpty) Positioned(right: 12, top: 12, child: _buildSelectionPanel(editor)),
    ];
  }

  Widget _buildSelectionPanel(SsPhotoEditorController editor) {
    final sel = editor.selection;
    return Container(
      key: const Key('ssPhotoSelectionPanel'),
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SsMasterTheme.panel.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SsMasterTheme.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(sel.summary(), key: const Key('ssPhotoSelectionSummary'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('ssPhotoDeleteSelected'),
                  onPressed: () => editor.deleteSelected(aiRestoreBackground: _aiRestoreBackground),
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                  label: const Text('삭제', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('ssPhotoRegenerateSelected'),
                  onPressed: editor.requestRegenerate,
                  icon: const Icon(Icons.refresh, size: 16, color: SsMasterTheme.neonBlue),
                  label: const Text('재생성', style: TextStyle(color: SsMasterTheme.neonBlue, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(SsPhotoEditorController editor) {
    return Container(
      key: const Key('ssPhotoRightPanel'),
      width: 300,
      color: SsMasterTheme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRightTabs(),
          const Divider(height: 1, color: SsMasterTheme.panelBorder),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: switch (_rightTab) {
                _RightTab.objects => _buildObjectsTab(editor),
                _RightTab.finish => _buildFinishTab(editor),
                _RightTab.opening => _buildOpeningTab(editor),
                _RightTab.furniture => _buildFurnitureTab(editor),
                _RightTab.lighting => _buildLightingTab(editor),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightTabs() {
    const tabs = [
      (_RightTab.objects, '객체'),
      (_RightTab.finish, '재질/색상'),
      (_RightTab.opening, '벽/구멍'),
      (_RightTab.furniture, '가구'),
      (_RightTab.lighting, '조명'),
    ];
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          for (final (tab, label) in tabs)
            Expanded(
              child: InkWell(
                key: Key('ssPhotoRightTab_${tab.name}'),
                onTap: () => setState(() => _rightTab = tab),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: _rightTab == tab ? SsMasterTheme.selectedItem : null),
                  child: Text(label, style: TextStyle(fontSize: 11, color: _rightTab == tab ? Colors.white : SsMasterTheme.textSecondary, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildObjectsTab(SsPhotoEditorController editor) {
    final scene = editor.scene;
    final selectedId = editor.selection.isEmpty ? null : int.tryParse(editor.selection.objectId);
    final selectedObj = selectedId == null ? null : scene.object(selectedId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('선택된 객체', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (selectedObj == null)
          const Text('사진에서 바꾸고 싶은 가구를 선택하세요.', key: Key('ssPhotoNoSelection'), style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))
        else
          Container(
            key: const Key('ssPhotoSelectedObjectCard'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: SsMasterTheme.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: SsMasterTheme.panelBorder)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selectedObj.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      Text(selectedObj.category.label, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                TextButton.icon(
                  key: const Key('ssPhotoDeleteFromPanel'),
                  onPressed: () => editor.deleteSelected(aiRestoreBackground: _aiRestoreBackground),
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                  label: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(child: Text('AI 배경 복원', style: TextStyle(color: Colors.white, fontSize: 13))),
            Switch(key: const Key('ssPhotoAiRestoreToggle'), value: _aiRestoreBackground, onChanged: (v) => setState(() => _aiRestoreBackground = v)),
          ],
        ),
        const Text('객체를 삭제한 뒤 기존 공간을 자연스럽게 복원합니다.', style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 11)),
        if (scene.removedObjects.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('삭제한 객체', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final o in scene.removedObjects)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(child: Text(o.name, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))),
                  TextButton(key: Key('ssPhotoRestoreObject_${o.id}'), onPressed: () => editor.restoreObjectById(o.id), child: const Text('복원')),
                ],
              ),
            ),
        ],
        const SizedBox(height: 18),
        const Text('유사 가구 추천', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in _kFurnitureCatalog)
              ActionChip(
                key: Key('ssPhotoSuggest_$name'),
                label: Text(name, style: const TextStyle(fontSize: 11)),
                onPressed: selectedObj == null ? null : () => editor.replaceSelectedFurniture(name),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinishTab(SsPhotoEditorController editor) {
    final current = editor.scene.finishes[_selectedSurface];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('공간 재질/색상', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final surface in SsPhotoSurface.values)
              ChoiceChip(
                key: Key('ssPhotoFinishSurface_${surface.name}'),
                label: Text(surface.label, style: const TextStyle(fontSize: 11)),
                selected: _selectedSurface == surface,
                onSelected: (_) => setState(() => _selectedSurface = surface),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final swatch in _kMaterialSwatches)
              GestureDetector(
                key: Key('ssPhotoSwatch_${swatch.$1}'),
                onTap: () => editor.setFinish(_selectedSurface, swatchId: swatch.$1, colorValue: swatch.$3),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(swatch.$3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: current?.swatchId == swatch.$1 ? SsMasterTheme.neonBlue : Colors.transparent, width: 2.5),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (current != null) Text('현재: ${current.swatchId}', key: const Key('ssPhotoCurrentFinish'), style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
      ],
    );
  }

  Widget _buildOpeningTab(SsPhotoEditorController editor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('벽체 개구부 추가', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('추가할 종류를 고르고 사진을 누르세요.', style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final kind in SsPhotoOpeningKind.values)
              ChoiceChip(
                key: Key('ssPhotoOpeningKind_${kind.name}'),
                label: Text(kind.label, style: const TextStyle(fontSize: 11)),
                selected: _pendingOpeningKind == kind,
                onSelected: (_) => setState(() => _pendingOpeningKind = kind),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('추가된 개구부', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (editor.scene.openings.isEmpty)
          const Text('아직 없습니다.', style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))
        else
          for (final o in editor.scene.openings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(child: Text(o.kind.label, style: const TextStyle(color: Colors.white, fontSize: 12))),
                  TextButton(
                    key: Key('ssPhotoRemoveOpening_${o.id}'),
                    onPressed: () => editor.removeOpening(o.id),
                    child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildFurnitureTab(SsPhotoEditorController editor) {
    final hasSelection = !editor.selection.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(hasSelection ? '가구 교체' : '가구 추가', style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          hasSelection ? '고르면 선택한 객체가 바로 바뀝니다.' : '고른 뒤 사진을 눌러 놓으세요.',
          style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in _kFurnitureCatalog)
              ChoiceChip(
                key: Key('ssPhotoFurniture_$name'),
                label: Text(name, style: const TextStyle(fontSize: 11)),
                selected: _pendingFurnitureName == name,
                onSelected: (_) {
                  if (hasSelection) {
                    editor.replaceSelectedFurniture(name);
                  } else {
                    setState(() => _pendingFurnitureName = name);
                  }
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildLightingTab(SsPhotoEditorController editor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('조명 변경', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final preset in _kLightingPresets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: Key('ssPhotoLighting_${preset.$1}'),
                onPressed: () => editor.setLighting(SsPhotoLighting(presetId: preset.$1, label: preset.$2, warmth: preset.$3, brightness: preset.$4)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: editor.scene.lighting?.presetId == preset.$1 ? SsMasterTheme.neonBlue : SsMasterTheme.panelBorder),
                  alignment: Alignment.centerLeft,
                ),
                child: Text(preset.$2, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomBar(SsPhotoEditorController editor) {
    final canProceed = _project != null && _autosave != null;
    return Container(
      key: const Key('ssPhotoBottomBar'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: SsMasterTheme.panel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SizedBox(
              height: 64,
              child: ListView(
                key: const Key('ssPhotoHistoryList'),
                scrollDirection: Axis.horizontal,
                children: [for (var i = 0; i < editor.history.steps.length; i++) Padding(padding: const EdgeInsets.only(right: 10), child: _buildHistoryChip(editor, i))],
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('ssPhotoMemo'),
              controller: _memo,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(isDense: true, hintText: '작업 내용을 입력하세요…', hintStyle: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 16),
          _buildSaveIndicator(),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            key: const Key('ssPhotoComplete'),
            onPressed: canProceed ? () => unawaited(_goNext()) : null,
            icon: const Icon(Icons.check),
            label: const Text('완료하기'),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryChip(SsPhotoEditorController editor, int index) {
    final step = editor.history.steps[index];
    final isCurrent = index == editor.history.index;
    return GestureDetector(
      key: Key('ssPhotoHistory_$index'),
      onTap: () => editor.history.jumpTo(index),
      child: Container(
        width: 72,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: isCurrent ? SsMasterTheme.neonBlue : SsMasterTheme.panelBorder, width: isCurrent ? 2 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(step.state.imageBytes, height: 32, width: 64, fit: BoxFit.cover, gaplessPlayback: true),
            ),
            const SizedBox(height: 2),
            Text(step.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveIndicator() {
    final autosave = _autosave;
    if (autosave == null) {
      return const Text('프로젝트 없음', key: Key('ssPhotoSaveState'), style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12));
    }
    return ListenableBuilder(
      listenable: autosave,
      builder: (context, _) => Text(autosave.state.label, key: const Key('ssPhotoSaveState'), style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 12)),
    );
  }
}

class _PhotoToolButton extends StatelessWidget {
  const _PhotoToolButton({required this.toolKey, required this.icon, required this.label, required this.selected, required this.onTap});
  final String toolKey;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('ssPhotoTool_$toolKey'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(gradient: selected ? SsMasterTheme.selectedItem : null, borderRadius: BorderRadius.circular(10)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: selected ? Colors.white : SsMasterTheme.textSecondary, size: 20),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 10, color: selected ? Colors.white : SsMasterTheme.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
