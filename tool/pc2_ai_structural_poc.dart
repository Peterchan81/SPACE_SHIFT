// SPACE SHIFT — PC2 FINAL WORK ORDER §8/§9.
//
// 실제 평면도.PNG를 기존(재사용) gpt-floorplan-understand Edge Function +
// VisionUnderstanding 계약으로 실제 호출해, Wall/Room/Door/Window가
// structured JSON으로 돌아오는지 증명하고, 원본 이미지 위에 진단용
// overlay PNG를 만든다. 새 architecture를 만들지 않는다 — WO088 당시
// 만들어진 GptFloorplanEdgeFunctionVisionService/VisionUnderstanding을
// 그대로 재사용한다.
//
// dart:ui 제약 때문에 `dart run`이 아니라 `flutter test tool/...`로
// 실행해야 한다(WO102에서 이미 확인된 우회법).
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:ason_space/models/vision_understanding.dart';
import 'package:ason_space/services/gpt_floorplan_vision_service.dart';

const _realImagePath = r'C:\Users\user\Desktop\스크린샷\평면도.PNG';
const _edgeFunctionUrl = 'https://imaxmdtnknychqyphaaa.supabase.co/functions/v1/gpt-floorplan-understand';
const _overlayOutPath = r'C:\ASON\SPACE_SHIFT\test\pc2_ai_structural_overlay.png';

