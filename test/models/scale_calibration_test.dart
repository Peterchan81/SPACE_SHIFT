// SS CAD TEST — 다중 실측 기준 축척([resolveScaleFromSamples]) 단위 테스트.
// 이 모델은 uncommitted 상태로 이미 화면(FloorPlanWorkspaceScreen)과 DXF
// export 경로에 배선되어 있었지만 그 자체를 독립적으로 검증하는 테스트가
// 없었다 — 여기서 median/충돌 감지 규칙을 직접 확인한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/scale_calibration.dart';

void main() {
  test('샘플이 1개면 그 값을 그대로 쓴다(기존 단일 보정과 동일)', () {
    final result = resolveScaleFromSamples([
      const ScaleReferenceSample(wallId: 'w1', pixelLength: 400, measuredMm: 3800),
    ]);
    expect(result.mmPerPixel, closeTo(9.5, 1e-9));
    expect(result.hasConflict, isFalse);
    expect(result.maxDeviationRatio, 0);
  });

  test('샘플이 홀수개면 정확한 중앙값을 쓴다', () {
    final result = resolveScaleFromSamples([
      const ScaleReferenceSample(wallId: 'w1', pixelLength: 100, measuredMm: 900), // 9.0
      const ScaleReferenceSample(wallId: 'w2', pixelLength: 100, measuredMm: 950), // 9.5
      const ScaleReferenceSample(wallId: 'w3', pixelLength: 100, measuredMm: 1000), // 10.0
    ]);
    expect(result.mmPerPixel, closeTo(9.5, 1e-9));
  });

  test('샘플이 짝수개면 가운데 두 값의 평균을 쓴다', () {
    final result = resolveScaleFromSamples([
      const ScaleReferenceSample(wallId: 'w1', pixelLength: 100, measuredMm: 900), // 9.0
      const ScaleReferenceSample(wallId: 'w2', pixelLength: 100, measuredMm: 1000), // 10.0
    ]);
    expect(result.mmPerPixel, closeTo(9.5, 1e-9));
  });

  test('서로 잘 맞는 여러 샘플은 충돌로 표시되지 않는다', () {
    final result = resolveScaleFromSamples([
      const ScaleReferenceSample(wallId: 'w1', pixelLength: 400, measuredMm: 3800), // 9.5
      const ScaleReferenceSample(wallId: 'w2', pixelLength: 320, measuredMm: 3040), // 9.5
    ]);
    expect(result.hasConflict, isFalse);
    expect(result.maxDeviationRatio, closeTo(0, 1e-9));
  });

  test('한 샘플이 대표값(중앙값)에서 임계값(8%) 넘게 벗어나면 충돌로 표시된다', () {
    // 3개 중 가운데 값(정확히 10.0)이 median이 되므로, 세 번째 샘플의
    // 편차를 손으로 정확히 계산할 수 있다: (11.0-10.0)/10.0 = 10%.
    final result = resolveScaleFromSamples([
      const ScaleReferenceSample(wallId: 'w1', pixelLength: 100, measuredMm: 1000), // 10.0
      const ScaleReferenceSample(wallId: 'w2', pixelLength: 100, measuredMm: 1000), // 10.0 (median)
      const ScaleReferenceSample(wallId: 'w3', pixelLength: 100, measuredMm: 1100), // 11.0 → +10%
    ]);
    expect(result.mmPerPixel, closeTo(10.0, 1e-9));
    expect(result.hasConflict, isTrue);
    expect(result.maxDeviationRatio, closeTo(0.10, 1e-9));
  });

  test('편차가 임계값 바로 아래(7%)면 충돌로 표시되지 않는다', () {
    final result = resolveScaleFromSamples([
      const ScaleReferenceSample(wallId: 'w1', pixelLength: 100, measuredMm: 1000), // 10.0
      const ScaleReferenceSample(wallId: 'w2', pixelLength: 100, measuredMm: 1000), // 10.0 (median)
      const ScaleReferenceSample(wallId: 'w3', pixelLength: 100, measuredMm: 1070), // 10.7 → +7%
    ]);
    expect(result.hasConflict, isFalse);
    expect(result.maxDeviationRatio, closeTo(0.07, 1e-9));
  });

  test('conflictThreshold를 직접 지정하면 그 값을 기준으로 판정한다', () {
    final result = resolveScaleFromSamples(
      [
        const ScaleReferenceSample(wallId: 'w1', pixelLength: 100, measuredMm: 1000), // 10.0
        const ScaleReferenceSample(wallId: 'w2', pixelLength: 100, measuredMm: 1000), // 10.0 (median)
        const ScaleReferenceSample(wallId: 'w3', pixelLength: 100, measuredMm: 1030), // 10.3 → +3%
      ],
      conflictThreshold: 0.02,
    );
    expect(result.hasConflict, isTrue);
  });

  test('mmPerPixel은 항상 양수(assert)를 요구한다 — 0 이하 길이는 만들 수 없다', () {
    expect(
      () => ScaleReferenceSample(wallId: 'w1', pixelLength: 0, measuredMm: 100),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => ScaleReferenceSample(wallId: 'w1', pixelLength: 100, measuredMm: 0),
      throwsA(isA<AssertionError>()),
    );
  });
}
