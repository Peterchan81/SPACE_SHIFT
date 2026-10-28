/// SS004 — MASTER UI 3(프로젝트 관리). 프로젝트 카드(대표 이미지·이름·상태·진행률·최근 수정일),
/// 검색·정렬·보기 전환, 새 프로젝트 생성, 마지막 작업 이어서 하기, 확인을 거친 삭제.
/// 프로젝트를 열면 저장된 currentStage(마지막 정상 단계)로 복원한다.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_project_summary.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/ss_source_type_visual.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:ason_space/theme/ss_master_theme.dart';

/// 저장소에서 프로젝트를 다시 읽어(손상 시 FileSsProjectStore가 마지막 정상본으로) 마지막 작업 단계로 연다.
/// 열지 못하면 SnackBar로 알리고 false.
Future<bool> resumeSsProject(BuildContext context, SsProjectStore store, String projectId) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context);
  SsProject? project;
  try {
    project = await store.load(projectId);
  } catch (e, st) {
    debugPrint('resumeSsProject 실패 (${e.runtimeType}): $e\n$st');
    messenger?.showSnackBar(
      const SnackBar(content: Text('프로젝트를 여는 중 오류가 발생했습니다. 다시 시도해주세요.', key: Key('ssProjectOpenError'))),
    );
    return false;
  }
  if (project == null) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('프로젝트를 복원하지 못했습니다. 저장 파일이 없거나 손상되었습니다.', key: Key('ssProjectOpenError'))),
    );
    return false;
  }
  try {
    await store.setLastOpened(projectId);
  } catch (e, st) {
    // 마지막 작업 기록 실패는 프로젝트 열기를 막지 않는다 — 원인은 개발자에게 남긴다.
    debugPrint('setLastOpened 실패 (${e.runtimeType}): $e\n$st');
  }
  await navigator.pushNamed(SsProjectSummary.resumeStage(project).routeName, arguments: projectId);
  return true;
}

class ProjectManagementScreen extends StatefulWidget {
  const ProjectManagementScreen({super.key, this.projectStore});

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  @override
  State<ProjectManagementScreen> createState() => _ProjectManagementScreenState();
}

enum _Load { loading, loaded, error }

