/// SS-BUG-011 — 상단 알림 아이콘이 여는 알림 패널.
///
/// 실제 프로젝트 저장소의 최근 활동(최근 수정한 프로젝트와 그 단계)만 보여준다. 가짜 알림은 만들지 않으며,
/// 프로젝트가 없으면 "새 알림이 없습니다"를 보여준다.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_project_summary.dart';
import 'package:ason_space/core/ss_recent_projects.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:ason_space/theme/ss_master_theme.dart';

/// 알림 패널을 연다.
Future<void> showSsNotificationsPanel(BuildContext context, {SsProjectStore? projectStore}) {
  return showDialog<void>(context: context, builder: (_) => SsNotificationsPanel(projectStore: projectStore));
}

class SsNotificationsPanel extends StatefulWidget {
  const SsNotificationsPanel({super.key, this.projectStore, this.maxItems = 5});

  final SsProjectStore? projectStore;
  final int maxItems;

  @override
  State<SsNotificationsPanel> createState() => _SsNotificationsPanelState();
}

enum _PanelLoad { loading, loaded, error }

class _SsNotificationsPanelState extends State<SsNotificationsPanel> {
  _PanelLoad _state = _PanelLoad.loading;
  List<SsProject> _recent = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final all = await SsRecentProjects.load(store);
      if (!mounted) return;
      setState(() {
        _recent = all.take(widget.maxItems).toList();
        _state = _PanelLoad.loaded;
      });
    } catch (e, st) {
      debugPrint('SsNotificationsPanel._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _PanelLoad.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('ssNotificationsPanel'),
      backgroundColor: SsMasterTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: SsMasterTheme.panelBorder)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('알림', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    key: const Key('ssNotificationsClose'),
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: SsMasterTheme.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(child: Padding(padding: const EdgeInsets.only(right: 12), child: _buildBody())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _PanelLoad.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('불러오는 중…', key: Key('ssNotificationsLoading'), style: TextStyle(color: SsMasterTheme.textSecondary)),
        );
      case _PanelLoad.error:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('알림을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.', key: Key('ssNotificationsError'), style: TextStyle(color: SsMasterTheme.textSecondary)),
        );
      case _PanelLoad.loaded:
        if (_recent.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('새 알림이 없습니다', key: Key('ssNotificationsEmpty'), style: TextStyle(color: SsMasterTheme.textSecondary)),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: _recent.length,
          separatorBuilder: (_, _) => const Divider(height: 1, color: SsMasterTheme.panelBorder),
          itemBuilder: (context, i) {
            final p = _recent[i];
            final stage = SsProjectSummary.resumeStage(p);
            final date = SsProjectSummary.formatDate(SsProjectSummary.lastUpdated(p));
            return Padding(
              key: Key('ssNotification_${p.info.id}'),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.history, color: SsMasterTheme.neonBlue, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.info.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('${stage.title} 단계 · 최근 수정 $date', style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
    }
  }
}
