/// SS001 §8 — AI 작업(공간 인식, CAD 변환, 렌더링 등)의 공통 상태와 재시도.
///
/// AI가 늘 정상 결과를 낸다고 가정하지 않는다. 실패·부분 완료·사용자 확인 필요를 같은 방식으로 다루고,
/// 실패해도 직전 결과([lastGoodResult])는 그대로 둔다 — 사용자가 이전 작업을 잃지 않게.
library;

import 'package:flutter/foundation.dart';

enum SsAiStatus {
  idle('대기'),
  processing('처리 중'),
  completed('완료'),
  partial('부분 완료'),
  needsUserCheck('사용자 확인 필요'),
  failed('실패'),
  retryable('다시 시도 가능'),
  inputFixNeeded('입력 수정 필요');

  const SsAiStatus(this.label);
  final String label;

  bool get isTerminal => this == completed || this == partial || this == needsUserCheck || this == failed || this == retryable || this == inputFixNeeded;
  bool get canRetry => this == retryable || this == failed || this == partial;
}

/// AI 호출 하나의 결과를 공통 상태로 옮기는 값.
@immutable
class SsAiOutcome<R> {
  const SsAiOutcome._(this.status, this.result, this.message);
  const SsAiOutcome.completed(R result) : this._(SsAiStatus.completed, result, null);
  const SsAiOutcome.partial(R result, String message) : this._(SsAiStatus.partial, result, message);
  const SsAiOutcome.needsUserCheck(R result, String message) : this._(SsAiStatus.needsUserCheck, result, message);
  const SsAiOutcome.retryable(String message) : this._(SsAiStatus.retryable, null, message);
  const SsAiOutcome.inputFixNeeded(String message) : this._(SsAiStatus.inputFixNeeded, null, message);
  const SsAiOutcome.failed(String message) : this._(SsAiStatus.failed, null, message);

  final SsAiStatus status;
  final R? result;
  final String? message;
}

/// AI 작업 상태 — 화면은 [status]/[message]/[canRetry]를 보여 주고, [run]/[retry]로 실행한다.
class SsAiTask<R> extends ChangeNotifier {
  SsAiTask({required this.name, this.maxAttempts = 3, R? previousResult}) : _lastGood = previousResult;

  final String name;
  final int maxAttempts;
  SsAiStatus _status = SsAiStatus.idle;
  SsAiStatus get status => _status;
  String? _message;
  String? get message => _message;
  int _attempts = 0;
  int get attempts => _attempts;
  R? _lastGood;

  /// 마지막으로 쓸 수 있었던 결과(완료/부분/확인 필요) — 실패해도 지워지지 않는다.
  R? get lastGoodResult => _lastGood;
  Future<SsAiOutcome<R>> Function()? _last;

  bool get canRetry => _status.canRetry && _attempts < maxAttempts && _last != null;

  Future<SsAiStatus> run(Future<SsAiOutcome<R>> Function() call) {
    _attempts = 0;
    _last = call;
    return _attempt();
  }

  Future<SsAiStatus> retry() {
    if (!canRetry) return Future.value(_status);
    return _attempt();
  }

  Future<SsAiStatus> _attempt() async {
    _attempts++;
    _status = SsAiStatus.processing;
    _message = null;
    notifyListeners();
    SsAiOutcome<R> o;
    try {
      o = await _last!();
    } catch (e) {
      o = SsAiOutcome.retryable('$name 중 오류가 났습니다. 다시 시도할 수 있습니다.');
    }
    if (o.result != null) _lastGood = o.result;
    _status = (o.status == SsAiStatus.retryable && _attempts >= maxAttempts) ? SsAiStatus.failed : o.status;
    _message = o.message;
    notifyListeners();
    return _status;
  }
}
