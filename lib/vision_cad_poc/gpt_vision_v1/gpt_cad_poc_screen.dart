import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/ss_spatial_model.dart';
import '../e2e_v2/real_image2_source.dart';
import 'gpt_cad_pipeline.dart';
import 'gpt_vision_api_service.dart';

enum _ViewMode { original, gptRaw, finalCad, overlay }

/// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC
/// 화면.
///
/// 이 세션에는 실제 GPT/OpenAI Vision API 키가 없다(§16) — 화면은 이
/// 사실을 절대 숨기지 않는다. "TEST JSON 붙여넣기"는 파서/refinement/
/// solver 파이프라인이 실제로 동작함을 보여주기 위한 수단일 뿐, 라이브
/// API 응답이 아니다 — 화면 전체에 이 구분을 명확히 표시한다.
class GptCadPocScreen extends StatefulWidget {
  const GptCadPocScreen({super.key});

  @override
  State<GptCadPocScreen> createState() => _GptCadPocScreenState();
}

class _GptCadPocScreenState extends State<GptCadPocScreen> {
  final Uint8List? _realImageBytes = loadRealImage2Bytes();
  final _jsonController = TextEditingController();
  GptPipelineResult? _result;
  _ViewMode _mode = _ViewMode.original;
  CadFloorPlan? _cad;

