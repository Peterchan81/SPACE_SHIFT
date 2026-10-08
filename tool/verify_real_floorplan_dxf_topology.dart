// SS CAD TEST — C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN_TOPOLOGY.dxf 독립 검증.
// 프로덕션 코드를 전혀 거치지 않는 별도 파서로 원본 DXF 텍스트를 다시
// 읽는다. 기준 벽은 두 조각(같은 x축)으로 남아 있으므로 합산 길이로
// 4700mm를 검증한다.
// 실행: flutter test tool/verify_real_floorplan_dxf_topology.dart (네트워크 없음)
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

class _Line {
  _Line(this.layer, this.x1, this.y1, this.x2, this.y2);
  final String layer;
  final double x1, y1, x2, y2;
  double get lengthMm => math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
  double get avgX => (x1 + x2) / 2;
}

List<_Line> _parseLines(String dxf) {
  final lines = dxf.split('\n').map((l) => l.trim()).toList();
  final out = <_Line>[];
  for (var i = 0; i < lines.length - 1; i++) {
    if (lines[i] == '0' && lines[i + 1] == 'LINE') {
      String? layer;
      double? x1, y1, x2, y2;
      var j = i + 2;
      while (j + 1 < lines.length && lines[j] != '0') {
        final code = lines[j];
        final value = lines[j + 1];
        switch (code) {
          case '8': layer = value;
          case '10': x1 = double.parse(value);
          case '20': y1 = double.parse(value);
          case '11': x2 = double.parse(value);
          case '21': y2 = double.parse(value);
        }
        j += 2;
      }
      if (layer != null && x1 != null && y1 != null && x2 != null && y2 != null) {
        out.add(_Line(layer, x1, y1, x2, y2));
      }
      i = j - 1;
    }
  }
  return out;
}

void main() {
  test('topology DXF 독립 재파싱: 골격/레이어/기준벽(합산) 4700mm 검증', () {
    const path = r'C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN_TOPOLOGY.dxf';
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path 가 존재해야 한다');
    final content = file.readAsStringSync();

    expect(content, contains('SECTION'));
    expect(content, contains('ENTITIES'));
    expect(content.trim(), endsWith('0\nEOF'));

    final parsed = _parseLines(content);
    final byLayer = <String, List<_Line>>{};
    for (final l in parsed) {
      byLayer.putIfAbsent(l.layer, () => []).add(l);
    }
    print('=== 독립 재파싱 결과 ===');
    print('총 LINE 개체 수: ${parsed.length}');
    for (final entry in byLayer.entries) {
      print('레이어 ${entry.key}: ${entry.value.length}개');
    }

    final exteriorLines = byLayer['SS-EXTERIOR-WALL'] ?? const [];
    const mmPerPixel = 28.421252;
    final approxX = 0.0542 * 840 * mmPerPixel;
    final nearAxis = exteriorLines.where((l) => (l.avgX - approxX).abs() < 50).toList();
    print('\n=== x≈${approxX.toStringAsFixed(0)}mm 부근 외벽 선분 ${nearAxis.length}개 ===');
    for (final l in nearAxis) {
      print('lengthMm=${l.lengthMm.toStringAsFixed(1)}');
    }
    expect(nearAxis, isNotEmpty, reason: '기준 실측 벽 부근에 외벽 선분이 있어야 한다');

    final combinedMm = nearAxis.fold<double>(0, (sum, l) => sum + l.lengthMm);
    print('\n합산 길이=${combinedMm.toStringAsFixed(4)} mm (기대값 4700mm)');
    expect(combinedMm, closeTo(4700.0, 1.0));
  });
}
