import 'package:flutter/material.dart';

import '../../models/floor_plan_geometry.dart';
import '../../theme/space_shift_colors.dart';

/// 우측 "작업 환경 → 정보" Tab.
///
/// 현재 작업 중인 공간의 요약 정보와 간단한 사용 안내를 보여준다.
/// 실제 프로젝트 메타데이터(면적 실측, 저장 시각 등)는 백엔드 연동 이후
/// 채워질 값이므로, 이번에는 화면에 들어온 값만 표시하고 나머지는
/// "추후 연동" 형태로 정직하게 비워 둔다.
class InfoTab extends StatelessWidget {
  const InfoTab({
    super.key,
    required this.projectName,
    required this.taskCount,
    required this.visibleTaskCount,
    this.analysisDebugStats,
  });

  final String projectName;
  final int taskCount;
  final int visibleTaskCount;

  /// 평면도 분석 개발 검증용 최소 통계 — 있을 때만 "분석 정보(개발자용)"
  /// 카드로 노출한다. 일반 사용자 화면에는 과도한 숫자를 보여주지 않는다
  /// (WO 26번).
  final FloorPlanAnalysisDebugStats? analysisDebugStats;

  @override
  Widget build(BuildContext context) {
    final debugStats = analysisDebugStats;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          title: '공간 정보',
          children: [
            _InfoRow(label: '프로젝트명', value: projectName),
            const _InfoRow(label: '평면도 실측 면적', value: '추후 연동'),
            const _InfoRow(label: '마지막 저장', value: '추후 연동'),
          ],
        ),
        const SizedBox(height: 16),
        _Card(
          title: '작업 현황',
          children: [
            _InfoRow(label: '전체 작업 항목', value: '$taskCount개'),
            _InfoRow(label: '표시 중인 항목', value: '$visibleTaskCount개'),
          ],
        ),
        if (debugStats != null) ...[
          const SizedBox(height: 16),
          _Card(
            title: '분석 정보 (개발자용)',
            children: [
              _InfoRow(
                label: '원본 이미지',
                value:
                    '${debugStats.sourceWidthPx}×${debugStats.sourceHeightPx}px',
              ),
              _InfoRow(
                label: '분석 해상도',
                value:
                    '${debugStats.analysisWidthPx}×${debugStats.analysisHeightPx}px',
              ),
              _InfoRow(
                label: '검출된 raw 직선',
                value:
                    '수평 ${debugStats.rawHorizontalRuns} · 수직 ${debugStats.rawVerticalRuns}',
              ),
              _InfoRow(label: '병합된 벽', value: '${debugStats.mergedWallCount}개'),
              _InfoRow(
                label: '공간 후보',
                value: '${debugStats.roomCandidateCount}개',
              ),
              _InfoRow(
                label: '문/창 후보',
                value: '${debugStats.openingCandidateCount}개',
              ),
              _InfoRow(label: '분석 소요 시간', value: '${debugStats.durationMs}ms'),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _Card(
          title: '사용 안내',
          children: const [
            _HelpRow(
              icon: Icons.touch_app_outlined,
              text: '캔버스의 번호 마커를 눌러 작업 항목을 선택하세요.',
            ),
            _HelpRow(
              icon: Icons.list_alt_rounded,
              text: '작업 목록과 마커, 우측 패널은 서로 실시간으로 연동됩니다.',
            ),
            _HelpRow(
              icon: Icons.smart_toy_outlined,
              text: 'AI 어시스턴트는 하단 버튼으로 필요할 때만 불러올 수 있습니다.',
            ),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: SpaceShiftColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: SpaceShiftColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: SpaceShiftColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
