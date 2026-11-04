/// SS012 — MASTER UI 9(3D 아이소 변환) 진행 상태. [SsAiTask]를 그대로 재사용해 실패·재시도·
/// lastGoodResult 보존(ss_ai_task.dart §8)을 다시 구현하지 않고([SsCadConversionController]와 같은
/// 패턴, SS010), 3D ISO 변환 화면에만 필요한 "지금 단계/완료한 단계/진행률"을 더한다. 확정된 CAD
/// 입력 데이터는 이 컨트롤러가 갖지 않는다 — 실패해도 화면이 들고 있는 원본 CAD 데이터를 그대로 두면
/// 되므로(§ 실패/중단/재시도 시 입력 데이터 보존).
library;

import 'package:flutter/foundation.dart';

import '../models/iso_conversion_result.dart';
import 'ss_ai_task.dart';
import 'ss_iso_conversion_step.dart';

class SsIsoConversionController extends ChangeNotifier {
  SsIsoConversionController() : task = SsAiTask<IsoConversionResult>(name: '3D ISO 변환') {
    task.addListener(notifyListeners);
  }

  final SsAiTask<IsoConversionResult> task;

  SsIsoConversionStep? _currentStep;
  SsIsoConversionStep? get currentStep => _currentStep;

  final List<SsIsoConversionStep> _completedSteps = [];
  List<SsIsoConversionStep> get completedSteps => List.unmodifiable(_completedSteps);

  /// 0.0~1.0 — 5단계 기준. 완료 상태면 항상 1.0(화면 전환 전 깜빡임 방지).
  double get progress {
    if (task.status == SsAiStatus.completed) return 1.0;
    final total = SsIsoConversionStep.values.length;
    final partial = (_currentStep != null && !_completedSteps.contains(_currentStep)) ? 0.5 : 0.0;
    return ((_completedSteps.length + partial) / total).clamp(0.0, 1.0);
  }

  void _onStepStarted(SsIsoConversionStep step) {
    if (_currentStep != null && !_completedSteps.contains(_currentStep)) {
      _completedSteps.add(_currentStep!);
    }
    _currentStep = step;
    notifyListeners();
  }

  void _resetSteps() {
    _currentStep = null;
    _completedSteps.clear();
  }

  /// 처음 실행 — [convertCall]은 단계가 바뀔 때마다 onStep을 순서대로 불러야 한다.
  Future<SsAiStatus> start(Future<IsoConversionResult> Function(void Function(SsIsoConversionStep step) onStep) convertCall) {
    _resetSteps();
    return task.run(() => _attempt(convertCall));
  }

  /// 실패/중단 뒤 다시 시도 — 처음 [start]에 준 호출을 그대로 다시 쓴다([SsAiTask]가 시도 횟수를
  /// 센다, maxAttempts를 넘으면 더 시도할 수 없다). 입력 자체가 문제(inputFixNeeded)인 경우는
  /// [SsAiStatus.canRetry]가 false라 이 메서드가 아무것도 하지 않는다 — 사용자는 CAD 편집 화면으로
  /// 돌아가 입력을 고쳐야 한다.
  Future<SsAiStatus> retry() {
    if (!task.canRetry) return Future.value(task.status);
    _resetSteps();
    notifyListeners();
    return task.retry();
  }

  Future<SsAiOutcome<IsoConversionResult>> _attempt(
    Future<IsoConversionResult> Function(void Function(SsIsoConversionStep step) onStep) convertCall,
  ) async {
    try {
      final result = await convertCall(_onStepStarted);
      _currentStep = null;
      _completedSteps
        ..clear()
        ..addAll(SsIsoConversionStep.values);
      return SsAiOutcome.completed(result);
    } on IsoConversionInputError catch (e) {
      return SsAiOutcome.inputFixNeeded(e.message);
    }
  }

  @override
  void dispose() {
    task.removeListener(notifyListeners);
    task.dispose();
    super.dispose();
  }
}
