import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';

void main() {
  runApp(const AsonSpaceApp());
}

/// ASON Space 앱의 루트 위젯.
///
/// Material 3 테마를 사용하며, 첫 화면으로 [SplashScreen]을 연결한다.
class AsonSpaceApp extends StatelessWidget {
  const AsonSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ASON Space',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8D6E63),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
