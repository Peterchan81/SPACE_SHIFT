import 'package:flutter/foundation.dart';

/// 하루 무료 이용 정책(현재 V1 기준 하루 3회)을 관리하는 서비스.
///
/// 결제 금액이 아직 확정되지 않았으므로 이 클래스는 "무료 횟수를 세고,
/// 다 썼는지 판단하는" 정책 구조만 담당한다. 실제 결제/과금 로직은
/// 별도 서비스로 확장할 수 있도록 이 클래스와 분리해 둔다.
///
/// 현재는 앱 실행 중에만 유지되는 메모리 카운터다. 기기 재시작 후에도
/// 유지되어야 한다면 추후 로컬 저장소(예: shared_preferences)를 붙여
/// [usedToday]/[recordGeneration] 내부 구현만 교체하면 된다.
class UsagePolicyService {
  UsagePolicyService._();

  static final UsagePolicyService instance = UsagePolicyService._();

  /// 하루에 무료로 제공하는 생성/수정 횟수.
  static const int freeDailyLimit = 3;

  DateTime _day = _today();
  int _usedToday = 0;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _rolloverIfNeeded() {
    final today = _today();
    if (today != _day) {
      _day = today;
      _usedToday = 0;
    }
  }

  /// 오늘 이미 사용한 무료 생성/수정 횟수.
  int get usedToday {
    _rolloverIfNeeded();
    return _usedToday;
  }

  /// 오늘 남은 무료 생성/수정 횟수 (0 미만으로 내려가지 않음).
  int get remainingToday {
    final remaining = freeDailyLimit - usedToday;
    return remaining < 0 ? 0 : remaining;
  }

  /// 오늘 무료로 생성/수정을 한 번 더 진행할 수 있는지 여부.
  bool get canGenerate {
    _rolloverIfNeeded();
    return _usedToday < freeDailyLimit;
  }

  /// 실제로 AI 생성/수정 요청을 보내기 직전에 호출해 오늘 사용 횟수를 1 늘린다.
  void recordGeneration() {
    _rolloverIfNeeded();
    _usedToday++;
  }

  /// 테스트 전용: 내부 카운터를 초기 상태로 되돌린다.
  @visibleForTesting
  void resetForTesting() {
    _usedToday = 0;
    _day = _today();
  }
}