void main() async {
  final file = File(_realImagePath);
  if (!file.existsSync()) {
    print('REAL IMAGE NOT FOUND: $_realImagePath');
    return;
  }
  final bytes = file.readAsBytesSync();
  print('=== SOURCE ===');
  print('path=$_realImagePath bytes=${bytes.length}');

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    print('FAILED TO DECODE IMAGE');
    return;
  }
  print('decoded dims=${decoded.width}x${decoded.height}');

  final service = GptFloorplanEdgeFunctionVisionService(endpoint: Uri.parse(_edgeFunctionUrl));

  print('=== CALLING REAL EDGE FUNCTION ===');
  print('url=$_edgeFunctionUrl');
  VisionUnderstanding understanding;
  final sw = Stopwatch()..start();
  try {
    understanding = await service.interpret(bytes);
  } catch (e) {
    print('REAL AI CALL FAILED: $e');
    return;
  }
  sw.stop();
  print('call succeeded in ${sw.elapsedMilliseconds}ms');

  print('=== STRUCTURED RESULT COUNTS ===');
  print('spaces=${understanding.spaces.length}');
  print('boundaries=${understanding.boundaries.length}');
  final doors = understanding.openings.where((o) => o.openingType == VisionOpeningType.door).toList();
  final windows = understanding.openings.where((o) => o.openingType == VisionOpeningType.window).toList();
  final passages = understanding.openings.where((o) => o.openingType == VisionOpeningType.openPassage).toList();
  print('openings(all)=${understanding.openings.length} doors=${doors.length} windows=${windows.length} openPassage=${passages.length}');
  print('objects=${understanding.objects.length}');
  print('structuralElements=${understanding.structuralElements.length}');
  print('dimensions=${understanding.dimensions.length}');
  print('scaleConfirmed=${understanding.scaleConfirmed}');
  print('notes=${understanding.notes}');

  print('=== SPACES DETAIL ===');
  for (final s in understanding.spaces) {
    print('  id=${s.id} label=${s.label} semanticType=${s.semanticType.name} confidence=${s.confidence.name} hintKind=${s.geometryHint?.kind}');
  }

  print('=== BOUNDARIES DETAIL (first 30) ===');
  for (final b in understanding.boundaries.take(30)) {
    final hint = b.geometryHint;
    final plausible = hint == null ? false : hint.allPoints.every((p) => p.isPlausible);
    print('  id=${b.id} type=${b.boundaryType.name} confidence=${b.confidence.name} hintKind=${hint?.kind} plausible=$plausible');
  }

  print('=== DOORS DETAIL ===');
  for (final d in doors) {
    final hint = d.geometryHint;
    final center = hint != null && hint.kind == GeometryHintKind.point ? hint.point : null;
    print('  id=${d.id} confidence=${d.confidence.name} attachedBoundaryId=${d.attachedBoundaryId} center=${center == null ? null : '(${center.x.toStringAsFixed(3)},${center.y.toStringAsFixed(3)})'} plausible=${center?.isPlausible}');
  }

  print('=== WINDOWS DETAIL ===');
  for (final w in windows) {
    final hint = w.geometryHint;
    final center = hint != null && hint.kind == GeometryHintKind.point ? hint.point : null;
    print('  id=${w.id} confidence=${w.confidence.name} attachedBoundaryId=${w.attachedBoundaryId} center=${center == null ? null : '(${center.x.toStringAsFixed(3)},${center.y.toStringAsFixed(3)})'} plausible=${center?.isPlausible}');
  }

  // sanity: 좌표계가 원본 이미지 기준인지(0~1 범위 대부분) 확인.
  final allPoints = <NormalizedPoint>[
    ...understanding.boundaries.expand((b) => b.geometryHint?.allPoints ?? const []),
    ...understanding.spaces.expand((s) => s.geometryHint?.allPoints ?? const []),
    ...understanding.openings.expand((o) => o.geometryHint?.allPoints ?? const []),
  ];
  final implausibleCount = allPoints.where((p) => !p.isPlausible).length;
  print('=== COORDINATE SANITY ===');
  print('totalPoints=${allPoints.length} implausible(out of [-0.2,1.2])=$implausibleCount');

  // === diagnostic overlay ===
  final overlay = img.Image.from(decoded);
  final w = overlay.width, h = overlay.height;
  Offset toPx(NormalizedPoint p) => Offset(p.x * w, p.y * h);

  void drawHint(GeometryHint? hint, img.Color color, {int thickness = 3}) {
    if (hint == null) return;
    switch (hint.kind) {
      case GeometryHintKind.point:
        final p = toPx(hint.point);
        img.drawCircle(overlay, x: p.x.round(), y: p.y.round(), radius: 10, color: color);
      case GeometryHintKind.segment:
        final a = toPx(hint.start), b = toPx(hint.end);
        img.drawLine(overlay, x1: a.x.round(), y1: a.y.round(), x2: b.x.round(), y2: b.y.round(), color: color, thickness: thickness);
      case GeometryHintKind.polygon:
        final pts = hint.points.map(toPx).toList();
        for (var i = 0; i < pts.length; i++) {
          final a = pts[i], b = pts[(i + 1) % pts.length];
          img.drawLine(overlay, x1: a.x.round(), y1: a.y.round(), x2: b.x.round(), y2: b.y.round(), color: color, thickness: thickness);
        }
      case GeometryHintKind.boundingBox:
        final box = hint.boundingBox!;
        img.drawRect(
          overlay,
          x1: (box.minX * w).round(),
          y1: (box.minY * h).round(),
          x2: (box.maxX * w).round(),
          y2: (box.maxY * h).round(),
          color: color,
          thickness: thickness,
        );
    }
  }

  // floorDomain: 보라.
  drawHint(understanding.floorDomain.geometryHint, img.ColorRgb8(160, 0, 200), thickness: 3);
  // spaces: 파랑 폴리곤/박스.
  for (final s in understanding.spaces) {
    drawHint(s.geometryHint, img.ColorRgb8(30, 90, 220), thickness: 2);
  }
  // boundaries(벽): 빨강 실선.
  for (final b in understanding.boundaries) {
    drawHint(b.geometryHint, img.ColorRgb8(220, 20, 20), thickness: 3);
  }
  // doors: 초록 원.
  for (final d in doors) {
    drawHint(d.geometryHint, img.ColorRgb8(0, 180, 0), thickness: 4);
  }
  // windows: 청록 원.
  for (final win in windows) {
    drawHint(win.geometryHint, img.ColorRgb8(0, 190, 200), thickness: 4);
  }

  File(_overlayOutPath).writeAsBytesSync(img.encodePng(overlay));
  print('=== OVERLAY WRITTEN ===');
  print(_overlayOutPath);

  // 참고용 raw JSON도 남겨서 다음 세션이 실제 응답 모양을 그대로 볼 수 있게 한다.
  File(r'C:\ASON\SPACE_SHIFT\test\pc2_ai_structural_result.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(understanding.toJson()));
  print('raw json written to test/pc2_ai_structural_result.json');
}

class Offset {
  const Offset(this.x, this.y);
  final double x;
  final double y;
}
