import 'package:flutter/material.dart';

import 'image2_e2e_screen.dart';

/// SPACE SHIFT — Image 2 AI → Real CAD End-to-End POC 전용 entry point.
/// `lib/main.dart`(실제 앱)와 완전히 분리된 별도 실행 대상이다.
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/e2e/image2_e2e_main.dart -d windows
void main() {
  runApp(const _E2eApp());
}

class _E2eApp extends StatelessWidget {
  const _E2eApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Image2 AI to CAD E2E POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const Image2E2eScreen(),
    );
  }
}
