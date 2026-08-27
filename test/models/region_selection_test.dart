// RegionSelection 모델에 대한 단위 테스트.
//
// 1. 생성자로 전달한 정규화 좌표가 그대로 저장되는지 확인한다.
// 2. 백분율 getter가 올바르게 반올림되는지 확인한다.
// 3. copyWith이 지정한 필드만 바꾸는지 확인한다.
// 4. ==/hashCode, toMap이 올바르게 동작하는지 확인한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/region_selection.dart';

void main() {
  test('생성자로 전달한 정규화 좌표가 그대로 저장된다', () {
    const selection = RegionSelection(x: 0.1, y: 0.2, width: 0.3, height: 0.4);

    expect(selection.x, 0.1);
    expect(selection.y, 0.2);
    expect(selection.width, 0.3);
    expect(selection.height, 0.4);
  });

  test('백분율 getter는 화면 크기에 관계없이 정규화 값을 반올림한 값을 반환한다', () {
    const selection = RegionSelection(x: 0.125, y: 0.5, width: 0.333, height: 0.667);

    expect(selection.xPercent, 13);
    expect(selection.yPercent, 50);
    expect(selection.widthPercent, 33);
    expect(selection.heightPercent, 67);
  });

  test('copyWith은 지정한 필드만 바꾸고 나머지는 유지한다', () {
    const original = RegionSelection(x: 0.1, y: 0.2, width: 0.3, height: 0.4);

    final updated = original.copyWith(width: 0.5);

    expect(updated.width, 0.5);
    expect(updated.x, original.x);
    expect(updated.y, original.y);
    expect(updated.height, original.height);
  });

  test('같은 값을 가진 두 선택 영역은 ==와 hashCode가 동일하다', () {
    const a = RegionSelection(x: 0.1, y: 0.2, width: 0.3, height: 0.4);
    const b = RegionSelection(x: 0.1, y: 0.2, width: 0.3, height: 0.4);

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('toMap은 화면 크기와 무관한 순수 정규화 좌표 데이터를 반환한다', () {
    const selection = RegionSelection(x: 0.1, y: 0.2, width: 0.3, height: 0.4);

    expect(selection.toMap(), {
      'x': 0.1,
      'y': 0.2,
      'width': 0.3,
      'height': 0.4,
    });
  });
}
