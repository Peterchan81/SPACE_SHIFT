/// SS001 §7 — 평면도·이미지 디자인·CAD·ISO 편집이 함께 쓰는 작업 이력(Undo/Redo/History/마지막 정상 상태 복원).
///
/// 흐름: 원본 → AI 결과 → 사용자 수정 1 → 2 → … → 최종 결과.
/// - 상태는 바꾸지 않는(불변) 값으로 다룬다 — 이전 상태를 복사하지 않고 참조만 보관해 큰 데이터도 가볍다(§7 성능).
/// - [capacity]를 넘으면 가장 오래된 것부터 버리되, 처음 원본은 항상 남긴다.
/// - "정상"으로 표시한 마지막 지점으로 한 번에 돌아갈 수 있다(AI/저장 실패 뒤 복원).
/// - 기존 CAD 편집기(floor_plan_workspace_screen의 _mutateCad undo 스택)는 그대로 둔다. CAD Work Order에서 이 기반으로 옮긴다.
library;

import 'package:flutter/foundation.dart';

/// 이력 한 칸의 종류.
enum SsHistoryKind {
  original('원본'),
  aiResult('AI 결과'),
  userEdit('사용자 수정'),
  finalResult('최종 결과');

  const SsHistoryKind(this.label);
  final String label;
}

@immutable
class SsHistoryStep<T> {
  const SsHistoryStep({required this.state, required this.kind, required this.label, this.good = true});
  final T state;
  final SsHistoryKind kind;
  final String label;

  /// 검증을 통과한 정상 상태인가(복원 지점).
  final bool good;
}

class SsHistory<T> extends ChangeNotifier {
  SsHistory({required T original, String label = '원본', this.capacity = 100}) : _steps = [SsHistoryStep(state: original, kind: SsHistoryKind.original, label: label)];

  final int capacity;
  final List<SsHistoryStep<T>> _steps;
  int _index = 0;

  T get current => _steps[_index].state;
  SsHistoryStep<T> get currentStep => _steps[_index];
  List<SsHistoryStep<T>> get steps => List.unmodifiable(_steps);
  int get index => _index;
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _steps.length - 1;

  /// 새 상태를 쌓는다. 되돌린 뒤 새로 고치면 그 뒤(redo 쪽)는 버린다.
  void push(T state, {SsHistoryKind kind = SsHistoryKind.userEdit, String? label, bool good = true}) {
    if (canRedo) _steps.removeRange(_index + 1, _steps.length);
    final n = _steps.where((s) => s.kind == SsHistoryKind.userEdit).length + 1;
    _steps.add(SsHistoryStep(state: state, kind: kind, label: label ?? (kind == SsHistoryKind.userEdit ? '사용자 수정 $n' : kind.label), good: good));
    while (_steps.length > capacity && _steps.length > 2) {
      _steps.removeAt(1); // 원본(0번)은 남긴다
    }
    _index = _steps.length - 1;
    notifyListeners();
  }

  T undo() {
    if (canUndo) {
      _index--;
      notifyListeners();
    }
    return current;
  }

  T redo() {
    if (canRedo) {
      _index++;
      notifyListeners();
    }
    return current;
  }

  /// 지금보다 앞쪽에서 가장 가까운 정상 상태로 돌아간다(없으면 원본).
  T restoreLastGood() {
    var i = _index;
    while (i > 0 && !_steps[i].good) {
      i--;
    }
    _index = i;
    notifyListeners();
    return current;
  }

  /// 원하는 이력 지점으로 바로 간다(History 목록에서 고를 때).
  T jumpTo(int i) {
    if (i < 0 || i >= _steps.length) throw RangeError.index(i, _steps);
    _index = i;
    notifyListeners();
    return current;
  }
}
