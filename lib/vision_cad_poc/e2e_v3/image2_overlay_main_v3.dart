import 'package:flutter/material.dart';

import 'image2_overlay_screen_v3.dart';

/// SPACE SHIFT — Image 2 GPT Direct CAD Geometry Proposal Benchmark 전용
/// entry point. `lib/main.dart`(실제 앱)와 완전히 분리된 별도 실행
/// 대상이다.
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/e2e_v3/image2_overlay_main_v3.dart -d windows
void main() {
  runApp(const _OverlayAppV3());
}

class _OverlayAppV3 extends StatelessWidget {
  const _OverlayAppV3();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Image2 GPT Direct Geometry Benchmark',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const Image2OverlayScreenV3(),
    );
  }
}
