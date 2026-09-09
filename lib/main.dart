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
      title: 'SS CAD TEST',
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
      // SS CAD TEST 전용 식별 배너 — 로그인 화면부터 모든 작업 화면까지
      // 항상 눈에 띄게 떠 있어야 한다(원본 SPACE SHIFT와 최근 앱 화면 등에서
      // 혼동해 실수로 조작하는 사고가 있었음). builder로 전역 오버레이해
      // 개별 화면 코드는 건드리지 않는다. IgnorePointer로 터치를 절대
      // 가로채지 않아 기존 CAD UI 동작에 영향이 없다.
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return Stack(
          children: [child, const IgnorePointer(child: _CadTestBadge())],
        );
      },
    );
  }
}

/// SS CAD TEST(개발용) 식별 배너. 원본 SPACE SHIFT와 화면이 동일해 보여
/// 사용자가 앱을 혼동한 사고 이후 도입 — 화면 최상단에 항상 고정 표시된다.
class _CadTestBadge extends StatelessWidget {
  const _CadTestBadge();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          color: const Color(0xFFFF7A00),
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: const Text(
            'SS CAD TEST · 개발용 (SPACE SHIFT 본체 아님)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
