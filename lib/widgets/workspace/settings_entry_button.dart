import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

/// 좌측 패널 하단에 고정으로 두는 "⚙ 설정" 진입 버튼.
///
/// 시작 방식(① 평면도 업로드/② 직접 그리기/③ 사진으로 변환) 카드와
/// 헷갈리지 않도록, rainbow accent나 선택 상태 강조 없이 중립적인
/// 흰색/얇은 테두리로만 그린다 — MASTER 공통 기능이라 어떤 시작 방식을
/// 쓰고 있어도 항상 같은 자리에 같은 모습으로 남아있는다.
class SettingsEntryButton extends StatelessWidget {
  const SettingsEntryButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SpaceShiftColors.border),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.settings_outlined,
                size: 20,
                color: SpaceShiftColors.textSecondary,
              ),
              SizedBox(width: 10),
              Text(
                '설정',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SpaceShiftColors.textPrimary,
                ),
              ),
              Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: SpaceShiftColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
