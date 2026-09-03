// SPACE SHIFT — Vision Hint → Exact Wall SNAP 기술검증 단위 테스트.
//
// flutter test 통과만으로 PASS를 선언하지 않는다(사용자 지시) — 이
// 테스트는 "명백한 회귀가 없는지"만 확인하는 최소 안전망이고, 실제
// PASS/FAIL 판정은 Windows 화면 육안 확인으로 한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/single_wall_snap/single_wall_snap_detector.dart';
import 'package:ason_space/vision_cad_poc/single_wall_snap/single_wall_snap_fixture.dart';

void main() {
  const detector = SingleWallSnapDetector();
  const hint = SingleWallHint(
    xNormalized: kSnapVisionHintX,
    startYNormalized: kSnapVisionHintStartYNorm,
    endYNormalized: kSnapVisionHintEndYNorm,
  );

  test('부정확한 hint에서도 실제 벽 중심선을 찾는다 (hint x=0.61, 실제 x=0.575)', () {
    final image = buildSingleWallSnapImage();
    final result = detector.detect(image, hint);
    expect(result, isNotNull);
    expect(result!.centerX, closeTo(kSnapRealWallCenterX, 2));
    // hint의 x(488px)보다 실제 벽 중심(460px)에 훨씬 가까워야 한다.
    expect((result.centerX - kSnapRealWallCenterX).abs(), lessThan((result.centerX - hint.xNormalized * kSnapImageWidth).abs()));
  });

  test('좌우 edge가 실제 벽 두께(10px)와 일치한다', () {
    final image = buildSingleWallSnapImage();
    final result = detector.detect(image, hint);
    expect(result, isNotNull);
    expect(result!.leftEdgeX, closeTo(kSnapRealWallLeftEdgeX, 2));
    expect(result.rightEdgeX, closeTo(kSnapRealWallRightEdgeX, 2));
    expect(result.thicknessPx, closeTo(kSnapRealWallThicknessPx, 3));
  });

  test('시작/끝점이 hint 범위 밖의 실제 junction으로 확장되어 찾아진다', () {
    final image = buildSingleWallSnapImage();
    final result = detector.detect(image, hint);
    expect(result, isNotNull);
    // hint의 시작 y(234px)보다 실제 상단 junction(200px)에 더 가까워야 한다.
    expect(result!.startY, closeTo(kSnapRealWallTopJunctionY, 5));
    expect(result.endY, closeTo(kSnapRealWallBottomJunctionY, 5));
    expect(result.startJunctionConfirmed, isTrue);
    expect(result.endJunctionConfirmed, isTrue);
  });

  test('confidence는 HIGH다 (양쪽 junction이 모두 확인됨)', () {
    final image = buildSingleWallSnapImage();
    final result = detector.detect(image, hint);
    expect(result, isNotNull);
    expect(result!.confidence, 'HIGH');
  });

  test('가구/텍스트 잡음에 끌려가지 않는다 — 검출된 벽이 잡음 위치와 다르다', () {
    final image = buildSingleWallSnapImage();
    final result = detector.detect(image, hint);
    expect(result, isNotNull);
    // 잡음(가구 x=410~452, 텍스트 x=475~512 부근)이 아니라 실제 벽
    // (x=455~465) 위치가 나와야 한다.
    expect(result!.leftEdgeX, greaterThan(452));
    expect(result.rightEdgeX, lessThan(475));
  });

  test('search window는 hint 기준 수평 ±5%, 수직은 hint 범위+마진으로 제한된다', () {
    final image = buildSingleWallSnapImage();
    final result = detector.detect(image, hint);
    expect(result, isNotNull);
    final window = result!.searchWindow;
    expect(window.left, greaterThanOrEqualTo(hint.xNormalized * kSnapImageWidth - kSnapImageWidth * 0.05 - 1));
    expect(window.right, lessThanOrEqualTo(hint.xNormalized * kSnapImageWidth + kSnapImageWidth * 0.05 + 1));
  });
}
