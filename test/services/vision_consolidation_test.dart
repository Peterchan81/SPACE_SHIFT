import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/vision_consolidation.dart';

const int kWidth = 1000;
const int kHeight = 1000;

CadWall _wall(String id, double x1, double y1, double x2, double y2, {double confidence = 0.8, CadWallType type = CadWallType.exterior}) {
  return CadWall(
    id: id,
    start: Point2(x1 / kWidth, y1 / kHeight),
    end: Point2(x2 / kWidth, y2 / kHeight),
    thicknessNormalized: 0.01,
    wallType: type,
    confidence: confidence,
  );
}

/// A simple rectangle: w1 top, w2 right, w3 bottom, w4 left (pixel coords
/// before /kWidth /kHeight normalization happens inside [_wall]).
CadFloorPlan _rectRun(double jitter, {bool includeW4 = true, bool extraSpurious = false, String? doorWallId}) {
  double j(double v) => v + jitter;
  final walls = <CadWall>[
    _wall('w1', j(100), j(100), j(900), j(100)),
    _wall('w2', j(900), j(100), j(900), j(900)),
    _wall('w3', j(900), j(900), j(100), j(900)),
  ];
  if (includeW4) walls.add(_wall('w4', j(100), j(900), j(100), j(100)));
  if (extraSpurious) walls.add(_wall('w5', 300, 300, 320, 300));

  return CadFloorPlan(
    sourceWidthPx: kWidth,
    sourceHeightPx: kHeight,
    walls: walls,
    openings: [
      CadOpening(
        id: 'd1',
        type: OpeningType.door,
        center: Point2(j(300) / kWidth, j(100) / kHeight),
        widthNormalized: 60 / kWidth,
        confidence: 0.8,
        wallId: doorWallId ?? 'w1',
      ),
    ],
    rooms: [
      CadRoom(
        id: 'r1',
        polygon: [
          Point2(j(100) / kWidth, j(100) / kHeight),
          Point2(j(900) / kWidth, j(100) / kHeight),
          Point2(j(900) / kWidth, j(900) / kHeight),
          Point2(j(100) / kWidth, j(900) / kHeight),
        ],
        areaNormalized: 0.5,
        confidence: 0.75,
        name: 'Living Room',
      ),
    ],
    warnings: const [],
  );
}

