import 'package:flutter/material.dart';

import 'pixel_wall_screen.dart';

/// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC 전용 entry point.
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/pixel_wall_v4/pixel_wall_main.dart -d windows
void main() {
  runApp(const _PixelWallApp());
}

class _PixelWallApp extends StatelessWidget {
  const _PixelWallApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Pixel Wall Extraction POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const PixelWallScreen(),
    );
  }
}
