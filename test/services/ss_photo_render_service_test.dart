// SS007 — SsPhotoRenderService 단위 테스트: 5단계를 순서대로 알려주는지, 삭제/재질/조명/개구부가 있어도
// 깨지지 않는지, 해석할 수 없는 이미지는 (네트워크 오류로 둔갑하지 않고) 예외를 그대로 던지는지 확인한다.
import 'dart:typed_data';

import 'package:ason_space/core/ss_render_step.dart';
import 'package:ason_space/models/ss_photo_scene.dart';
import 'package:ason_space/services/ss_photo_render_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _tinyImage() {
  final image = img.Image(width: 40, height: 30, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(200, 200, 200, 255));
  return img.encodePng(image);
}

void main() {
  test('5단계를 순서대로 알려주고 유효한 PNG 결과를 돌려준다', () async {
    const service = SsPhotoRenderService(stepDelay: Duration.zero);
    var scene = SsPhotoScene(imageBytes: _tinyImage());
    scene = scene.addObject(name: '소파', category: SsPhotoObjectCategory.furniture, x: 0.1, y: 0.1, width: 0.3, height: 0.3);
    scene = scene.setFinish(SsPhotoSurface.wall, swatchId: 'ivory', colorValue: 0xFFEFE7DA);
    scene = scene.setLighting(const SsPhotoLighting(presetId: 'warmCozy', label: '따뜻한 조명', warmth: 0.8, brightness: 0.6));

    final seen = <SsRenderStep>[];
    final bytes = await service.render(scene, onStep: seen.add);

    expect(seen, SsRenderStep.values);
    final decoded = img.decodeImage(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 40);
    expect(decoded.height, 30);
  });

  test('삭제한 객체·개구부가 있어도 깨지지 않는다', () async {
    const service = SsPhotoRenderService(stepDelay: Duration.zero);
    var scene = SsPhotoScene(imageBytes: _tinyImage());
    scene = scene.addObject(name: '의자', category: SsPhotoObjectCategory.furniture, x: 0.0, y: 0.0, width: 0.2, height: 0.2);
    scene = scene.updateObject(1, (o) => o.copyWith(removed: true));
    scene = scene.addOpening(SsPhotoOpeningKind.window, x: 0.5, y: 0.1, width: 0.2, height: 0.2);

    final bytes = await service.render(scene);
    expect(img.decodeImage(bytes), isNotNull);
  });

  test('해석할 수 없는 이미지는 예외를 던진다(원인을 감추지 않는다)', () async {
    const service = SsPhotoRenderService(stepDelay: Duration.zero);
    final scene = SsPhotoScene(imageBytes: Uint8List.fromList([1, 2, 3]));
    await expectLater(service.render(scene), throwsA(isA<FormatException>()));
  });
}
