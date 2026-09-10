/// SS CAD TEST — 다중 실측 기준 치수 보정.
///
/// 기존 "치수 보정"(단일 벽 3800mm)을 파괴하지 않고 확장한다: 사용자가
/// 벽 여러 개를 각각 실측해 입력하면, 각 벽마다 mmPerPixel 샘플이
/// 하나씩 생기고 그 중앙값(median)을 대표 축척으로 쓴다. 샘플이 1개뿐
/// 이면 그 값을 그대로 쓰므로 기존 단일 보정과 결과가 100% 동일하다.
///
/// GPT는 이 계산에 전혀 관여하지 않는다 — 모든 샘플은 사용자가 직접
/// 입력한 실측값에서만 나온다(WO "GPT가 임의로 scale을 결정해서는 안
/// 된다").
library;

/// 사용자가 벽 하나(또는 드래그 두 점)를 골라 실제 길이(mm)를 입력해
/// 만든 실측 기준 하나.
class ScaleReferenceSample {
  const ScaleReferenceSample({
    required this.wallId,
    required this.pixelLength,
    required this.measuredMm,
  }) : assert(pixelLength > 0, 'pixelLength must be positive'),
       assert(measuredMm > 0, 'measuredMm must be positive');

  /// 실제 [CadWall]을 찾아 측정했으면 그 id — 같은 벽을 다시 측정하면
  /// 이 값으로 이전 샘플을 갱신(교체)한다. 드래그 두 점 폴백이면 null —
  /// null 샘플은 항상 새 샘플로 추가된다(같은 벽인지 알 수 없으므로).
  final String? wallId;

  /// 측정 시점의 실제 픽셀 거리(정규화 좌표 × sourceWidthPx/HeightPx).
  final double pixelLength;

  /// 사용자가 입력한 실제 길이(mm).
  final double measuredMm;

  double get mmPerPixel => measuredMm / pixelLength;
}

/// 여러 [ScaleReferenceSample]로부터 계산한 대표 축척과 그 신뢰도 정보.
class ScaleCalibrationResult {
  const ScaleCalibrationResult({
    required this.mmPerPixel,
    required this.samples,
    required this.hasConflict,
    required this.maxDeviationRatio,
  });

  /// 대표 mmPerPixel(중앙값) — 샘플이 1개면 그 샘플의 값과 정확히 같다.
  final double mmPerPixel;

  final List<ScaleReferenceSample> samples;

  /// 샘플 중 하나라도 대표값과 [maxDeviationRatio]가 임계값을 넘게
  /// 벗어나면 true — 서로 다른 벽을 잘못 측정했거나 GPT geometry가
  /// 부정확할 수 있다는 신호. 자동으로 억지 통합하지 않고 그대로 노출한다.
  final bool hasConflict;

  /// 샘플들 중 대표값에서 가장 크게 벗어난 비율(0.08 = 8%).
  final double maxDeviationRatio;
}

/// 기본 허용 오차 — 실측 오차(줄자 눈금, GPT geometry 미세 오차 등)를
/// 감안한 값이다. 이 이상 벌어지면 "서로 다른 것을 잰 것 아닌가"로
/// 취급해 reviewNeeded 성격의 [ScaleCalibrationResult.hasConflict]를 켠다.
const double kScaleConflictThreshold = 0.08;

/// [samples]가 비어 있으면 안 된다(호출 전에 항상 최소 1개 확인).
/// 중앙값(median)을 쓴다 — 평균보다 이상치(잘못 잰 값 하나) 하나에
/// 덜 흔들린다.
ScaleCalibrationResult resolveScaleFromSamples(
  List<ScaleReferenceSample> samples, {
  double conflictThreshold = kScaleConflictThreshold,
}) {
  assert(samples.isNotEmpty, 'resolveScaleFromSamples requires >=1 sample');
  final values = samples.map((s) => s.mmPerPixel).toList()..sort();
  final n = values.length;
  final median = n.isOdd
      ? values[n ~/ 2]
      : (values[n ~/ 2 - 1] + values[n ~/ 2]) / 2;

  var maxDeviation = 0.0;
  for (final v in values) {
    final deviation = (v - median).abs() / median;
    if (deviation > maxDeviation) maxDeviation = deviation;
  }

  return ScaleCalibrationResult(
    mmPerPixel: median,
    samples: samples,
    hasConflict: maxDeviation > conflictThreshold,
    maxDeviationRatio: maxDeviation,
  );
}
