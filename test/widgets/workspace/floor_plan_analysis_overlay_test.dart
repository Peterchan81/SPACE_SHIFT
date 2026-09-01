// ContainFitTransform(BoxFit.contain letterbox 계산)에 대한 단위 테스트.
//
// FloorPlanPreview의 Image.memory(fit: BoxFit.contain)와 오버레이가 같은
// 좌표계를 쓰려면, 이 계산이 실제 BoxFit.contain 동작과 정확히 일치해야
// 한다(WO 6번).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/widgets/workspace/floor_plan_analysis_overlay.dart';

void main() {
  test('컨테이너보다 가로로 넓은 이미지는 위아래 letterbox가 생긴다', () {
    // 이미지 비율 2:1, 컨테이너 비율 1:1 → 너비를 꽉 채우고 위아래 여백.
    final transform = ContainFitTransform.compute(
      const Size(400, 400),
      const Size(800, 400),
    );

    expect(transform.rect.width, 400);
    expect(transform.rect.height, 200);
    expect(transform.rect.left, 0);
    expect(transform.rect.top, 100);
  });

  test('컨테이너보다 세로로 긴 이미지는 좌우 letterbox가 생긴다', () {
    // 이미지 비율 1:2, 컨테이너 비율 1:1 → 높이를 꽉 채우고 좌우 여백.
    final transform = ContainFitTransform.compute(
      const Size(400, 400),
      const Size(200, 400),
    );

    expect(transform.rect.height, 400);
    expect(transform.rect.width, 200);
    expect(transform.rect.top, 0);
    expect(transform.rect.left, 100);
  });

  test('정규화 좌표를 화면 좌표로 매핑하면 letterbox 오프셋이 반영된다', () {
    final transform = ContainFitTransform.compute(
      const Size(400, 400),
      const Size(800, 400),
    );

    final topLeft = transform.mapNormalized(const Point2(0, 0));
    final bottomRight = transform.mapNormalized(const Point2(1, 1));
    final center = transform.mapNormalized(const Point2(0.5, 0.5));

    expect(topLeft, const Offset(0, 100));
    expect(bottomRight, const Offset(400, 300));
    expect(center, const Offset(200, 200));
  });

  test('화면 좌표 → 정규화 좌표 역변환은 mapNormalized의 역함수다', () {
    final transform = ContainFitTransform.compute(
      const Size(400, 400),
      const Size(800, 400),
    );

    const original = Point2(0.3, 0.7);
    final screen = transform.mapNormalized(original);
    final back = transform.inverse(screen);

    expect(back, isNotNull);
    expect(back!.x, closeTo(original.x, 0.0001));
    expect(back.y, closeTo(original.y, 0.0001));
  });

  test('letterbox 여백(이미지 바깥) 좌표는 역변환에서 null을 반환한다', () {
    final transform = ContainFitTransform.compute(
      const Size(400, 400),
      const Size(800, 400),
    );

    // top=100이므로 y=10은 위쪽 여백 안이다.
    final result = transform.inverse(const Offset(200, 10));
    expect(result, isNull);
  });
}
