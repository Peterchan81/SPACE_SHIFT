import 'package:flutter/material.dart';

/// SPACE SHIFT 브랜드 컬러 아이덴티티.
///
/// SS_V1_UI_MASTER.png 기준, 전체 배경은 밝은 화이트를 유지하고 이 컬러들은
/// 로고/라인/버튼 등 강조 요소에만 사용한다.
abstract final class SpaceShiftColors {
  static const Color blue = Color(0xFF3B82F6);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color purple = Color(0xFFA855F7);
  static const Color pink = Color(0xFFEC4899);
  static const Color orange = Color(0xFFFB923C);

  /// 버튼/라인 등에 사용하는 대표 spectrum 그라데이션.
  static const LinearGradient spectrum = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [blue, cyan, purple, pink, orange],
  );

  /// 선택 영역 오버레이 등 단일 강조색이 필요할 때 사용하는 보라 계열.
  static const Color selectionAccent = purple;

  static const Color textPrimary = Color(0xFF1F2933);
  static const Color textSecondary = Color(0xFF52606D);
  static const Color border = Color(0xFFE4E7EB);
  static const Color surface = Colors.white;
  static const Color background = Colors.white;

  /// PC2 2D CAD 재조사 WO — 공간(방) 번호/채움 색에 쓰는 순환 강조색.
  /// [WorkspaceTaskItem]의 번호 marker(`workspaceMarkerColors`)와 같은
  /// rainbow accent 팔레트를 공유해, "번호 하나 = accent 색 하나"라는
  /// 언어가 작업 목록과 도면 공간 번호 사이에서 일관되게 보이도록 한다.
  /// 도면 위에서는 항상 낮은 alpha로만 채워 벽선 가독성을 해치지 않는다.
  static const List<Color> roomAccentColors = [
    Color(0xFFEC4899), // pink/red
    Color(0xFFFB923C), // orange
    Color(0xFFEAB308), // yellow
    Color(0xFF22C55E), // green
    Color(0xFF22D3EE), // cyan
    Color(0xFF6366F1), // blue/purple
  ];

  /// [index]는 0부터 시작(공간 목록 순번-1과 동일) — 팔레트보다 방이
  /// 많으면 순환한다.
  static Color roomAccentColorFor(int index) =>
      roomAccentColors[index % roomAccentColors.length];
}
