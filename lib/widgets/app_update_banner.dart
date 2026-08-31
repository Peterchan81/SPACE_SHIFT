import 'package:flutter/material.dart';

import '../models/app_update_view.dart';
import '../services/app_update_store.dart';
import '../theme/space_shift_colors.dart';

/// 인터넷 기반 무선 업데이트 안내를 PhotoSelectScreen(2번 화면, 로그인 후
/// 사용자가 가장 먼저/자주 보는 화면) 위쪽에 보여준다.
///
/// 새 확인 로직/네트워크 경로를 따로 만들지 않는다 — main.dart가 Android에서
/// 앱 시작 시 한 번 실행해 둔 [AppUpdateStore.instance]의 상태를 그대로
/// 구독만 한다. `updateAvailable`/`downloading`/`readyToInstall`일 때만
/// 보이고, 그 외(idle/checking/upToDate/error)에는 완전히 숨는다 — 배경
/// 확인 실패가 사용자에게 방해가 되지 않게 한다.
class AppUpdateBanner extends StatelessWidget {
  final AppUpdateViewState view;
  final VoidCallback onInstall;

  const AppUpdateBanner({
    super.key,
    required this.view,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    if (!view.isVisible) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SpaceShiftColors.selectionAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: SpaceShiftColors.selectionAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.system_update_rounded,
            size: 20,
            color: SpaceShiftColors.selectionAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              view.message,
              style: const TextStyle(
                fontSize: 13,
                color: SpaceShiftColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (view.state == AppUpdateState.updateAvailable)
            FilledButton(
              onPressed: onInstall,
              style: FilledButton.styleFrom(
                backgroundColor: SpaceShiftColors.selectionAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('업데이트', style: TextStyle(fontSize: 12.5)),
            )
          else
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SpaceShiftColors.selectionAccent,
              ),
            ),
        ],
      ),
    );
  }
}
