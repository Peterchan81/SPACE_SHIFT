import 'package:flutter/material.dart';

import '../models/cad_floor_plan.dart';
import '../models/ss_spatial_model.dart';
import '../services/mock_vision_interpretation_service.dart';
import '../services/vision_guided_spatial_model_builder.dart';
import 'sample_image2_fixture.dart';
import 'vision_cad_preview.dart';

/// SPACE SHIFT — Vision Guided CAD POC 전용 entry point. `lib/main.dart`
/// (실제 앱)와 완전히 분리된 별도 실행 대상이다 — MASTER UI/production
/// pipeline을 전혀 거치지 않는다(WO 절대 금지 — production 화면/3D
/// 렌더러를 건드리지 않는다).
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/poc_main.dart -d windows
///
/// "이미지 2" 원본 파일은 이 저장소에 없다(정직한 고지 —
/// [sample_image2_fixture.dart] 상단 문서 참고) — 실제 구조를 재현한
/// 합성 픽셀 이미지를 대신 사용하고, 화면에도 그 사실을 그대로 밝힌다.
void main() {
  runApp(const _VisionCadPocApp());
}

class _VisionCadPocApp extends StatelessWidget {
  const _VisionCadPocApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Vision Guided CAD POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const _PocScreen(),
    );
  }
}

class _PocScreen extends StatefulWidget {
  const _PocScreen();

  @override
  State<_PocScreen> createState() => _PocScreenState();
}

class _PocScreenState extends State<_PocScreen> {
  late final Future<({CadFloorPlan cad, SSSpatialModel model})> _future = _run();

  Future<({CadFloorPlan cad, SSSpatialModel model})> _run() async {
    final builder = VisionGuidedSpatialModelBuilder(visionService: const MockVisionInterpretationService());
    final imageBytes = buildImage2Png();
    final model = await builder.build(imageBytes);
    final cad = buildCadFloorPlanFromSpatialModel(model);
    return (cad: cad, model: model);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SPACE SHIFT — Vision Guided CAD POC · 이미지 2 (독립, production 미연결)',
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFECEFF1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Text(
                '정직한 고지: 실제 사용자 첨부 원본 파일 대신, 동일한 실제 구조(13개 '
                '공간·문 위치)를 재현한 합성 이미지를 사용합니다. Mock Vision Provider는 '
                '실제 API를 호출하지 않으며, 이 화면에 그려진 CAD geometry는 그 hint를 '
                '실제 픽셀에서 정밀화·검증한 결과입니다(최종 좌표를 손으로 넣지 않았습니다).',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
            Expanded(
              child: FutureBuilder(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('오류: ${snapshot.error}'));
                  }
                  final result = snapshot.data!;
                  return VisionCadPreview(
                    originalImageBytes: buildImage2Png(),
                    cad: result.cad,
                    spatialModel: result.model,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
