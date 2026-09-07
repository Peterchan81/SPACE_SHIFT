// SPACE SHIFT — WO088-1 IMAGE 2 COORDINATE-BASED 2D STRUCTURE POC.
//
// 독립 실행: flutter run -t lib/vision_cad_poc/coord_structure_v1/coord_structure_main.dart
// 기존 production main.dart/floor_plan_workspace_screen.dart와 완전히
// 분리된 실험 진입점이다(§1/§3).

import 'package:flutter/material.dart';

import 'coord_structure_screen.dart';

void main() {
  runApp(const _CoordStructureApp());
}

class _CoordStructureApp extends StatelessWidget {
  const _CoordStructureApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: CoordStructureScreen());
  }
}
