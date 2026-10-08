import 'package:flutter/material.dart';

import 'clean_cad_preview.dart';
import 'floorplan_semantic_model.dart';
import 'geometry_normalizer.dart';
import 'sample_floorplan_data.dart';

/// SPACE SHIFT — Vision-style Floorplan Understanding POC 전용 entry
/// point. `lib/main.dart`(실제 앱)와 완전히 분리된 별도 실행 대상이다 —
/// MASTER UI/production pipeline을 전혀 거치지 않는다.
///
/// 실행:
///   flutter run -t lib/poc_vision_understanding/poc_main.dart -d windows
void main() {
  final normalized = const GeometryNormalizer().normalize(sampleUnderstanding);
  runApp(_PocApp(understanding: normalized));
}

class _PocApp extends StatelessWidget {
  const _PocApp({required this.understanding});

  final FloorplanUnderstanding understanding;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Vision Understanding POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('SPACE SHIFT — Vision Understanding POC (독립, production 미연결)'),
        ),
        body: CleanCadPreview(understanding: understanding),
      ),
    );
  }
}
