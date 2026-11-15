/// SS-수정003 — MASTER UI 3 프로젝트 카드의 5단계 진행 점 줄(업로드 · 분석 · 생성 · 수정 · 완료).
/// 지난 단계는 채운 체크 점, 현재 단계는 강조한 빈 원, 남은 단계는 빈 원, 점 사이는 선.
library;

import 'package:flutter/material.dart';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_summary.dart';
import 'package:ason_space/theme/ss_master_theme.dart';

class SsProjectProgressSteps extends StatelessWidget {
  const SsProjectProgressSteps({super.key, required this.project, this.compact = false});

  final SsProject project;

  /// 목록 보기용 작은 점 줄.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final states = SsProjectSummary.phaseStates(project);
    final phases = SsProjectPhase.values;
    final id = project.info.id;
    final dot = compact ? 12.0 : 16.0;
    final labelSize = compact ? 9.0 : 10.0;
    return Tooltip(
      message: SsProjectSummary.stepDetail(project),
      child: Row(
        key: Key('ssProjectSteps_$id'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < phases.length; i++)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: dot,
                    child: Row(
                      children: [
                        Expanded(child: _line(visible: i > 0, active: states[i] != SsPhaseState.upcoming)),
                        _Dot(key: Key('ssProjectStep_${id}_${phases[i].name}_${states[i].name}'), state: states[i], size: dot),
                        Expanded(child: _line(visible: i < phases.length - 1, active: i < phases.length - 1 && states[i + 1] != SsPhaseState.upcoming)),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      phases[i].label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: labelSize,
                        fontWeight: states[i] == SsPhaseState.current ? FontWeight.w800 : FontWeight.w500,
                        color: states[i] == SsPhaseState.upcoming ? SsMasterTheme.textMuted : (states[i] == SsPhaseState.current ? SsMasterTheme.neonCyan : SsMasterTheme.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _line({required bool visible, required bool active}) {
    if (!visible) return const SizedBox.shrink();
    return Container(height: 2, color: active ? SsMasterTheme.neonPurple : SsMasterTheme.panelBorder);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.state, required this.size});
  final SsPhaseState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case SsPhaseState.completed:
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SsMasterTheme.selectedItem),
          child: Icon(Icons.check, size: size * 0.7, color: Colors.white),
        );
      case SsPhaseState.current:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SsMasterTheme.background,
            border: Border.all(color: SsMasterTheme.neonCyan, width: 2),
            boxShadow: [BoxShadow(color: SsMasterTheme.neonCyan.withValues(alpha: 0.5), blurRadius: 6)],
          ),
        );
      case SsPhaseState.upcoming:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SsMasterTheme.background,
            border: Border.all(color: SsMasterTheme.panelBorder, width: 1.5),
          ),
        );
    }
  }
}
