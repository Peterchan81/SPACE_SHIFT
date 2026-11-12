/// SS-BUG-011 — 홈 "가이드 보기"·상단 도움말 아이콘이 여는 안내 화면.
/// 3가지 시작 방식(평면도 업로드·직접 그리기·이미지 변환)과 각 방식의 실제 단계 흐름([SsFlows])을
/// 보여주고, 각 방식에서 바로 프로젝트 생성(그 시작 방식 선택된 상태)으로 갈 수 있다.
/// 내용은 앱 안 고정 문구다(외부 AI·네트워크 호출 없음).
library;

import 'package:flutter/material.dart';

import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/theme/ss_master_theme.dart';
import 'package:ason_space/widgets/ss_info_page.dart';

class SsGuideScreen extends StatelessWidget {
  const SsGuideScreen({super.key});

  static const Map<SsSourceType, IconData> _icons = {
    SsSourceType.floorPlanUpload: Icons.cloud_upload_outlined,
    SsSourceType.directDraw: Icons.edit_outlined,
    SsSourceType.imageTransform: Icons.image_outlined,
  };

  static const Map<SsSourceType, String> _descriptions = {
    SsSourceType.floorPlanUpload: '가지고 있는 평면도 이미지나 PDF를 올리면 AI가 벽·문·창을 인식합니다. 인식 결과를 확인·보정한 뒤 CAD와 3D 디자인으로 이어집니다.',
    SsSourceType.directDraw: '평면도가 없다면 간단한 도구로 벽과 문·창을 직접 그려 공간을 만듭니다. 그린 도면은 CAD와 3D 디자인으로 이어집니다.',
    SsSourceType.imageTransform: '실제 공간 사진을 올리고 바꿀 부분과 원하는 스타일을 정하면 AI가 새 디자인 이미지를 만듭니다.',
  };

  static const Map<SsSourceType, Color> _accents = {
    SsSourceType.floorPlanUpload: SsMasterTheme.neonBlue,
    SsSourceType.directDraw: SsMasterTheme.neonPurple,
    SsSourceType.imageTransform: SsMasterTheme.neonPink,
  };

  @override
  Widget build(BuildContext context) {
    return SsInfoPage(
      title: '시작 가이드',
      subtitle: 'SPACE SHIFT는 3가지 방식으로 시작할 수 있습니다. 방식을 고르면 아래 순서대로 작업이 진행됩니다.',
      children: [
        for (final type in SsSourceType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _GuideFlowCard(type: type, icon: _icons[type]!, description: _descriptions[type]!, accent: _accents[type]!),
          ),
      ],
    );
  }
}

class _GuideFlowCard extends StatelessWidget {
  const _GuideFlowCard({required this.type, required this.icon, required this.description, required this.accent});

  final SsSourceType type;
  final IconData icon;
  final String description;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final steps = SsFlows.stages[type]!;
    return Container(
      key: Key('ssGuideFlow_${type.name}'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SsMasterTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(type.label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(description, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < steps.length; i++)
                Container(
                  key: Key('ssGuideStep_${type.name}_$i'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: SsMasterTheme.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SsMasterTheme.panelBorder),
                  ),
                  child: Text('${i + 1}. ${steps[i].title}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: Key('ssGuideStart_${type.name}'),
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pushNamed(SsStage.projectCreation.routeName, arguments: type),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('이 방식으로 시작하기'),
          ),
        ],
      ),
    );
  }
}