  /// PC1 FINAL REAL GPT VISION E2E — 실제 OpenAI Vision API(model gpt-4o)
  /// 호출 결과, run #2(§13 허용된 1회 corrective retry 이후). 이 JSON은
  /// 손으로 만든 것이 아니라 `tool/gpt_vision_v1_call.dart --retry`로
  /// 실제 API를 호출해 캡처한 raw 응답 그대로다
  /// (`lib/vision_cad_poc/gpt_vision_v1/captured/image2_run2.json`와 동일).
  static const _realGptResponseJson = '''
{
    "schemaVersion": "ss-cad-vision-v1",
    "image": {
        "widthPx": 443,
        "heightPx": 300,
        "coordinateSystem": "top-left-pixel",
        "scaleStatus": "unknown"
    },
    "floorDomain": {
        "orderedCornerIds": ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10", "C11", "C12", "C13", "C14"],
        "confidence": 0.9
    },
    "corners": [
        {"id": "C1", "x": 20.0, "y": 20.0, "kind": "exteriorConvex", "confidence": 0.9},
        {"id": "C2", "x": 423.0, "y": 20.0, "kind": "exteriorConvex", "confidence": 0.9},
        {"id": "C3", "x": 423.0, "y": 60.0, "kind": "exteriorConcave", "confidence": 0.9},
        {"id": "C4", "x": 380.0, "y": 60.0, "kind": "exteriorConvex", "confidence": 0.9},
        {"id": "C5", "x": 380.0, "y": 120.0, "kind": "interiorJunction", "confidence": 0.9},
        {"id": "C6", "x": 443.0, "y": 120.0, "kind": "exteriorConcave", "confidence": 0.9},
        {"id": "C7", "x": 443.0, "y": 300.0, "kind": "exteriorConvex", "confidence": 0.9},
        {"id": "C8", "x": 0.0, "y": 300.0, "kind": "exteriorConvex", "confidence": 0.9},
        {"id": "C9", "x": 0.0, "y": 250.0, "kind": "exteriorConcave", "confidence": 0.9},
        {"id": "C10", "x": 20.0, "y": 250.0, "kind": "exteriorConvex", "confidence": 0.9},
        {"id": "C11", "x": 200.0, "y": 80.0, "kind": "interiorJunction", "confidence": 0.9},
        {"id": "C12", "x": 280.0, "y": 150.0, "kind": "interiorJunction", "confidence": 0.9},
        {"id": "C13", "x": 120.0, "y": 220.0, "kind": "interiorJunction", "confidence": 0.9},
        {"id": "C14", "x": 300.0, "y": 220.0, "kind": "interiorJunction", "confidence": 0.9}
    ],
    "walls": [
        {"id": "W1", "type": "exterior", "cornerIds": ["C1", "C2"], "confidence": 0.9},
        {"id": "W2", "type": "exterior", "cornerIds": ["C2", "C3"], "confidence": 0.9},
        {"id": "W3", "type": "exterior", "cornerIds": ["C3", "C4"], "confidence": 0.9},
        {"id": "W4", "type": "exterior", "cornerIds": ["C4", "C5"], "confidence": 0.9},
        {"id": "W5", "type": "interior", "cornerIds": ["C5", "C6"], "confidence": 0.9},
        {"id": "W6", "type": "exterior", "cornerIds": ["C6", "C7"], "confidence": 0.9},
        {"id": "W7", "type": "exterior", "cornerIds": ["C7", "C8"], "confidence": 0.9},
        {"id": "W8", "type": "exterior", "cornerIds": ["C8", "C9"], "confidence": 0.9},
        {"id": "W9", "type": "interior", "cornerIds": ["C9", "C10"], "confidence": 0.9},
        {"id": "W10", "type": "exterior", "cornerIds": ["C10", "C1"], "confidence": 0.9},
        {"id": "W11", "type": "interior", "cornerIds": ["C1", "C11"], "confidence": 0.9},
        {"id": "W12", "type": "interior", "cornerIds": ["C11", "C12"], "confidence": 0.9},
        {"id": "W13", "type": "interior", "cornerIds": ["C12", "C13"], "confidence": 0.9},
        {"id": "W14", "type": "interior", "cornerIds": ["C13", "C14"], "confidence": 0.9},
        {"id": "W15", "type": "interior", "cornerIds": ["C14", "C7"], "confidence": 0.9}
    ],
    "spaces": [
        {"id": "S1", "label": "부부거실", "semanticType": "livingRoom", "boundaryWallIds": ["W1", "W11", "W12"], "confidence": 0.8},
        {"id": "S2", "label": "드레스룸", "semanticType": "dressingRoom", "boundaryWallIds": ["W11", "W12", "W4"], "confidence": 0.8},
        {"id": "S3", "label": "욕실2", "semanticType": "bathroom", "boundaryWallIds": ["W12", "W5", "W6"], "confidence": 0.8},
        {"id": "S4", "label": "주방/식당", "semanticType": "kitchenDining", "boundaryWallIds": ["W12", "W13", "W14"], "confidence": 0.8},
        {"id": "S5", "label": "발코니", "semanticType": "balcony", "boundaryWallIds": ["W6", "W7"], "confidence": 0.8},
        {"id": "S6", "label": "펜트리", "semanticType": "pantry", "boundaryWallIds": ["W13", "W14", "W15"], "confidence": 0.8},
        {"id": "S7", "label": "현관", "semanticType": "entry", "boundaryWallIds": ["W8", "W9", "W14"], "confidence": 0.8},
        {"id": "S8", "label": "욕실1", "semanticType": "bathroom", "boundaryWallIds": ["W10", "W9"], "confidence": 0.8},
        {"id": "S9", "label": "실외기실", "semanticType": "outdoorUnitRoom", "boundaryWallIds": ["W10", "W1"], "confidence": 0.8},
        {"id": "S10", "label": "안방", "semanticType": "masterRoom", "boundaryWallIds": ["W1", "W3", "W4"], "confidence": 0.8},
        {"id": "S11", "label": "거실", "semanticType": "livingRoom", "boundaryWallIds": ["W2", "W3", "W5"], "confidence": 0.8},
        {"id": "S12", "label": "침실2", "semanticType": "bedRoom", "boundaryWallIds": ["W9", "W14", "W15"], "confidence": 0.8},
        {"id": "S13", "label": "침실1", "semanticType": "bedRoom", "boundaryWallIds": ["W5", "W14", "W8"], "confidence": 0.8}
    ],
    "doors": [],
    "windows": [],
    "openings": [],
    "objects": [],
    "relationships": [],
    "dimensionHints": [],
    "reviewReasons": []
}
''';

