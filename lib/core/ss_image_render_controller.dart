/// SS007 — MASTER UI 4-2-1(이미지 AI 렌더링) 진행 상태. [SsAiTask]를 그대로 재사용해 실패·재시도·
/// lastGoodResult 보존(ss_ai_task.dart §8)을 다시 구현하지 않고, 렌더링 화면에만 필요한 "지금
/// 단계/완료한 단계/진행률"을 더한다. 편집 지시([SsPhotoScene])는 이 컨트롤러가 갖지 않는다 — 실패해도
/// 화면이 들고 있는 원본 프로젝트 데이터를 그대로 두면 되므로(§ 실패/중단/재시도 시 편집 데이터 보존).
library;


import 'package:flutter/foundation.dart';

import 'ss_ai_task.dart';
import 'ss_render_step.dart';

class SsImageRenderController extends ChangeNotifier {
  SsImageRenderController() : task = SsAiTask<Uint8List>(name: '이미지 렌더링') {
    task.addListener(notifyListeners);
  }

  final SsAiTask<Uint8List> task;

  SsRenderStep? _currentStep;
  SsRenderStep? get currentStep => _currentStep;

  final List<SsRenderStep> _completedSteps = [];
  List<SsRenderStep> get completedSteps => List.unmodifiable(_completedSteps);

  /// 0.0~1.0 — § 렌더링 단계 예시 5단계 기준. 완료 상태면 항상 1.0(화면 전환 전 깜빡임 방지).
  double get progress {
    if (task.status == SsAiStatus.completed) return 1.0;
    final total = SsRenderStep.values.length;
    final partial = (_currentStep != null && !_completedSteps.contains(_currentStep)) ? 0.5 : 0.0;
    return ((_completedSteps.length + partial) / total).clamp(0.0, 1.0);
  }

  void _onStepStarted(SsRenderStep step) {
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

  /// 처음 실행 — [renderCall]은 단계가 바뀔 때마다 onStep을 순서대로 불러야 한다.
  Future<SsAiStatus> start(Future<Uint8List> Function(void Function(SsRenderStep step) onStep) renderCall) {
    _resetSteps();
    return task.run(() => _attempt(renderCall));
  }

  /// 실패/중단 뒤 다시 시도 — 처음 [start]에 준 호출을 그대로 다시 쓴다
  /// ([SsAiTask]가 시도 횟수를 센다, maxAttempts를 넘으면 더 시도할 수 없다).
  Future<SsAiStatus> retry() {
    if (!task.canRetry) return Future.value(task.status);
    _resetSteps();
    notifyListeners();
    return task.retry();
  }

  Future<SsAiOutcome<Uint8List>> _attempt(Future<Uint8List> Function(void Function(SsRenderStep step) onStep) renderCall) async {
    final bytes = await renderCall(_onStepStarted);
    _currentStep = null;
    _completedSteps
      ..clear()
      ..addAll(SsRenderStep.values);
    return SsAiOutcome.completed(bytes);
  }

  @override
  void dispose() {
    task.removeListener(notifyListeners);
    task.dispose();
    super.dispose();
  }
}
