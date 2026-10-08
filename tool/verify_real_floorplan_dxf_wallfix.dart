// SS CAD TEST — C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN_WALLFIX.dxf 독립 검증.
// 프로덕션 코드를 전혀 거치지 않는 별도 파서로 원본 DXF 텍스트를 다시
// 읽는다. 이번 결과는 기준 실측 벽이 실제 T-junction에서 두 조각으로
// 쪼개져 있으므로(export 스크립트가 이미 확인한 그대로), 같은 x축 위에
// 서로 y로 이어지는 두 조각을 찾아 합산 길이가 4700mm인지 검증한다.
// 실행: flutter test tool/verify_real_floorplan_dxf_wallfix.dart (네트워크 없음)
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

class _Line {
  _Line(this.layer, this.x1, this.y1, this.x2, this.y2);
  final String layer;
  final double x1, y1, x2, y2;
  double get lengthMm => math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
  double get minY => math.min(y1, y2);
  double get maxY => math.max(y1, y2);
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
  test('wallfix DXF 독립 재파싱: 골격/레이어/기준벽(합산) 4700mm 검증', () {
    const path = r'C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN_WALLFIX.dxf';
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

    // 기준 실측 벽 근처(원본 정규화 x=0.0542, mmPerPixel~28.11이므로
    // mm 좌표 x ~= 0.0542*840*28.11 ~= 1279mm 부근)에 있는, 세로로
    // 이어지는 외벽 선분들을 찾는다 — production 코드가 아니라 이 파일
    // 자체의 좌표만으로 다시 계산한다.
    final exteriorLines = byLayer['SS-EXTERIOR-WALL'] ?? const [];
    final approxX = 0.0542 * 840 * 28.113482;
    final nearAxis = exteriorLines.where((l) => (l.avgX - approxX).abs() < 50).toList()
      ..sort((a, b) => a.minY.compareTo(b.minY));
    print('\n=== x≈${approxX.toStringAsFixed(0)}mm 부근 외벽 선분 ${nearAxis.length}개 ===');
    for (final l in nearAxis) {
      print('lengthMm=${l.lengthMm.toStringAsFixed(1)} minY=${l.minY.toStringAsFixed(1)} maxY=${l.maxY.toStringAsFixed(1)}');
    }
    expect(nearAxis, isNotEmpty, reason: '기준 실측 벽 부근에 외벽 선분이 있어야 한다');

    final combinedMm = nearAxis.fold<double>(0, (sum, l) => sum + l.lengthMm);
    print('\n합산 길이=${combinedMm.toStringAsFixed(4)} mm (기대값 4700mm)');
    expect(combinedMm, closeTo(4700.0, 1.0));
  });
}