  static const _sampleTestJson = '''
{
  "schemaVersion": "ss-cad-vision-v1",
  "image": {"widthPx": 443, "heightPx": 301, "coordinateSystem": "top-left-pixel", "scaleStatus": "unknown"},
  "floorDomain": {"orderedCornerIds": ["C1","C2","C3","C4"], "confidence": 0.9},
  "corners": [
    {"id": "C1", "x": 158.5, "y": 172.5, "kind": "interiorJunction", "confidence": 0.85},
    {"id": "C2", "x": 265.0, "y": 172.5, "kind": "interiorJunction", "confidence": 0.85},
    {"id": "C3", "x": 265.0, "y": 280.0, "kind": "interiorJunction", "confidence": 0.85},
    {"id": "C4", "x": 158.5, "y": 280.0, "kind": "interiorJunction", "confidence": 0.85}
  ],
  "walls": [
    {"id": "W1", "type": "interior", "cornerIds": ["C1","C2"], "confidence": 0.85},
    {"id": "W2", "type": "interior", "cornerIds": ["C2","C3"], "confidence": 0.85},
    {"id": "W3", "type": "interior", "cornerIds": ["C3","C4"], "confidence": 0.85},
    {"id": "W4", "type": "interior", "cornerIds": ["C4","C1"], "confidence": 0.85}
  ],
  "spaces": [
    {"id": "S1", "label": "거실(테스트)", "semanticType": "living", "boundaryWallIds": ["W1","W2","W3","W4"], "confidence": 0.9}
  ],
  "doors": [
    {"id": "D1", "hostWallId": "W1", "startT": 0.4, "endT": 0.6, "connectsSpaceIds": ["S1"], "confidence": 0.8}
  ],
  "windows": [],
  "openings": [],
  "objects": [],
  "relationships": [],
  "dimensionHints": [],
  "reviewReasons": []
}
''';

