import 'package:flutter/material.dart';

import 'gpt_boundary_loop_screen.dart';

/// SPACE SHIFT — GPT Space Boundary Loop Recovery POC 전용 entry point.
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/gpt_vision_v2/gpt_boundary_loop_main.dart -d windows
void main() {
  runApp(const _BoundaryLoopApp());
}

class _BoundaryLoopApp extends StatelessWidget {
  const _BoundaryLoopApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS GPT Boundary Loop Recovery POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const GptBoundaryLoopScreen(),
    );
  }
}
