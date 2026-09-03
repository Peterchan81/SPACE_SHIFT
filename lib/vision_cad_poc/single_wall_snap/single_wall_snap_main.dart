import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'single_wall_snap_detector.dart';
import 'single_wall_snap_fixture.dart';

/// SPACE SHIFT — Vision Hint → Exact Wall SNAP 기술검증 전용 entry
/// point. 기존 Vision Guided CAD POC(`lib/vision_cad_poc/poc_main.dart`)
/// 와 완전히 분리된 별도 실행 대상이다 — 벽 1개의 SNAP 성능만 본다.
///
/// 실행:
///   flutter run -t lib/vision_cad_poc/single_wall_snap/single_wall_snap_main.dart -d windows
void main() {
  runApp(const _SnapApp());
}

class _SnapApp extends StatelessWidget {
  const _SnapApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SS Single Wall Snap 기술검증',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const _SnapScreen(),
    );
  }
}

class _SnapScreen extends StatelessWidget {
  const _SnapScreen();

  @override
  Widget build(BuildContext context) {
    final imageBytes = buildSingleWallSnapImage();
    const hint = SingleWallHint(
      xNormalized: kSnapVisionHintX,
      startYNormalized: kSnapVisionHintStartYNorm,
      endYNormalized: kSnapVisionHintEndYNorm,
    );
    final result = const SingleWallSnapDetector().detect(imageBytes, hint);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SPACE SHIFT — Single Wall Snap 기술검증 (거실|침실2, 독립/production 미연결)'),
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
                '정직한 고지: 실제 사용자 원본 파일을 파일시스템으로 추출할 수 없어, '
                '"거실|침실2 세로 내부벽" 상황을 재현한 독립 합성 이미지를 사용합니다. '
                '이 이미지의 실제 벽 중심은 x=460px(정규화 0.575)이며, 사용자가 준 Vision '
                'hint(x=0.61)와 의도적으로 다릅니다 — 검출기가 hint 값을 그대로 베끼지 '
                '않고 실제 픽셀에서 벽을 다시 찾아내는지 보기 위함입니다. 기존 production '
                'Vision-Guided 파이프라인/다른 벽/방/FloorDomain은 이 작업에서 전혀 '
                '건드리지 않았습니다.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AspectRatio(
                        aspectRatio: kSnapImageWidth / kSnapImageHeight,
                        child: CustomPaint(
                          foregroundPainter: _OverlayPainter(hint: hint, result: result),
                          child: Image.memory(Uint8List.fromList(imageBytes), fit: BoxFit.fill),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _ReadoutPanel(hint: hint, result: result),
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

class _ReadoutPanel extends StatelessWidget {
  const _ReadoutPanel({required this.hint, required this.result});

  final SingleWallHint hint;
  final SingleWallSnapResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final rows = <(String, String)>[
      ('Vision X (normalized)', hint.xNormalized.toStringAsFixed(3)),
      ('Vision X (px)', (hint.xNormalized * kSnapImageWidth).toStringAsFixed(1)),
      ('Ground-truth center X (px)', kSnapRealWallCenterX.toStringAsFixed(1)),
      ('---', '---'),
      ('Detected Left Edge X (px)', r == null ? '검출 실패' : r.leftEdgeX.toStringAsFixed(1)),
      ('Detected Right Edge X (px)', r == null ? '검출 실패' : r.rightEdgeX.toStringAsFixed(1)),
      ('Detected Center X (px)', r == null ? '검출 실패' : r.centerX.toStringAsFixed(1)),
      ('Thickness (px)', r == null ? '검출 실패' : r.thicknessPx.toStringAsFixed(1)),
      ('Detected Start Y (px)', r == null ? '검출 실패' : r.startY.toStringAsFixed(1)),
      ('Detected End Y (px)', r == null ? '검출 실패' : r.endY.toStringAsFixed(1)),
      ('Start Junction Confirmed', r == null ? '-' : r.startJunctionConfirmed.toString()),
      ('End Junction Confirmed', r == null ? '-' : r.endJunctionConfirmed.toString()),
      ('Confidence', r == null ? 'FAIL' : r.confidence),
    ];

    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text('측정값', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(row.$1, style: const TextStyle(fontSize: 12))),
                  Text(row.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (r != null) ...[
            const Text('confidence 근거', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            for (final reason in r.confidenceReasons)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('· $reason', style: const TextStyle(fontSize: 11)),
              ),
          ],
          const SizedBox(height: 16),
          const _Legend(),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget row(Color color, String label, {bool dashed = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 20, height: 3, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('범례', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        row(Colors.purple, 'Vision Hint (점선)'),
        row(Colors.red, 'Detected Left Edge'),
        row(Colors.blue, 'Detected Right Edge'),
        row(Colors.green, 'Calculated Centerline'),
        row(Colors.orange, 'Search Window'),
        row(Colors.black, 'Detected Start/End Point (점)'),
      ],
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.hint, required this.result});

  final SingleWallHint hint;
  final SingleWallSnapResult? result;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / kSnapImageWidth;
    final scaleY = size.height / kSnapImageHeight;

    // Vision hint (점선, 보라색).
    final hintPaint = Paint()
      ..color = Colors.purple
      ..strokeWidth = 2;
    final hintX = hint.xNormalized * kSnapImageWidth * scaleX;
    _drawDashedLine(
      canvas,
      Offset(hintX, hint.startYNormalized * kSnapImageHeight * scaleY),
      Offset(hintX, hint.endYNormalized * kSnapImageHeight * scaleY),
      hintPaint,
    );

    final r = result;
    if (r == null) return;

    // Search window (주황색 점선 사각형).
    final windowPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(
      Rect.fromLTRB(
        r.searchWindow.left * scaleX,
        r.searchWindow.top * scaleY,
        r.searchWindow.right * scaleX,
        r.searchWindow.bottom * scaleY,
      ),
      windowPaint,
    );

    // Left edge (빨강), right edge (파랑), centerline (초록).
    void solidLine(double x, Color color) {
      canvas.drawLine(
        Offset(x * scaleX, r.startY * scaleY),
        Offset(x * scaleX, r.endY * scaleY),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
    }

    solidLine(r.leftEdgeX, Colors.red);
    solidLine(r.rightEdgeX, Colors.blue);
    solidLine(r.centerX, Colors.green);

    // Start/end point.
    final pointPaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset(r.centerX * scaleX, r.startY * scaleY), 5, pointPaint);
    canvas.drawCircle(Offset(r.centerX * scaleX, r.endY * scaleY), 5, pointPaint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 6.0;
    const gapLength = 4.0;
    final total = (end - start).distance;
    final direction = (end - start) / total;
    var covered = 0.0;
    while (covered < total) {
      final segStart = start + direction * covered;
      final segEnd = start + direction * (covered + dashLength).clamp(0, total);
      canvas.drawLine(segStart, segEnd, paint);
      covered += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => true;
}