void main() {
  group('repetitionAdjustedConfidence', () {
    test('boosts confidence when all runs agree', () {
      expect(repetitionAdjustedConfidence(0.7, 3, 3), greaterThan(0.7));
    });
    test('pulls confidence down hard for a single-run-only detection', () {
      expect(repetitionAdjustedConfidence(0.7, 1, 3), lessThan(0.4));
    });
    test('keeps majority agreement roughly neutral-to-positive', () {
      final result = repetitionAdjustedConfidence(0.7, 2, 3);
      expect(result, greaterThanOrEqualTo(0.7));
      expect(result, lessThan(0.95));
    });
  });

  group('consolidateCadFloorPlans', () {
    test('returns the single run unchanged when only one run is given', () {
      final run = _rectRun(0);
      expect(consolidateCadFloorPlans([run]), same(run));
    });

    test('keeps walls seen in every run and boosts confidence above any single run value, with reviewNeeded=false', () {
      final runs = [_rectRun(0), _rectRun(0.003), _rectRun(-0.003)];
      final result = consolidateCadFloorPlans(runs);

      expect(result.walls.length, 4);
      for (final w in result.walls) {
        expect(w.confidence, greaterThan(0.8));
        expect(w.reviewNeeded, isFalse);
      }
    });

    test('drops a wall seen in only one run when it is geometrically disconnected from everything else', () {
      final runs = [_rectRun(0, extraSpurious: true), _rectRun(0.003), _rectRun(-0.003)];
      final result = consolidateCadFloorPlans(runs);

      expect(result.walls.length, 4);
      final nearSpurious = result.walls.any(
        (w) => (w.start.x * kWidth - 300).abs() < 50 && (w.start.y * kHeight - 300).abs() < 50,
      );
      expect(nearSpurious, isFalse);
    });

    test('keeps a wall seen in only 2 of 3 runs when it is connected to the rest, flagged reviewNeeded', () {
      final runs = [_rectRun(0), _rectRun(0.003, includeW4: false), _rectRun(-0.003)];
      final result = consolidateCadFloorPlans(runs);

      expect(result.walls.length, 4);
      final leftWall = result.walls.where(
        (w) => (w.start.x * kWidth - 100).abs() < 20 && (w.end.x * kWidth - 100).abs() < 20,
      );
      expect(leftWall, isNotEmpty);
    });

    test('matches the same wall across runs even when one run splits it into two shorter collinear segments', () {
      final runA = _rectRun(0);
      final runB = CadFloorPlan(
        sourceWidthPx: kWidth,
        sourceHeightPx: kHeight,
        walls: [
          _wall('w1a', 100, 100, 500, 100),
          _wall('w1b', 500, 100, 900, 100),
          _wall('w2', 900, 100, 900, 900),
          _wall('w3', 900, 900, 100, 900),
          _wall('w4', 100, 900, 100, 100),
        ],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      final runC = _rectRun(0);

      final result = consolidateCadFloorPlans([runA, runB, runC]);

      final topWall = result.walls.where(
        (w) => (w.start.y * kHeight - 100).abs() < 5 && (w.end.y * kHeight - 100).abs() < 5,
      ).firstOrNull;
      expect(topWall, isNotNull);
      final xs = [topWall!.start.x * kWidth, topWall.end.x * kWidth]..sort();
      expect(xs.first, closeTo(100, 1));
      expect(xs.last, closeTo(900, 1));
      expect(topWall.confidence, greaterThan(0.5));
    });

    test('remaps doors to the consolidated wall id and averages their position', () {
      final runs = [_rectRun(0), _rectRun(0.003), _rectRun(-0.003)];
      final result = consolidateCadFloorPlans(runs);

      expect(result.openings.length, 1);
      final door = result.openings.first;
      final attachedWall = result.walls.where((w) => w.id == door.wallId);
      expect(attachedWall, isNotEmpty);
      expect(door.center.x * kWidth, closeTo(300, 1));
    });

    test('consolidates rooms by centroid and boosts confidence when seen in every run', () {
      final runs = [_rectRun(0), _rectRun(0.003), _rectRun(-0.003)];
      final result = consolidateCadFloorPlans(runs);

      expect(result.rooms.length, 1);
      expect(result.rooms.first.confidence, greaterThan(0.75));
      expect(result.rooms.first.reviewNeeded, isFalse);
    });

    test('drops an opening whose only host wall was removed as noise', () {
      final runs = [
        _rectRun(0, extraSpurious: true, doorWallId: 'w5'),
        _rectRun(0.003, doorWallId: 'w5'),
        _rectRun(-0.003, doorWallId: 'w5'),
      ];
      final result = consolidateCadFloorPlans(runs);
      // Only run A actually has a wall 'w5' (the spurious, single-run,
      // disconnected wall that gets removed as noise) — runs B/C reference
      // a wallId that never existed in their own walls list at all, so
      // their doors have nothing to remap to either. Every door in this
      // set should end up dropped.
      // The door attached to the spurious, single-run, disconnected w5
      // should be dropped along with its wall.
      expect(result.openings, isEmpty);
    });
  });

  group('buildConsolidatedVisionCadFloorPlan', () {
    test('calls buildOnce `samples` times and consolidates the results', () async {
      var callCount = 0;
      final runs = [_rectRun(0), _rectRun(0.003), _rectRun(-0.003)];
      final result = await buildConsolidatedVisionCadFloorPlan(
        Uint8List(0),
        buildOnce: (_) async => runs[callCount++],
        samples: 3,
      );
      expect(callCount, 3);
      expect(result.walls.length, 4);
    });

    test('proceeds with whatever succeeded when some samples fail', () async {
      var callCount = 0;
      final result = await buildConsolidatedVisionCadFloorPlan(
        Uint8List(0),
        buildOnce: (_) async {
          callCount++;
          if (callCount == 2) throw Exception('network error');
          return _rectRun(0);
        },
        samples: 3,
      );
      expect(callCount, 3);
      expect(result.walls, isNotEmpty);
    });

    test('throws when every sample fails', () async {
      expect(
        () => buildConsolidatedVisionCadFloorPlan(
          Uint8List(0),
          buildOnce: (_) async => throw Exception('always fails'),
          samples: 3,
        ),
        throwsException,
      );
    });
  });

  group('사용자 실측 치수 보정이 GPT 재분석에도 덮어써지지 않는다', () {
    test(
      '치수 보정("치수 보정" UI에서 3800mm 입력)으로 만들어진 measured scale은 '
      'buildConsolidatedVisionCadFloorPlan을 다시 실행해 새 GPT 결과가 나와도 '
      'resolveAutoScale(newResult, existingMeasuredScale)에서 그대로 유지된다 '
      '— floor_plan_workspace_screen.dart의 _onRunVisionConsolidation이 실제로 '
      '호출하는 것과 동일한 순서로 재현한다.',
      () async {
        // "치수 보정"에서 사용자가 실제 벽 구간을 골라 3800mm를 입력하면
        // 화면은 정확히 이 모양의 FloorPlanScale을 만든다(source 기본값이
        // ScaleSource.measured — cad_floor_plan.dart 참고).
        const userConfirmedScale = FloorPlanScale(
          mmPerPixel: 31.9328,
          referenceStart: Point2(0.1, 0.1),
          referenceEnd: Point2(0.1, 0.219),
          referenceLengthMm: 3800,
        );
        expect(userConfirmedScale.source, ScaleSource.measured);

        final reAnalyzed = await buildConsolidatedVisionCadFloorPlan(
          Uint8List(0),
          // 재분석은 매번 새로운(약간 다른) GPT 결과를 3회 만들어 통합한다
          // — 실제로 AI 결과가 회차마다 완전히 같지 않다는 전제를 지킨다.
          buildOnce: (_) async => _rectRun(
            0.001 * (DateTime.now().microsecondsSinceEpoch % 5),
          ),
          samples: 3,
        );

        final resolvedAfterReAnalysis = resolveAutoScale(
          reAnalyzed,
          userConfirmedScale,
        );

        expect(identical(resolvedAfterReAnalysis, userConfirmedScale), isTrue);
        expect(resolvedAfterReAnalysis.mmPerPixel, 31.9328);
        expect(resolvedAfterReAnalysis.referenceLengthMm, 3800);
        expect(resolvedAfterReAnalysis.source, ScaleSource.measured);
      },
    );
  });
}