class _ProjectManagementScreenState extends State<ProjectManagementScreen> {
  _Load _state = _Load.loading;
  SsProjectStore? _store;
  List<SsProject> _projects = const [];
  Map<String, String> _thumbs = const {};
  SsProject? _last;
  String _query = '';
  SsProjectSort _sort = SsProjectSort.recent;
  bool _grid = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_state != _Load.loading) setState(() => _state = _Load.loading);
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final ids = await store.list();
      final loaded = <SsProject>[];
      for (final id in ids) {
        final p = await store.load(id);
        if (p != null) loaded.add(p);
      }
      final lastId = await store.lastOpened();
      final thumbs = <String, String>{};
      for (final p in loaded) {
        final c = SsProjectSummary.thumbnailCandidate(p);
        if (c == null) continue;
        try {
          if (await File(c).exists()) thumbs[p.info.id] = c;
        } catch (e) {
          debugPrint('대표 이미지 확인 실패 (${e.runtimeType}): $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _store = store;
        _projects = loaded;
        _thumbs = thumbs;
        _last = loaded.where((p) => p.info.id == lastId).firstOrNull;
        _state = _Load.loaded;
      });
    } catch (e, st) {
      debugPrint('ProjectManagementScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _Load.error);
    }
  }

  Future<void> _open(SsProject p) async {
    final store = _store;
    if (store == null) return;
    await resumeSsProject(context, store, p.info.id);
    if (mounted) unawaited(_load());
  }

  Future<void> _create() async {
    await Navigator.of(context).pushNamed(SsStage.projectCreation.routeName);
    if (mounted) unawaited(_load());
  }

  Future<void> _confirmDelete(SsProject p) async {
    final store = _store;
    if (store is! SsDeletableProjectStore) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('ssProjectDeleteDialog'),
        backgroundColor: SsMasterTheme.panel,
        title: const Text('프로젝트 삭제', style: TextStyle(color: Colors.white)),
        content: Text(
          "'${p.info.name}' 프로젝트를 삭제할까요?\n저장된 작업(원본·CAD·3D·렌더링)이 모두 지워지며 되돌릴 수 없습니다.",
          style: const TextStyle(color: SsMasterTheme.textSecondary),
        ),
        actions: [
          TextButton(key: const Key('ssProjectDeleteCancel'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          FilledButton(
            key: const Key('ssProjectDeleteConfirm'),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await store.delete(p.info.id);
      messenger?.showSnackBar(SnackBar(content: Text("'${p.info.name}' 프로젝트를 삭제했습니다.")));
    } catch (e, st) {
      debugPrint('프로젝트 삭제 실패 (${e.runtimeType}): $e\n$st');
      messenger?.showSnackBar(const SnackBar(content: Text('프로젝트를 삭제하지 못했습니다. 다시 시도해주세요.', key: Key('ssProjectDeleteError'))));
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('ssProjectsScroll'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SsStageHeader(stage: SsStage.projectManagement),
          const SizedBox(height: 16),
          _buildToolbar(),
          const SizedBox(height: 16),
          if (_state == _Load.loaded && _last != null) ...[_buildResumeBanner(_last!), const SizedBox(height: 16)],
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            key: const Key('ssProjectsSearch'),
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: SsMasterTheme.panel,
              hintText: '프로젝트 검색',
              hintStyle: const TextStyle(color: SsMasterTheme.textMuted),
              prefixIcon: const Icon(Icons.search, color: SsMasterTheme.textSecondary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: SsMasterTheme.panelBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: SsMasterTheme.panelBorder)),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('ssProjectsViewGrid'),
                tooltip: '카드 보기',
                onPressed: () => setState(() => _grid = true),
                icon: Icon(Icons.grid_view_rounded, color: _grid ? SsMasterTheme.neonBlue : SsMasterTheme.textSecondary),
              ),
              IconButton(
                key: const Key('ssProjectsViewList'),
                tooltip: '목록 보기',
                onPressed: () => setState(() => _grid = false),
                icon: Icon(Icons.view_list_rounded, color: !_grid ? SsMasterTheme.neonBlue : SsMasterTheme.textSecondary),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<SsProjectSort>(
              key: const Key('ssProjectsSort'),
              value: _sort,
              dropdownColor: SsMasterTheme.panel,
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: SsMasterTheme.textSecondary,
              items: [for (final s in SsProjectSort.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (s) {
                if (s != null) setState(() => _sort = s);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResumeBanner(SsProject p) {
    final stage = SsProjectSummary.resumeStage(p);
    return Container(
      key: const Key('ssProjectsResume'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(colors: [Color(0xFF13305E), Color(0xFF2A1E4D)]),
        border: Border.all(color: SsMasterTheme.neonBlue.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: SsMasterTheme.neonCyan),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '마지막 작업: ${p.info.name} · ${stage.title} 단계에서 이어서 할 수 있습니다.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            key: const Key('ssProjectsResumeButton'),
            style: FilledButton.styleFrom(backgroundColor: SsMasterTheme.neonBlue),
            onPressed: () => unawaited(_open(p)),
            child: const Text('이어서 작업하기'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _Load.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(key: Key('ssProjectsLoading'), color: SsMasterTheme.neonBlue, value: 0.3)),
        );
      case _Load.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Column(
              children: [
                const Text(
                  '프로젝트 목록을 불러오지 못했습니다. 다시 시도해주세요.',
                  key: Key('ssProjectsError'),
                  style: TextStyle(color: SsMasterTheme.textSecondary),
                ),
                const SizedBox(height: 10),
                OutlinedButton(key: const Key('ssProjectsRetry'), onPressed: () => unawaited(_load()), child: const Text('다시 시도')),
              ],
            ),
          ),
        );
      case _Load.loaded:
        final visible = SsProjectSummary.filterAndSort(_projects, query: _query, sort: _sort);
        final deletable = _store is SsDeletableProjectStore;
        final message = _projects.isEmpty
            ? const Text(
                "아직 프로젝트가 없습니다. '새 프로젝트 생성'을 눌러 첫 프로젝트를 시작하세요.",
                key: Key('ssProjectsEmpty'),
                style: TextStyle(color: SsMasterTheme.textSecondary),
              )
            : visible.isEmpty
            ? const Text('검색 결과가 없습니다.', key: Key('ssProjectsNoResult'), style: TextStyle(color: SsMasterTheme.textSecondary))
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) ...[message, const SizedBox(height: 16)],
            LayoutBuilder(
              builder: (context, constraints) {
                if (_grid) {
                  const gap = 16.0;
                  final cols = (constraints.maxWidth / 300).floor().clamp(1, 6);
                  final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      SizedBox(width: w, child: _NewProjectCard(onTap: () => unawaited(_create()))),
                      for (var i = 0; i < visible.length; i++)
                        SizedBox(
                          width: w,
                          child: _ProjectCard(
                            project: visible[i],
                            index: i + 1,
                            thumbnailPath: _thumbs[visible[i].info.id],
                            highlighted: visible[i].info.id == _last?.info.id,
                            onOpen: () => unawaited(_open(visible[i])),
                            onDelete: deletable ? () => unawaited(_confirmDelete(visible[i])) : null,
                          ),
                        ),
                    ],
                  );
                }
                return Column(
                  children: [
                    SizedBox(height: 120, child: _NewProjectCard(onTap: () => unawaited(_create()))),
                    for (var i = 0; i < visible.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _ProjectListTile(
                          project: visible[i],
                          index: i + 1,
                          thumbnailPath: _thumbs[visible[i].info.id],
                          highlighted: visible[i].info.id == _last?.info.id,
                          onOpen: () => unawaited(_open(visible[i])),
                          onDelete: deletable ? () => unawaited(_confirmDelete(visible[i])) : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
    }
  }
}

class _NewProjectCard extends StatelessWidget {
  const _NewProjectCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('ssProjectsCreateCard'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 310,
          decoration: BoxDecoration(
            color: SsMasterTheme.panel.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SsMasterTheme.neonBlue.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SsMasterTheme.selectedItem),
                child: const Icon(Icons.add, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 14),
              const Text('새 프로젝트 생성', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('새로운 공간을 디자인해보세요.', style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.project});
  final SsProject project;

  @override
  Widget build(BuildContext context) {
    final status = SsProjectSummary.status(project);
    final color = switch (status) {
      SsProjectStatus.draft => SsMasterTheme.textSecondary,
      SsProjectStatus.inProgress => SsMasterTheme.neonCyan,
      SsProjectStatus.needsUpdate => SsMasterTheme.neonOrange,
      SsProjectStatus.done => SsSourceTypeVisual.imageGreen,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: SsMasterTheme.background.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20), border: Border.all(color: color)),
      child: Text(
        status.label,
        key: Key('ssProjectStatus_${project.info.id}'),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.project, this.path});
  final SsProject project;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SsSourceTypeVisual.color(project.sourceType).withValues(alpha: 0.45), SsMasterTheme.background],
        ),
      ),
      child: Center(child: Icon(SsSourceTypeVisual.previewIcon(project.sourceType), size: 48, color: Colors.white70)),
    );
    final p = path;
    if (p == null) return placeholder;
    return Image.file(File(p), fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
  }
}

class _ProjectMenu extends StatelessWidget {
  const _ProjectMenu({required this.project, required this.onOpen, this.onDelete});
  final SsProject project;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final id = project.info.id;
    return PopupMenuButton<String>(
      key: Key('ssProjectMenu_$id'),
      tooltip: '프로젝트 메뉴',
      color: SsMasterTheme.panel,
      iconSize: 20,
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, color: SsMasterTheme.textSecondary),
      onSelected: (v) {
        if (v == 'open') onOpen();
        if (v == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(value: 'open', key: Key('ssProjectMenuOpen_$id'), child: const Text('열기', style: TextStyle(color: Colors.white))),
        if (onDelete != null)
          PopupMenuItem<String>(value: 'delete', key: Key('ssProjectMenuDelete_$id'), child: const Text('삭제', style: TextStyle(color: Colors.redAccent))),
      ],
    );
  }
}

class _ProgressInfo extends StatelessWidget {
  const _ProgressInfo({required this.project});
  final SsProject project;

  @override
  Widget build(BuildContext context) {
    final pct = SsProjectSummary.percent(project);
    final stage = SsProjectSummary.resumeStage(project);
    final next = SsFlows.next(project.sourceType, stage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 14, color: SsMasterTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              SsProjectSummary.formatDate(SsProjectSummary.lastUpdated(project)),
              key: Key('ssProjectUpdated_${project.info.id}'),
              style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12),
            ),
            const Spacer(),
            Text(
              '$pct%',
              key: Key('ssProjectProgress_${project.info.id}'),
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 6,
            backgroundColor: SsMasterTheme.panelBorder,
            color: SsMasterTheme.neonPurple,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${SsProjectSummary.stepIndex(project) + 1}/${SsProjectSummary.stepCount(project)} 단계 · ${next == null ? '완료' : '다음: ${next.title}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.index, required this.highlighted, required this.onOpen, this.thumbnailPath, this.onDelete});
  final SsProject project;
  final int index;
  final String? thumbnailPath;
  final bool highlighted;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final stage = SsProjectSummary.resumeStage(project);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('ssProjectCard_${project.info.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Container(
          height: 310,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: SsMasterTheme.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: highlighted ? SsMasterTheme.neonBlue : SsMasterTheme.panelBorder, width: highlighted ? 2 : 1),
            boxShadow: highlighted ? [BoxShadow(color: SsMasterTheme.neonBlue.withValues(alpha: 0.35), blurRadius: 16)] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 130,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Thumb(project: project, path: thumbnailPath),
                    Positioned(top: 10, right: 10, child: _StatusChip(project: project)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(index.toString().padLeft(2, '0'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              project.info.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                          _ProjectMenu(project: project, onOpen: onOpen, onDelete: onDelete),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${project.sourceType.label} | ${stage.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                      Padding(padding: const EdgeInsets.only(right: 8), child: _ProgressInfo(project: project)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectListTile extends StatelessWidget {
  const _ProjectListTile({required this.project, required this.index, required this.highlighted, required this.onOpen, this.thumbnailPath, this.onDelete});
  final SsProject project;
  final int index;
  final String? thumbnailPath;
  final bool highlighted;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final stage = SsProjectSummary.resumeStage(project);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('ssProjectCard_${project.info.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          height: 100,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SsMasterTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: highlighted ? SsMasterTheme.neonBlue : SsMasterTheme.panelBorder, width: highlighted ? 2 : 1),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 120, height: 76, child: _Thumb(project: project, path: thumbnailPath)),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index.toString().padLeft(2, '0')}  ${project.info.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${project.sourceType.label} | ${stage.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _StatusChip(project: project),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: Center(child: _ProgressInfo(project: project))),
              _ProjectMenu(project: project, onOpen: onOpen, onDelete: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}