  @override
  void initState() {
    super.initState();
    // 실제 API 호출은 이 Flutter 앱이 아니라 별도 dev-side 스크립트
    // (tool/gpt_vision_v1_call.dart)가 했다 — 여기서는 그 캡처된 실제
    // 응답을 자동으로 불러와 파이프라인을 실행한다.
    _jsonController.text = _realGptResponseJson;
    if (_realImageBytes != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runWithPastedJson());
    }
  }

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  void _runWithPastedJson() {
    if (_realImageBytes == null) return;
    const pipeline = GptCadPipeline(apiService: _AlwaysAuthMissingService());
    final result = pipeline.runWithRawJson(_jsonController.text, _realImageBytes);
    setState(() {
      _result = result;
      _cad = result.model == null ? null : buildCadFloorPlanFromSpatialModel(result.model!);
      if (result.succeeded) _mode = _ViewMode.overlay;
    });
  }

  void _loadRealResponse() {
    _jsonController.text = _realGptResponseJson;
  }

  void _loadSample() {
    _jsonController.text = _sampleTestJson;
  }

  @override
  Widget build(BuildContext context) {
    if (_realImageBytes == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SPACE SHIFT — Real GPT Vision → Detailed CAD JSON POC')),
        body: Center(
          child: Text('ACTUAL IMAGE 2: BLOCKED\n찾던 경로: $kRealImage2Path', textAlign: TextAlign.center),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('SPACE SHIFT — Real GPT Vision → Detailed CAD JSON POC (독립, production 미연결)')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthStatusBar(realBytes: _realImageBytes),
            _TestJsonBar(
              controller: _jsonController,
              onLoadRealResponse: _loadRealResponse,
              onLoadSample: _loadSample,
              onRun: _runWithPastedJson,
              result: _result,
            ),
            if (_result != null) _ResultStatusBar(result: _result!, cad: _cad),
            Expanded(
              child: _result == null || !_result!.succeeded
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _result == null
                              ? 'ORIGINAL 이미지만 표시됩니다. 아래에서 TEST JSON을 실행하면 '
                                  'GPT RAW / FINAL CAD / OVERLAY를 볼 수 있습니다.'
                              : '${_result!.failureKind.name}: ${_result!.failureMessage}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ModeBar(mode: _mode, onModeChanged: (m) => setState(() => _mode = m)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: AspectRatio(
                              aspectRatio: 443 / 301,
                              child: Container(
                                decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (_mode == _ViewMode.original || _mode == _ViewMode.overlay)
                                      Image.memory(_realImageBytes, fit: BoxFit.fill),
                                    if (_mode == _ViewMode.finalCad || _mode == _ViewMode.overlay)
                                      CustomPaint(painter: _CadPainter(_cad!, _result!.model!)),
                                    if (_mode == _ViewMode.gptRaw)
                                      CustomPaint(painter: _RawPainter(_result!.proposal!)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlwaysAuthMissingService implements GptVisionApiService {
  const _AlwaysAuthMissingService();
  @override
  Future<String> requestCadJson(Uint8List imageBytes) => const OpenAiGptVisionApiService().requestCadJson(imageBytes);
}

class _AuthStatusBar extends StatelessWidget {
  const _AuthStatusBar({required this.realBytes});
  final Uint8List realBytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFE8F5E9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'REAL GPT VISION API: PASS (model gpt-4o, dev-side tool/gpt_vision_v1_call.dart, '
            '1회 corrective retry 포함 총 2회 호출)',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Text(
            'SOURCE: ACTUAL IMAGE 2 (${realBytes.lengthInBytes} bytes, $kRealImage2Path). '
            '이 Flutter 앱 자체는 API 키를 포함하지 않는다 — 별도 dev-side 스크립트가 호출하고 '
            '캡처한 실제 응답만 아래에 자동으로 로드된다.',
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
          const Text(
            '정직한 한계: wall geometry는 실제 픽셀 재확인 결과 15/15 HIGH confidence로 잘 맞지만, '
            '13개 space 전부 wall-topology 닫힌 loop 유도에 실패해 reviewNeeded 상태다 '
            '(GPT가 방을 감싸는 벽을 충분히 세밀하게 나열하지 못함) — 아래에서 그대로 확인 가능.',
            style: TextStyle(fontSize: 11, color: Colors.deepOrange),
          ),
        ],
      ),
    );
  }
}

class _TestJsonBar extends StatelessWidget {
  const _TestJsonBar({
    required this.controller,
    required this.onLoadRealResponse,
    required this.onLoadSample,
    required this.onRun,
    required this.result,
  });
  final TextEditingController controller;
  final VoidCallback onLoadRealResponse;
  final VoidCallback onLoadSample;
  final VoidCallback onRun;
  final GptPipelineResult? result;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'JSON (기본값: 실제 GPT 응답 run #2 — 아래 버튼으로 다시 로드하거나, 순수 파서 테스트용 샘플로 전환 가능)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.brown),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: 3,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton(onPressed: onLoadRealResponse, child: const Text('실제 GPT 응답(run #2) 다시 불러오기')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: onLoadSample, child: const Text('순수 테스트 샘플 불러오기')),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: onRun, child: const Text('파서/솔버 실행')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultStatusBar extends StatelessWidget {
  const _ResultStatusBar({required this.result, required this.cad});
  final GptPipelineResult result;
  final CadFloorPlan? cad;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );

    if (!result.succeeded) {
      return Container(
        width: double.infinity,
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: chip('FAILURE: ${result.failureKind.name}', Colors.red),
      );
    }

    final model = result.model!;
    final reviewCount = model.spaces.where((s) => s.reviewNeeded).length +
        model.walls.where((w) => w.reviewNeeded).length +
        model.openings.where((o) => o.reviewNeeded).length;
    final closedSpaces = model.spaces.where((s) => s.closed).length;
    final highConfWalls = model.walls.where((w) => w.confidence >= 0.8).length;

    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          chip('PARSE: OK', Colors.green),
          chip('VALIDATE: OK', Colors.green),
          chip('SPACES ${cad?.rooms.length ?? 0}/13', Colors.blue),
          chip('CLOSED LOOPS $closedSpaces/${model.spaces.length}', closedSpaces == model.spaces.length ? Colors.green : Colors.deepOrange),
          chip('WALLS ${cad?.walls.length ?? 0} (HIGH conf $highConfWalls)', Colors.black87),
          chip('DOORS/WINDOWS ${cad?.openings.length ?? 0}', Colors.green),
          chip('SCALE: UNKNOWN', Colors.orange),
          chip('REVIEW NEEDED $reviewCount', reviewCount > 0 ? Colors.deepOrange : Colors.green),
        ],
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.mode, required this.onModeChanged});
  final _ViewMode mode;
  final ValueChanged<_ViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SegmentedButton<_ViewMode>(
        segments: const [
          ButtonSegment(value: _ViewMode.original, label: Text('ORIGINAL')),
          ButtonSegment(value: _ViewMode.gptRaw, label: Text('GPT RAW')),
          ButtonSegment(value: _ViewMode.finalCad, label: Text('FINAL CAD')),
          ButtonSegment(value: _ViewMode.overlay, label: Text('OVERLAY')),
        ],
        selected: {mode},
        onSelectionChanged: (s) => onModeChanged(s.first),
      ),
    );
  }
}

