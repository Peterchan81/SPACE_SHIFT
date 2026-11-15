/// SS-BUG-011 — 좌측 메뉴 "진행 중인 프로젝트"(MASTER UI 3·5) 목록.
///
/// 실제 프로젝트 저장소([SsProjectStoreProvider] 또는 주입한 [projectStore])의 완료되지 않은 프로젝트를
/// 최근 수정순으로 번호·이름·진행률 막대·%로 보여준다. 누르면 기존 SS003·SS004 재개 흐름
/// ([resumeSsProject])으로 그 프로젝트의 마지막 저장 단계를 연다. 프로젝트가 없으면 짧은 빈 안내.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_project_summary.dart';
import 'package:ason_space/core/ss_recent_projects.dart';
import 'package:ason_space/screens/project_management_screen.dart' show resumeSsProject;
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:ason_space/theme/ss_master_theme.dart';

class SsNavCurrentProjects extends StatefulWidget {
  const SsNavCurrentProjects({super.key, this.projectStore, this.maxItems = 5});

  /// 테스트 주입용. 없으면 앱 공용 저장소.
  final SsProjectStore? projectStore;
  final int maxItems;

  @override
  State<SsNavCurrentProjects> createState() => _SsNavCurrentProjectsState();
}

enum _NavLoad { loading, loaded, error }

class _SsNavCurrentProjectsState extends State<SsNavCurrentProjects> {
  _NavLoad _state = _NavLoad.loading;
  List<SsProject> _projects = const [];
  SsProjectStore? _store;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final all = await SsRecentProjects.load(store);
      final inProgress = [
        for (final p in all)
          if (SsProjectSummary.status(p) != SsProjectStatus.done) p,
      ];
      if (!mounted) return;
      setState(() {
        _store = store;
        _projects = inProgress.take(widget.maxItems).toList();
        _state = _NavLoad.loaded;
      });
    } catch (e, st) {
      // 저장소 오류인지 다른 예외인지 단정하지 않는다 — 화면엔 일반 실패만, 실제 원인은 개발자에게.
      debugPrint('SsNavCurrentProjects._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _NavLoad.error);
    }
  }

  Future<void> _open(SsProject project) async {
    final store = _store;
    if (store == null || _opening) return;
    _opening = true;
    try {
      await resumeSsProject(context, store, project.info.id);
    } finally {
      _opening = false;
    }
    // 재개한 화면에서 돌아오면 진행률이 바뀌었을 수 있으므로 다시 읽는다.
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _NavLoad.loading:
        return const _NavNote(key: Key('ssNavCurrentProjectsLoading'), text: '불러오는 중…');
      case _NavLoad.error:
        return const _NavNote(key: Key('ssNavCurrentProjectsError'), text: '프로젝트를 불러오지 못했습니다.');
      case _NavLoad.loaded:
        if (_projects.isEmpty) {
          return const _NavNote(key: Key('ssNavCurrentProjectsEmpty'), text: '진행 중인 프로젝트가 없습니다.');
        }
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _projects.length,
          itemBuilder: (context, i) => _NavProjectRow(index: i, project: _projects[i], onTap: () => unawaited(_open(_projects[i]))),
        );
    }
  }
}

class _NavNote extends StatelessWidget {
  const _NavNote({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: const TextStyle(fontSize: 12, color: SsMasterTheme.textMuted)),
    );
  }
}

class _NavProjectRow extends StatelessWidget {
  const _NavProjectRow({required this.index, required this.project, required this.onTap});
  final int index;
  final SsProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = SsProjectSummary.percent(project);
    final stage = SsProjectSummary.resumeStage(project);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key('ssNavCurrentProject_${project.info.id}'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    (index + 1).toString().padLeft(2, '0'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SsMasterTheme.neonCyan),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$pct%',
                    key: Key('ssNavCurrentProjectPercent_${project.info.id}'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SsMasterTheme.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  key: Key('ssNavCurrentProjectProgress_${project.info.id}'),
                  value: pct / 100,
                  minHeight: 4,
                  backgroundColor: SsMasterTheme.panelBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(SsMasterTheme.neonBlue),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stage.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: SsMasterTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
