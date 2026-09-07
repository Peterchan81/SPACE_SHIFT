import 'package:flutter/material.dart';

import 'drafting_screen.dart';

/// SPACE SHIFT — WO088-4 Drafting Coordinate POC 전용 entry point.
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/drafting_v1/drafting_main.dart -d windows
void main() {
  runApp(const _DraftingApp());
}

class _DraftingApp extends StatelessWidget {
  const _DraftingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Drafting Coordinate POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const DraftingScreen(),
    );
  }
}