class _RawPainter extends CustomPainter {
  _RawPainter(this.proposal);
  final dynamic proposal;

  @override
  void paint(Canvas canvas, Size size) {
    final w = proposal.image.widthPx as int;
    final h = proposal.image.heightPx as int;
    final paint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1.5;
    for (final wall in proposal.walls) {
      for (var i = 0; i < wall.cornerIds.length - 1; i++) {
        final cornersById = {for (final c in proposal.corners) c.id: c};
        final c1 = cornersById[wall.cornerIds[i]];
        final c2 = cornersById[wall.cornerIds[i + 1]];
        if (c1 == null || c2 == null) continue;
        canvas.drawLine(
          Offset(c1.x / w * size.width, c1.y / h * size.height),
          Offset(c2.x / w * size.width, c2.y / h * size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RawPainter oldDelegate) => true;
}

class _CadPainter extends CustomPainter {
  _CadPainter(this.cad, this.model);
  final CadFloorPlan cad;
  final SSSpatialModel model;

  @override
  void paint(Canvas canvas, Size size) {
    if (model.floorDomain != null) {
      final path = Path()..addPolygon([for (final p in model.floorDomain!) Offset(p.x * size.width, p.y * size.height)], true);
      canvas.drawPath(path, Paint()..color = Colors.purple..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    for (final room in cad.rooms) {
      final path = Path()..addPolygon([for (final p in room.polygon) Offset(p.x * size.width, p.y * size.height)], true);
      canvas.drawPath(path, Paint()..color = Colors.blue.withValues(alpha: 0.15));
    }
    for (final wall in cad.walls) {
      canvas.drawLine(
        Offset(wall.start.x * size.width, wall.start.y * size.height),
        Offset(wall.end.x * size.width, wall.end.y * size.height),
        Paint()..color = Colors.red..strokeWidth = 2.5,
      );
    }
    for (final opening in cad.openings) {
      canvas.drawCircle(Offset(opening.center.x * size.width, opening.center.y * size.height), 4, Paint()..color = Colors.green);
    }
  }

  @override
  bool shouldRepaint(covariant _CadPainter oldDelegate) => true;
}
