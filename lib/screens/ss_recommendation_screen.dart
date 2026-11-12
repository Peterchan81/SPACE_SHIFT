/// SS-BUG-011 — 홈 "추천 보기"가 여는 인테리어 스타일 추천 목록(앱 안 고정 내용 — 외부 AI·네트워크 호출 없음).
/// 스타일을 고르면 이미지 변환 시작 흐름(시작 방식이 이미지 변환으로 정해진 프로젝트 생성)으로 이동한다.
library;

import 'package:flutter/material.dart';

import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/theme/ss_master_theme.dart';
import 'package:ason_space/widgets/ss_info_page.dart';

class SsRecommendationScreen extends StatelessWidget {
  const SsRecommendationScreen({super.key});

  static const styles = [
    (id: 'modern', name: '모던', desc: '군더더기 없는 직선과 무채색, 금속·유리 소재로 깔끔하게.', colors: [Color(0xFF1F2937), Color(0xFF9CA3AF), Color(0xFFF3F4F6)]),
    (id: 'nordic', name: '북유럽', desc: '밝은 원목과 흰 벽, 부드러운 패브릭으로 따뜻하고 편안하게.', colors: [Color(0xFFF5F0E6), Color(0xFFD6B98C), Color(0xFF9CA3AF)]),
    (id: 'minimal', name: '미니멀', desc: '가구와 장식을 줄이고 여백을 살려 넓어 보이게.', colors: [Color(0xFFFFFFFF), Color(0xFFE5E7EB), Color(0xFF6B7280)]),
    (id: 'natural', name: '내추럴', desc: '나무·라탄·식물 등 자연 소재와 베이지 톤으로 차분하게.', colors: [Color(0xFFE7DCC8), Color(0xFFA67C52), Color(0xFF6B8F5E)]),
    (id: 'classic', name: '클래식', desc: '몰딩과 짙은 원목, 우아한 조명으로 품격 있게.', colors: [Color(0xFF3F2A1E), Color(0xFFC9A66B), Color(0xFFF1E7D0)]),
    (id: 'industrial', name: '인더스트리얼', desc: '노출 콘크리트·벽돌과 검은 철제 마감으로 개성 있게.', colors: [Color(0xFF4B5563), Color(0xFF7C2D12), Color(0xFF111827)]),
  ];

  @override
  Widget build(BuildContext context) {
    return SsInfoPage(
      title: '오늘의 추천',
      subtitle: '추천 인테리어 스타일입니다. 마음에 드는 스타일을 고르면 공간 사진으로 이미지 변환을 시작합니다.',
      children: [
        for (final s in styles)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: Key('ssRecommendStyle_${s.id}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).pushNamed(SsStage.projectCreation.routeName, arguments: SsSourceType.imageTransform),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SsMasterTheme.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: SsMasterTheme.panelBorder),
                  ),
                  child: Row(
                    children: [
                      for (final c in s.colors)
                        Container(
                          width: 18,
                          height: 36,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(s.desc, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12, height: 1.4)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, color: SsMasterTheme.neonPurple, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
