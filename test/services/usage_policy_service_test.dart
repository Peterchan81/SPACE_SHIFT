// UsagePolicyService(하루 무료 3회 정책)에 대한 단위 테스트.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/services/usage_policy_service.dart';

void main() {
  setUp(() {
    UsagePolicyService.instance.resetForTesting();
  });

  test('초기 상태에서는 3회 모두 사용 가능하다', () {
    final service = UsagePolicyService.instance;

    expect(service.usedToday, 0);
    expect(service.remainingToday, 3);
    expect(service.canGenerate, isTrue);
  });

  test('recordGeneration을 호출할 때마다 사용 횟수가 늘어난다', () {
    final service = UsagePolicyService.instance;

    service.recordGeneration();
    expect(service.usedToday, 1);
    expect(service.remainingToday, 2);

    service.recordGeneration();
    service.recordGeneration();
    expect(service.usedToday, 3);
    expect(service.remainingToday, 0);
  });

  test('하루 한도(3회)를 모두 사용하면 canGenerate가 false가 된다', () {
    final service = UsagePolicyService.instance;

    for (var i = 0; i < UsagePolicyService.freeDailyLimit; i++) {
      expect(service.canGenerate, isTrue);
      service.recordGeneration();
    }

    expect(service.canGenerate, isFalse);
    expect(service.remainingToday, 0);
  });

  test('한도를 초과해 기록해도 remainingToday는 0 밑으로 내려가지 않는다', () {
    final service = UsagePolicyService.instance;

    for (var i = 0; i < UsagePolicyService.freeDailyLimit + 2; i++) {
      service.recordGeneration();
    }

    expect(service.remainingToday, 0);
  });
}
