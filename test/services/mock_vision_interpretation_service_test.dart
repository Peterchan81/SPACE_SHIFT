// Vision Guided CAD POC — MockVisionInterpretationService 단위 테스트.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/vision_understanding.dart';
import 'package:ason_space/services/mock_vision_interpretation_service.dart';
import 'package:ason_space/vision_cad_poc/sample_image2_fixture.dart';

void main() {
  const service = MockVisionInterpretationService();

  test('이미지 2의 13개 공간을 모두 포함한다', () async {
    final understanding = await service.interpret(buildImage2Png());
    expect(understanding.spaces, hasLength(image2Rooms.length));
    for (final key in image2Rooms.keys) {
      expect(understanding.spaces.any((s) => s.id == 'space-$key'), isTrue, reason: key);
    }
  });

  test('scaleConfirmed는 항상 false다 (인쇄된 치수 없음)', () async {
    final understanding = await service.interpret(buildImage2Png());
    expect(understanding.scaleConfirmed, isFalse);
  });

  test('모든 hint 좌표는 실제 픽셀 좌표에서 의도적으로 어긋나 있다', () async {
    final understanding = await service.interpret(buildImage2Png());
    final masterBedroom = understanding.spaces.firstWhere((s) => s.id == 'space-masterBedroom');
    final box = masterBedroom.geometryHint!.boundingBox!;
    final realBox = image2Rooms['masterBedroom']!;
    // 정확히 일치하면 안 된다 — hint일 뿐 최종 CAD 좌표가 아니다.
    expect(box.minX * kImage2Width, isNot(closeTo(realBox.left, 0.001)));
  });

  test('실제로 그려지지 않은 가구 hint를 하나 포함한다(CASE E 시연용)', () async {
    final understanding = await service.interpret(buildImage2Png());
    expect(understanding.objects, isNotEmpty);
    expect(understanding.objects.first.objectType, VisionObjectType.bed);
  });

  test('실제로는 문이 없는 위치에 잘못된 door hint를 하나 포함한다(CASE D 시연용)', () async {
    final understanding = await service.interpret(buildImage2Png());
    expect(
      understanding.openings.any((o) => o.id == 'opening-dressRoom-masterLiving-door'),
      isTrue,
    );
  });

  test('모든 entity는 유효한 정규화 좌표를 갖는다', () async {
    final understanding = await service.interpret(buildImage2Png());
    for (final b in understanding.boundaries) {
      expect(b.geometryHint!.start.isPlausible, isTrue);
      expect(b.geometryHint!.end.isPlausible, isTrue);
    }
    for (final s in understanding.spaces) {
      final box = s.geometryHint!.boundingBox!;
      expect(NormalizedPoint(box.minX, box.minY).isPlausible, isTrue);
      expect(NormalizedPoint(box.maxX, box.maxY).isPlausible, isTrue);
    }
  });
}
