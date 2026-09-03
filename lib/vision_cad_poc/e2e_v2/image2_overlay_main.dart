import 'package:flutter/material.dart';

import 'image2_overlay_screen.dart';

/// SPACE SHIFT — Image 2 GPT Detailed CAD Geometry POC 전용 entry point.
/// `lib/main.dart`(실제 앱)와 완전히 분리된 별도 실행 대상이다.
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/e2e_v2/image2_overlay_main.dart -d windows
void main() {
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Image2 Detailed CAD Overlay POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const Image2OverlayScreen(),
    );
  }
}
