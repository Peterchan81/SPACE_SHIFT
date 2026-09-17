// SS CAD TEST — API 호출 정책(비용 감사) WO §8. runAdaptiveVisionConsolidation
// 이 실제로 "1회 기본 + 결과가 불충분할 때만 추가"로 동작하는지, 그리고
// billing 오류에서는 절대 재시도하지 않는지 LIVE OpenAI 호출 없이(가짜
// buildOnce 함수만으로) 검증한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/vision_consolidation.dart';
import 'package:ason_space/services/vision_interpretation_service.dart';

CadWall _wall(String id, {bool reviewNeeded = false}) => CadWall(
  id: id,
  start: Point2(0.1, 0.1),
  end: Point2(0.9, 0.1),
  thicknessNormalized: 0.01,
  wallType: CadWallType.exterior,
  confidence: 1.0,
  reviewNeeded: reviewNeeded,
);

CadFloorPlan _goodPlan() => CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [_wall('w1'), _wall('w2'), _wall('w3'), _wall('w4')],
  openings: const [],
  rooms: const [],
  warnings: const [],
);

CadFloorPlan _insufficientPlanEmptyWalls() => const CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [],
  openings: [],
  rooms: [],
  warnings: [],
);

CadFloorPlan _insufficientPlanFloorDomainInvalid() => CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [_wall('w1')],
  openings: const [],
  rooms: const [],
  warnings: const ['FloorDomain INVALID: 구조 벽이 서로 이어지지 않음'],
);

CadFloorPlan _insufficientPlanMostlyReviewNeeded() => CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [
    _wall('w1', reviewNeeded: true),
    _wall('w2', reviewNeeded: true),
    _wall('w3', reviewNeeded: true),
    _wall('w4'),
  ],
  openings: const [],
  rooms: const [],
  warnings: const [],
);

void main() {
  group('isVisionResultSufficient', () {
    test('벽이 있고 외곽이 닫혔고 reviewNeeded 비율이 낮으면 충분하다', () {
      expect(isVisionResultSufficient(_goodPlan()), isTrue);
    });

    test('벽이 하나도 없으면 불충분하다', () {
      expect(isVisionResultSufficient(_insufficientPlanEmptyWalls()), isFalse);
    });

    test('FloorDomain이 닫히지 않았으면 불충분하다', () {
      expect(isVisionResultSufficient(_insufficientPlanFloorDomainInvalid()), isFalse);
    });

    test('벽의 절반을 초과해 reviewNeeded면 불충분하다', () {
      expect(isVisionResultSufficient(_insufficientPlanMostlyReviewNeeded()), isFalse);
    });
  });

  group('runAdaptiveVisionConsolidation — 호출 횟수 정책', () {
    test('1) 정상 분석 -> OpenAI(mock) request 정확히 1회, 4) 추가 요청 없음', () async {
      var callCount = 0;
      final attempts = <int>[];
      final result = await runAdaptiveVisionConsolidation(
        Uint8List(0),
        buildOnce: (_) async {
          callCount++;
          return _goodPlan();
        },
        onAttempt: ({required attempt, required reason, outcome}) => attempts.add(attempt),
      );

      expect(callCount, 1, reason: '1번째 결과가 이미 충분히 좋으면 추가 유료 호출이 없어야 한다');
      expect(attempts, [1]);
      expect(result.walls, hasLength(4));
    });

    test('2) 결과 불충분 -> 조건부 2차 요청(그 2차가 충분하면 거기서 멈춘다)', () async {
      var callCount = 0;
      final result = await runAdaptiveVisionConsolidation(
        Uint8List(0),
        buildOnce: (_) async {
          callCount++;
          return callCount == 1 ? _insufficientPlanEmptyWalls() : _goodPlan();
        },
      );

      expect(callCount, 2, reason: '1차가 불충분했으니 2차까지는 시도해야 하고, 2차가 성공(추가된)이면 3차는 필요 없다');
      expect(result.walls, isNotEmpty);
    });

    test('3) 계속 불충분 -> 최대 허용 범위(3회)까지만 시도한다', () async {
      var callCount = 0;
      final result = await runAdaptiveVisionConsolidation(
        Uint8List(0),
        buildOnce: (_) async {
          callCount++;
          return _insufficientPlanEmptyWalls();
        },
      );

      expect(callCount, 3, reason: '계속 불충분해도 maxSamples(기본 3)를 넘겨 호출하지 않는다');
      // 3번 다 벽이 0개인 결과라도, consolidateCadFloorPlans는 최소 1개
      // 결과만 있으면 예외 없이 통합한다(빈 통합 결과) — 이 테스트는
      // "호출 횟수 상한"만 확인한다.
      expect(result, isNotNull);
    });

    test('5/6) insufficient_quota/credit_balance_exhausted(GptBillingExhaustedException) -> 1회 시도 후 즉시 중단, retry 0회', () async {
      var callCount = 0;
      await expectLater(
        runAdaptiveVisionConsolidation(
          Uint8List(0),
          buildOnce: (_) async {
            callCount++;
            throw const GptBillingExhaustedException();
          },
        ),
        throwsA(isA<GptBillingExhaustedException>()),
      );

      expect(callCount, 1, reason: 'billing 오류는 재시도하지 않는다 — 같은 요청을 2번째로 다시 보내면 안 된다');
    });

    test('7) 일시적 오류(billing이 아닌 일반 실패) -> 정책 범위(최대 3회) 안에서는 재시도한다', () async {
      var callCount = 0;
      final result = await runAdaptiveVisionConsolidation(
        Uint8List(0),
        buildOnce: (_) async {
          callCount++;
          if (callCount < 3) throw Exception('일시적 네트워크 오류');
          return _goodPlan();
        },
      );

      expect(callCount, 3);
      expect(result.walls, isNotEmpty);
    });

    test('모든 시도가 실패하면(billing이 아닌 일반 오류) 마지막 오류를 그대로 던진다', () async {
      await expectLater(
        runAdaptiveVisionConsolidation(
          Uint8List(0),
          buildOnce: (_) async => throw Exception('계속 실패'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('onAttempt 계측 콜백이 각 실제 요청마다 정확히 한 번씩 호출된다(성공/실패 사유 포함)', () async {
      final logs = <String>[];
      var callCount = 0;
      await runAdaptiveVisionConsolidation(
        Uint8List(0),
        buildOnce: (_) async {
          callCount++;
          if (callCount == 1) throw Exception('첫 시도 실패');
          return _goodPlan();
        },
        onAttempt: ({required attempt, required reason, outcome}) {
          logs.add('attempt=$attempt reason=$reason outcome=$outcome');
        },
      );

      expect(logs, [
        'attempt=1 reason=initial outcome=failed',
        'attempt=2 reason=low_confidence outcome=success',
      ]);
    });
  });
}
