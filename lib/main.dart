import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'theme/space_shift_colors.dart';

void main() {
  runApp(const AsonSpaceApp());
}

/// SPACE SHIFT 앱의 루트 위젯.
///
/// Material 3 테마를 사용하며, SS_V1_UI_MASTER.png 기준 화이트 + spectrum
/// 컬러 아이덴티티를 전역 테마로 적용한다. 첫 화면은 [LoginScreen](로그인/
/// 자동로그인)이다.
class AsonSpaceApp extends StatelessWidget {
  const AsonSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPACE SHIFT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: SpaceShiftColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: SpaceShiftColors.blue,
          secondary: SpaceShiftColors.purple,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: SpaceShiftColors.textPrimary,
          displayColor: SpaceShiftColors.textPrimary,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SpaceShiftColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SpaceShiftColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: SpaceShiftColors.selectionAccent,
              width: 1.5,
            ),
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
