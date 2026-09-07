// SPACE SHIFT — WO087 EXISTING SEMANTIC PRODUCTION WIRING.
//
// [SemanticProvider] 추상화 자체(§15)를 검증한다 — 실제 semantic
// fusion 로직(mapSemanticZones/buildWallOpenings)은 이미 다른 테스트
// 파일들이 검증하고 있으므로 여기서는 "provider가 pipeline에 정확히
// 연결되는지"만 본다(중복 검증 금지).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/semantic_provider.dart';

Uint8List _simpleFloorPlan() {
  final image = img.Image(width: 300, height: 200);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  void thickLine(int x1, int y1, int x2, int y2) {
    for (var t = -3; t <= 3; t++) {
      if (y1 == y2) {
        img.drawLine(image, x1: x1, y1: y1 + t, x2: x2, y2: y2 + t, color: img.ColorRgb8(0, 0, 0));
      } else {
        img.drawLine(image, x1: x1 + t, y1: y1, x2: x2 + t, y2: y2, color: img.ColorRgb8(0, 0, 0));
      }
    }
  }

  thickLine(30, 30, 270, 30);
  thickLine(30, 170, 270, 170);
  thickLine(30, 30, 30, 170);
  thickLine(270, 30, 270, 170);
  return Uint8List.fromList(img.encodePng(image));
}

const _validSemanticJson = '''
{
  "spaces": [
    {"id": "S01", "label": "테스트방", "semanticType": "bedroom", "approxRegion": {"x0": 0.1, "y0": 0.15, "x1": 0.9, "y1": 0.85}}
  ]
}
''';

void main() {
  group('UnavailableSemanticProvider', () {
    test('항상 unavailable + 이유를 반환한다(§16 죽지 않는다)', () async {
      const provider = UnavailableSemanticProvider();
      final result = await provider.fetch(Uint8List(0));
      expect(result.status, SemanticProviderStatus.unavailable);
      expect(result.hasResponse, isFalse);
      expect(result.reason, isNotNull);
    });
  });

  group('CapturedFixtureSemanticProvider', () {
    test('존재하지 않는 경로 — unavailable(예외를 던지지 않는다)', () async {
      const provider = CapturedFixtureSemanticProvider('no/such/file.json');
      final result = await provider.fetch(Uint8List(0));
      expect(result.status, SemanticProviderStatus.unavailable);
      expect(result.reason, contains('없음'));
    });

    test('손상된 JSON — unavailable(예외를 던지지 않는다)', () async {
      final dir = Directory.systemTemp.createTempSync('sem_provider_test');
      final file = File('${dir.path}/bad.json')..writeAsStringSync('{not valid json');
      addTearDown(() => dir.deleteSync(recursive: true));
      final provider = CapturedFixtureSemanticProvider(file.path);
      final result = await provider.fetch(Uint8List(0));
      expect(result.status, SemanticProviderStatus.unavailable);
    });

    test('유효한 fixture — success + 실제 GptSemanticResponse를 반환한다', () async {
      final dir = Directory.systemTemp.createTempSync('sem_provider_test');
      final file = File('${dir.path}/semantic.json')..writeAsStringSync(_validSemanticJson);
      addTearDown(() => dir.deleteSync(recursive: true));
      final provider = CapturedFixtureSemanticProvider(file.path);
      final result = await provider.fetch(Uint8List(0));
      expect(result.status, SemanticProviderStatus.success);
      expect(result.hasResponse, isTrue);
      expect(result.response!.spaces.single.label, '테스트방');
    });
  });

  group('runPixelWallPipelineWithSemanticProvider — pipeline 연결', () {
    test('provider가 success면 semanticStatus=success + 결과에 semantic이 실제로 반영된다', () async {
      final dir = Directory.systemTemp.createTempSync('sem_provider_test');
      final file = File('${dir.path}/semantic.json')..writeAsStringSync(_validSemanticJson);
      addTearDown(() => dir.deleteSync(recursive: true));

      final bytes = _simpleFloorPlan();
      final withSemantic = await runPixelWallPipelineWithSemanticProvider(
        imageBytes: bytes,
        provider: CapturedFixtureSemanticProvider(file.path),
      );
      final geometryOnly = runPixelWallPipeline(imageBytes: bytes);

      expect(withSemantic.semanticStatus, SemanticProviderStatus.success);
      expect(geometryOnly.semanticStatus, SemanticProviderStatus.unavailable);
      // 같은 이미지이므로 geometry 자체(벽 개수)는 동일해야 한다 —
      // semantic은 room 라벨/opening 종류에만 영향을 준다.
      expect(withSemantic.model.walls.length, geometryOnly.model.walls.length);
    });

    test('provider가 unavailable이어도 pipeline은 죽지 않고 geometry-only로 계속된다(§16)', () async {
      final bytes = _simpleFloorPlan();
      final result = await runPixelWallPipelineWithSemanticProvider(
        imageBytes: bytes,
        provider: const UnavailableSemanticProvider(),
      );
      expect(result.semanticStatus, SemanticProviderStatus.unavailable);
      expect(result.semanticReason, isNotNull);
      expect(result.model.walls, isNotEmpty, reason: 'semantic이 없어도 geometry 분석 자체는 정상 동작해야 한다');
    });
  });
}
