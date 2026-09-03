import 'package:flutter/material.dart';

import 'gpt_cad_poc_screen.dart';

/// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC
/// 전용 entry point. `lib/main.dart`(실제 앱)와 완전히 분리된 별도 실행
/// 대상이다.
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/gpt_vision_v1/gpt_cad_poc_main.dart -d windows
void main() {
  runApp(const _GptCadPocApp());
}

class _GptCadPocApp extends StatelessWidget {
  const _GptCadPocApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Real GPT Vision CAD POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const GptCadPocScreen(),
    );
  }
}
