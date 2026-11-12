/// SS-BUG-011 — 홈 "팁 보기"가 여는 공간 디자인 팁 목록(앱 안 고정 내용 — 외부 AI·네트워크 호출 없음).
library;

import 'package:flutter/material.dart';

import 'package:ason_space/theme/ss_master_theme.dart';
import 'package:ason_space/widgets/ss_info_page.dart';

class SsTipsScreen extends StatelessWidget {
  const SsTipsScreen({super.key});

  static const tips = [
    (icon: Icons.crop_free, title: '평면도는 반듯하고 선명하게', body: '평면도를 정면에서 반듯하게 찍거나 스캔하면 벽과 문·창 인식이 더 정확해집니다. 그림자와 기울기를 피하세요.'),
    (icon: Icons.straighten, title: '치수가 보이는 도면을 쓰세요', body: '치수가 적힌 도면은 실제 크기를 맞추기 쉬워 CAD와 3D 결과의 비율이 정확해집니다.'),
    (icon: Icons.fact_check_outlined, title: '인식 결과는 꼭 확인·보정하세요', body: 'AI가 인식한 벽·문·창을 확인하고 틀린 곳을 고친 뒤 CAD 변환을 하면 이후 단계가 모두 깔끔해집니다.'),
    (icon: Icons.wb_sunny_outlined, title: '사진은 밝고 넓게 찍으세요', body: '이미지 변환에는 밝은 낮에, 공간 전체가 보이도록 넓게 찍은 사진이 좋습니다.'),
    (icon: Icons.edit_note, title: '원하는 스타일을 구체적으로', body: '"따뜻한 원목 바닥과 흰 벽"처럼 색·소재·분위기를 구체적으로 적으면 원하는 결과에 더 가까워집니다.'),
    (icon: Icons.save_outlined, title: '작업은 자동으로 저장됩니다', body: '작업 중 앱을 닫아도 마지막 저장 단계부터 이어서 할 수 있습니다. 좌측 메뉴의 진행 중인 프로젝트에서 바로 재개하세요.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SsInfoPage(
      title: '공간 디자인 팁',
      subtitle: '더 좋은 결과를 위한 팁을 확인하세요.',
      children: [
        for (var i = 0; i < tips.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              key: Key('ssTip_$i'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SsMasterTheme.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SsMasterTheme.panelBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(tips[i].icon, color: SsMasterTheme.neonCyan),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tips[i].title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(tips[i].body, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
