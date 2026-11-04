/// SS015 — MASTER UI 11(3D 아이소 랜더링) 진행 상태. [SsAiTask]를 그대로 재사용해 실패·재시도·
/// lastGoodResult 보존(ss_ai_task.dart §8)을 다시 구현하지 않고([SsIsoConversionController]/
/// [SsImageRenderController]와 같은 패턴, SS012/SS007), 3D ISO 렌더링 화면에만 필요한 "지금
/// 단계/완료한 단계/진행률"을 더한다. 완성된 ISO 디자인(cadData/isoData)은 이 컨트롤러가 갖지 않는다
/// — 실패해도 화면이 들고 있는 원본 디자인 데이터를 그대로 두면 되므로(§완료조건 "실패 시 CAD/ISO
/// 디자인 데이터 보존").
///
/// [start]/[retry]는 이미 처리 중이면(§구현 범위 "중복 렌더링 요청 방지") 새 요청을 만들지 않고 지금
/// 상태를 그대로 돌려준다 — 실제 렌더 엔진/API를 쓸 때 같은 요청을 두 번 보내지 않기 위함(§구현 범위
/// "실제 렌더 엔진/API 사용 시 불필요한 중복 호출 방지").
library;

import 'package:flutter/foundation.dart';

import '../models/iso_render_result.dart';
import 'ss_ai_task.dart';
import 'ss_iso_render_step.dart';

class SsIsoRenderController extends ChangeNotifier {
  SsIsoRenderController() : task = SsAiTask<IsoRenderResult>(name: '3D ISO 렌더링') {
    task.addListener(notifyListeners);
  }

  final SsAiTask<IsoRenderResult> task;

  SsIsoRenderStep? _currentStep;
  SsIsoRenderStep? get currentStep => _currentStep;

  final List<SsIsoRenderStep> _completedSteps = [];
  List<SsIsoRenderStep> get completedSteps => List.unmodifiable(_completedSteps);

  /// 0.0~1.0 — 5단계 기준. 완료 상태면 항상 1.0(화면 전환 전 깜빡임 방지).
  double get progress {
    if (task.status == SsAiStatus.completed) return 1.0;
    final total = SsIsoRenderStep.values.length;
    final partial = (_currentStep != null && !_completedSteps.contains(_currentStep)) ? 0.5 : 0.0;
    return ((_completedSteps.length + partial) / total).clamp(0.0, 1.0);
  }

  void _onStepStarted(SsIsoRenderStep step) {
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

  /// 처음 실행 — [renderCall]은 단계가 바뀔 때마다 onStep을 순서대로 불러야 한다. 이미 처리 중이면
  /// 아무것도 하지 않고 지금 상태를 그대로 돌려준다(중복 렌더링 요청 방지).
  Future<SsAiStatus> start(Future<IsoRenderResult> Function(void Function(SsIsoRenderStep step) onStep) renderCall) {
    if (task.status == SsAiStatus.processing) return Future.value(task.status);
    _resetSteps();
    return task.run(() => _attempt(renderCall));
  }

  /// 실패/중단 뒤 다시 시도 — 처음 [start]에 준 호출을 그대로 다시 쓴다([SsAiTask]가 시도 횟수를
  /// 센다, maxAttempts를 넘으면 더 시도할 수 없다). 입력 자체가 문제(inputFixNeeded)인 경우는
  /// [SsAiStatus.canRetry]가 false라 이 메서드가 아무것도 하지 않는다 — 사용자는 3D 디자인 화면으로
  /// 돌아가 입력을 고쳐야 한다. 이미 처리 중인 요청이 있으면(중복 탭 등) 새 요청을 만들지 않는다.
  Future<SsAiStatus> retry() {
    if (!task.canRetry || task.status == SsAiStatus.processing) return Future.value(task.status);
    _resetSteps();
    notifyListeners();
    return task.retry();
  }

  Future<SsAiOutcome<IsoRenderResult>> _attempt(
    Future<IsoRenderResult> Function(void Function(SsIsoRenderStep step) onStep) renderCall,
  ) async {
    try {
      final result = await renderCall(_onStepStarted);
      _currentStep = null;
      _completedSteps
        ..clear()
        ..addAll(SsIsoRenderStep.values);
      return SsAiOutcome.completed(result);
    } on IsoRenderInputError catch (e) {
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
