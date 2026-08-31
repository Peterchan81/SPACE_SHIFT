import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'services/app_update_store.dart';
import 'theme/space_shift_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 인터넷 기반 무선 업데이트 확인은 Android에서만, 앱이 뜰 때 한 번
  // 배경으로 실행해 결과를 공유 싱글턴(AppUpdateStore.instance)에
  // 반영한다. 첫 프레임을 막지 않도록 await하지 않으며, 실패해도 예외를
  // 던지지 않는 AppUpdateService.checkForUpdate()를 그대로 재사용한다.
  if (!kIsWeb && Platform.isAndroid) {
    unawaited(AppUpdateStore.instance.checkForUpdate());
  }

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
