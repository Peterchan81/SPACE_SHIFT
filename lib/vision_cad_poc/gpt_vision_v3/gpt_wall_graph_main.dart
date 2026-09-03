import 'package:flutter/material.dart';

import 'gpt_wall_graph_screen.dart';

/// SPACE SHIFT — Canonical Wall Graph First POC 전용 entry point.
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/gpt_vision_v3/gpt_wall_graph_main.dart -d windows
void main() {
  runApp(const _WallGraphApp());
}

class _WallGraphApp extends StatelessWidget {
  const _WallGraphApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Canonical Wall Graph POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const GptWallGraphScreen(),
    );
  }
}
