/// SS010 — MASTER UI 7(평면도 CAD변환) 진행 상태. [SsAiTask]를 그대로 재사용해 실패·재시도·
/// lastGoodResult 보존(ss_ai_task.dart §8)을 다시 구현하지 않고, CAD 변환 화면에만 필요한 "지금
/// 단계/완료한 단계/진행률"을 더한다([SsImageRenderController]와 같은 패턴, SS007). 확정된 입력
/// 데이터는 이 컨트롤러가 갖지 않는다 — 실패해도 화면이 들고 있는 원본 프로젝트 데이터를 그대로 두면
/// 되므로(§ 실패/중단/재시도 시 입력 데이터 보존).
library;

import 'package:flutter/foundation.dart';

import '../models/cad_conversion_result.dart';
import 'ss_ai_task.dart';
import 'ss_cad_conversion_step.dart';

class SsCadConversionController extends ChangeNotifier {
  SsCadConversionController() : task = SsAiTask<CadConversionResult>(name: 'CAD 변환') {
    task.addListener(notifyListeners);
  }

  final SsAiTask<CadConversionResult> task;

  SsCadConversionStep? _currentStep;
  SsCadConversionStep? get currentStep => _currentStep;

  final List<SsCadConversionStep> _completedSteps = [];
  List<SsCadConversionStep> get completedSteps => List.unmodifiable(_completedSteps);

  /// 0.0~1.0 — 5단계 기준. 완료 상태면 항상 1.0(화면 전환 전 깜빡임 방지).
  double get progress {
    if (task.status == SsAiStatus.completed) return 1.0;
    final total = SsCadConversionStep.values.length;
    final partial = (_currentStep != null && !_completedSteps.contains(_currentStep)) ? 0.5 : 0.0;
    return ((_completedSteps.length + partial) / total).clamp(0.0, 1.0);
  }

  void _onStepStarted(SsCadConversionStep step) {
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
  Future<SsAiStatus> start(Future<CadConversionResult> Function(void Function(SsCadConversionStep step) onStep) convertCall) {
    _resetSteps();
    return task.run(() => _attempt(convertCall));
  }

  /// 실패/중단 뒤 다시 시도 — 처음 [start]에 준 호출을 그대로 다시 쓴다([SsAiTask]가 시도 횟수를
  /// 센다, maxAttempts를 넘으면 더 시도할 수 없다). 입력 자체가 문제(inputFixNeeded)인 경우는
  /// [SsAiStatus.canRetry]가 false라 이 메서드가 아무것도 하지 않는다 — 사용자는 이전 단계로 돌아가
  /// 입력을 고쳐야 한다.
  Future<SsAiStatus> retry() {
    if (!task.canRetry) return Future.value(task.status);
    _resetSteps();
    notifyListeners();
    return task.retry();
  }

  Future<SsAiOutcome<CadConversionResult>> _attempt(
    Future<CadConversionResult> Function(void Function(SsCadConversionStep step) onStep) convertCall,
  ) async {
    try {
      final result = await convertCall(_onStepStarted);
      _currentStep = null;
      _completedSteps
        ..clear()
        ..addAll(SsCadConversionStep.values);
      return SsAiOutcome.completed(result);
    } on CadConversionInputError catch (e) {
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
