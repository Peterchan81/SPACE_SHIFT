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
}
