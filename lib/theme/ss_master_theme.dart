import 'package:flutter/material.dart';

/// SS001-UI — 공통 프레임(lib/core/ss_router.dart의 SsStageScreen·SsNavRail·SsStageHeader·SsTopBar)이
/// 쓰는 MASTER UI 테마. 기준: 2026-09-28 확정 MASTER UI 2(홈화면)·3(프로젝트 관리)·5(평면도 업로드)·
/// 8(CAD 수정 및 내보내기) 이미지 — Dark Navy 배경·패널, Rainbow/Neon 강조(선택 메뉴 파랑→보라
/// 그라데이션, 무지개 SS 로고), 흰색/회색 글자.
///
/// 기존 흰색 V1 테마([lib/theme/space_shift_colors.dart]의 `SpaceShiftColors`)는 값을 바꾸거나 지우지
/// 않는다 — 아직 V1 화면(LoginScreen, PhotoSelectScreen, FloorPlanWorkspaceScreen 등)이 그대로 쓰고,
/// 그 화면들은 SS002~SS011에서 차례로 이 MASTER 테마로 바뀐다.
abstract final class SsMasterTheme {
  /// 전체 배경(Dark Navy).
  static const Color background = Color(0xFF0A1830);

  /// 패널(상단 Header·좌측 메뉴) 배경 — 배경보다 한 단 밝은 Navy.
  static const Color panel = Color(0xFF0E2140);

  /// 패널 구분선/테두리.
  static const Color panelBorder = Color(0xFF203A5C);

  /// 본문 글자(흰색).
  static const Color textPrimary = Colors.white;

  /// 보조 글자(회색/연한 블루그레이).
  static const Color textSecondary = Color(0xFFA9B4C8);

  /// 더 흐린 보조 글자(섹션 라벨 등).
  static const Color textMuted = Color(0xFF6B7C99);

  // Neon/Rainbow 강조색 — SS 로고·선택 강조에 쓴다(V1의 SpaceShiftColors와 같은 계열의 색감).
  static const Color neonBlue = Color(0xFF3B82F6);
  static const Color neonCyan = Color(0xFF22D3EE);
  static const Color neonPurple = Color(0xFFA855F7);
  static const Color neonPink = Color(0xFFEC4899);
  static const Color neonOrange = Color(0xFFFB923C);

  /// SS 로고 등 무지개 강조 텍스트/아이콘에 쓰는 그라데이션.
  static const LinearGradient rainbow = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [neonBlue, neonCyan, neonPurple, neonPink, neonOrange],
  );

  /// 좌측 메뉴에서 선택된(지금 단계에 해당하는) 항목을 강조하는 파랑→보라 그라데이션 상자.
  static const LinearGradient selectedItem = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF2F6BFF), Color(0xFF8B2FE0)],
  );

  /// SS 수정 01(MASTER 02) — 상단 Header "SPACE SHIFT" 글자: 분홍→보라→파랑.
  static const LinearGradient brandText = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFF5FA8), Color(0xFFB25CFF), Color(0xFF5B8CFF), Color(0xFF3FC5FF)],
  );

  /// SS 수정 01(MASTER 02) — 홈 배너의 큰 "SPACE SHIFT": 파랑→보라→분홍→주황.
  static const LinearGradient heroBrand = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF2FA8FF), Color(0xFF7B61FF), Color(0xFFE94BC0), Color(0xFFFF8A3D)],
  );

  /// SS 수정 01(MASTER 02) — 좌측 메뉴 선택 항목: 파랑→보라→분홍.
  static const LinearGradient selectedNavItem = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF2F6BFF), Color(0xFF8B2FE0), Color(0xFFE24FCF)],
  );

  /// 선택 메뉴 바깥 네온 빛.
  static const List<BoxShadow> selectedNavGlow = [
    BoxShadow(color: Color(0x998B5CF6), blurRadius: 18),
    BoxShadow(color: Color(0x663B82F6), blurRadius: 8, spreadRadius: 1),
  ];

  /// 홈 콘텐츠 판(둥근 테두리 + 가장자리 네온 빛).
  static const Color homePanel = Color(0xFF0B1B36);
  static const Color homePanelBorder = Color(0xFF2A4C80);
  static const List<BoxShadow> homePanelGlow = [
    BoxShadow(color: Color(0x403B82F6), blurRadius: 18),
    BoxShadow(color: Color(0x26A855F7), blurRadius: 30),
  ];
}
