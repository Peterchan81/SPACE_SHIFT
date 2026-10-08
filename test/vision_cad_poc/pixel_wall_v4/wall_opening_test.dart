// SPACE SHIFT — PC1 CONTINUE: DOOR/WINDOW → PARENT WALL + PARAMETRIC OPENING.
//
// [WallSystem](wall_system.dart)을 parent wall("WallEdge")로 그대로
// 재사용해 doorOpening 크기 gap만 [WallOpening]으로 만들고, GPT
// doorArc/windowDetail 근거가 실제로 겹칠 때만 종류를 확정한다는 원칙을
// 합성 데이터로 검증한다(planar_wall_graph_test.dart와 같은 스타일 —
// 좌표 하드코딩이 아니라 이미지 전체에 적용되는 일반 규칙만 검증).

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/wall_opening.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/wall_system.dart';

const w = 400;
const h = 300;

PixelWallCandidate _seg({
  required String id,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  PixelWallOrientation? orientation,
  bool isExterior = false,
  double thicknessPx = 6,
  double confidence = 0.8,
  PixelWallCategory category = PixelWallCategory.structural,
  PixelWallNoiseCategory noiseCategory = PixelWallNoiseCategory.trueStructural,
}) {
  final o = orientation ?? (y1 == y2 ? PixelWallOrientation.horizontal : PixelWallOrientation.vertical);
  return PixelWallCandidate(
    id: id,
    start: Point2(x1 / w, y1 / h),
    end: Point2(x2 / w, y2 / h),
    thicknessNormalized: thicknessPx / (o == PixelWallOrientation.horizontal ? h : w),
    orientation: o,
    isExterior: isExterior,
    baseConfidence: confidence,
    junctionSupport: 2,
    confidenceTier: PixelWallConfidenceTier.high,
    category: category,
    noiseCategory: noiseCategory,
    sourceSegmentIds: [id],
  );
}

void main() {
  group('buildWallOpenings — door/window classification', () {
    test('TEST 1: door 크기 gap + doorArc 의미 근거 → door interval opening이 만들어진다', () {
      final left = _seg(id: 'left', x1: 0, y1: 50, x2: 100, y2: 50);
      final right = _seg(id: 'right', x1: 120, y1: 50, x2: 220, y2: 50); // gap 20px, door 범위.
      final doorHint = _seg(
        id: 'door-hint',
        x1: 100,
        y1: 50,
        x2: 120,
        y2: 50,
        category: PixelWallCategory.reviewNeeded,
        noiseCategory: PixelWallNoiseCategory.doorArc,
      );
      final systems = buildWallSystems(candidates: [left, right], w: w, h: h);
      expect(systems, hasLength(1));
      expect(systems.single.gaps, hasLength(1));
      expect(systems.single.gaps.single.kind, GapKind.doorOpening);

      final openings = buildWallOpenings(wallSystems: systems, allCandidates: [left, right, doorHint], w: w, h: h).openings;
      expect(openings, hasLength(1));
      final opening = openings.single;
      expect(opening.kind, OpeningKind.door);
      expect(opening.parentWallId, systems.single.id);
      expect(opening.reviewNeeded, isFalse);
      expect(opening.startT, greaterThan(0));
      expect(opening.endT, lessThan(1));
      expect(opening.startT, lessThan(opening.endT));
    });

    test('TEST 2: door 크기 gap + windowDetail 의미 근거 → window interval opening이 만들어진다', () {
      final left = _seg(id: 'left', x1: 0, y1: 50, x2: 100, y2: 50);
      final right = _seg(id: 'right', x1: 120, y1: 50, x2: 220, y2: 50);
      final windowHint = _seg(
        id: 'window-hint',
        x1: 100,
        y1: 50,
        x2: 120,
        y2: 50,
        category: PixelWallCategory.reviewNeeded,
        noiseCategory: PixelWallNoiseCategory.windowDetail,
      );
      final systems = buildWallSystems(candidates: [left, right], w: w, h: h);
      final openings = buildWallOpenings(wallSystems: systems, allCandidates: [left, right, windowHint], w: w, h: h).openings;
      expect(openings, hasLength(1));
      expect(openings.single.kind, OpeningKind.window);
      expect(openings.single.reviewNeeded, isFalse);
    });

    test('의미 근거가 없으면 unknownOpening + reviewNeeded=true로 남는다(추측 금지)', () {
      final left = _seg(id: 'left', x1: 0, y1: 50, x2: 100, y2: 50);
      final right = _seg(id: 'right', x1: 120, y1: 50, x2: 220, y2: 50);
      final systems = buildWallSystems(candidates: [left, right], w: w, h: h);
      final openings = buildWallOpenings(wallSystems: systems, allCandidates: [left, right], w: w, h: h).openings;
      expect(openings, hasLength(1));
      expect(openings.single.kind, OpeningKind.unknownOpening);
      expect(openings.single.reviewNeeded, isTrue);
    });

    test('TEST 8(imageBreak): 아주 작은 gap(imageBreak)은 자동으로 door가 되지 않는다', () {
      final left = _seg(id: 'left', x1: 0, y1: 50, x2: 100, y2: 50);
      final right = _seg(id: 'right', x1: 102, y1: 50, x2: 200, y2: 50); // 2px gap, imageBreak 범위.
      final systems = buildWallSystems(candidates: [left, right], w: w, h: h);
      expect(systems.single.gaps.single.kind, GapKind.imageBreak);
      final openings = buildWallOpenings(wallSystems: systems, allCandidates: [left, right], w: w, h: h).openings;
      expect(openings, isEmpty, reason: 'imageBreak gap은 Opening을 만들지 않는다(§7)');
    });

    test('openPlan 크기 gap(내부 벽, 문 범위 초과)도 Opening을 만들지 않는다', () {
      final left = _seg(id: 'left', x1: 0, y1: 50, x2: 100, y2: 50);
      final right = _seg(id: 'right', x1: 200, y1: 50, x2: 300, y2: 50); // 100px gap, 문 범위(65px) 초과.
      final systems = buildWallSystems(candidates: [left, right], w: w, h: h);
      expect(systems.single.gaps.single.kind, GapKind.openPlan);
      final openings = buildWallOpenings(wallSystems: systems, allCandidates: [left, right], w: w, h: h).openings;
      expect(openings, isEmpty);
    });

    test('TEST 10: 한 벽 위에 여러 개구부가 있어도 각각 정확히 매칭된다', () {
      final a = _seg(id: 'a', x1: 0, y1: 50, x2: 100, y2: 50);
      final b = _seg(id: 'b', x1: 120, y1: 50, x2: 220, y2: 50);
      final c = _seg(id: 'c', x1: 240, y1: 50, x2: 340, y2: 50);
      final systems = buildWallSystems(candidates: [a, b, c], w: w, h: h);
      expect(systems, hasLength(1));
      expect(systems.single.gaps, hasLength(2));
      final openings = buildWallOpenings(wallSystems: systems, allCandidates: [a, b, c], w: w, h: h).openings;
      expect(openings, hasLength(2));
      expect(openings[0].parentWallId, systems.single.id);
      expect(openings[1].parentWallId, systems.single.id);
      expect(openings[0].startT, lessThan(openings[1].startT), reason: 'along-axis 순서가 유지돼야 한다');
    });

    test('TEST 12: provenance가 parent wall/앞뒤 physical segment/의미 근거 id를 그대로 보존한다', () {
      final left = _seg(id: 'left-seg', x1: 0, y1: 50, x2: 100, y2: 50);
      final right = _seg(id: 'right-seg', x1: 120, y1: 50, x2: 220, y2: 50);
      final doorHint = _seg(
        id: 'door-hint-1',
        x1: 100,
        y1: 50,
        x2: 120,
        y2: 50,
        category: PixelWallCategory.reviewNeeded,
        noiseCategory: PixelWallNoiseCategory.doorArc,
      );
      final systems = buildWallSystems(candidates: [left, right], w: w, h: h);
      final opening = buildWallOpenings(wallSystems: systems, allCandidates: [left, right, doorHint], w: w, h: h).openings.single;
      expect(opening.provenance, containsAll(<String>[systems.single.id, 'left-seg', 'right-seg', 'door-hint-1']));
    });

    test('13: Image 2 특정 좌표/해상도에 의존하지 않는다 — 임의 캔버스 크기에서도 동일 규칙이 적용된다', () {
      const altW = 913; // Image2의 분석 해상도(443x301류)와 무관한 임의 값.
      const altH = 617;
      PixelWallCandidate segAt(String id, double x1, double y1, double x2, double y2) => PixelWallCandidate(
        id: id,
        start: Point2(x1 / altW, y1 / altH),
        end: Point2(x2 / altW, y2 / altH),
        thicknessNormalized: 6 / altH,
        orientation: PixelWallOrientation.horizontal,
        isExterior: false,
        baseConfidence: 0.8,
        junctionSupport: 2,
        confidenceTier: PixelWallConfidenceTier.high,
        category: PixelWallCategory.structural,
        sourceSegmentIds: [id],
      );
      final left = segAt('l', 10, 400, 250, 400);
      final right = segAt('r', 270, 400, 500, 400);
      final systems = buildWallSystems(candidates: [left, right], w: altW, h: altH);
      final openings = buildWallOpenings(wallSystems: systems, allCandidates: [left, right], w: altW, h: altH).openings;
      expect(openings, hasLength(1));
      expect(openings.single.isValidInterval, isTrue);
    });
  });

  group('buildWallOpenings — CAD/DXF FIRST GOAL 인식 품질 개선 WO §2 (reviewNeeded 교차 검증)', () {
    test(
      'pixel gap이 전혀 없어도(구조 벽 자체가 없어도) 근처에 reviewNeeded '
      'candidate가 있으면 GPT hint와 교차 검증해 opening을 만든다 — '
      'reviewNeeded=true, source=semanticAi로 정직하게 남긴다',
      () {
        // 이 doorHint 근처에는 confirmed structural wall이 전혀 없다 — 이
        // reviewWallNearHint(trueStructural, 아직 구조 벽으로 확정되지 않음)
        // 하나만 있다. 기존 로직이라면 semantic evidence가 조용히 버려졌다.
        final unrelated = _seg(id: 'unrelated', x1: 0, y1: 200, x2: 100, y2: 200);
        final reviewWallNearHint = _seg(
          id: 'review-wall',
          x1: 100,
          y1: 50,
          x2: 220,
          y2: 50,
          category: PixelWallCategory.reviewNeeded,
          noiseCategory: PixelWallNoiseCategory.trueStructural,
        );
        final doorHint = _seg(
          id: 'door-hint',
          x1: 150,
          y1: 50,
          x2: 170,
          y2: 50,
          category: PixelWallCategory.reviewNeeded,
          noiseCategory: PixelWallNoiseCategory.doorArc,
        );
        final systems = buildWallSystems(candidates: [unrelated], w: w, h: h);
        final result = buildWallOpenings(
          wallSystems: systems,
          allCandidates: [unrelated, reviewWallNearHint, doorHint],
          w: w,
          h: h,
        );

        expect(result.unmatchedSemanticHints, isEmpty, reason: '실제로 근처에 pixel 증거가 있으므로 버려지면 안 된다');
        expect(result.openings, hasLength(1));
        final opening = result.openings.single;
        expect(opening.kind, OpeningKind.door);
        expect(opening.reviewNeeded, isTrue, reason: 'pixel gap 근거가 없으므로 항상 사람 확인이 필요하다');
        expect(opening.source, OpeningEvidenceSource.semanticAi);
        expect(result.extraWallSystems, hasLength(1));
        expect(opening.parentWallId, result.extraWallSystems.single.id);
      },
    );

    test(
      'hint의 along 위치 자체가 매칭된 reviewNeeded 벽의 감지된 extent 밖(그러나 '
      'extentTolerancePx 이내)이어도 폭 0으로 무너지지 않고 그 벽 경계에 붙어 '
      '유효한 interval을 만든다(실측 조사로 발견된 2차 버그 회귀 방지)',
      () {
        final unrelated = _seg(id: 'unrelated', x1: 0, y1: 200, x2: 100, y2: 200);
        // reviewWallNearHint의 감지된 extent는 x:100~220이다.
        final reviewWallNearHint = _seg(
          id: 'review-wall-2',
          x1: 100,
          y1: 50,
          x2: 220,
          y2: 50,
          category: PixelWallCategory.reviewNeeded,
          noiseCategory: PixelWallNoiseCategory.trueStructural,
        );
        // doorHint의 중심(along=70)은 이 extent(100~220) 밖이다 — 다만
        // collinearity(같은 y=50)는 정확히 맞고, along 차이(30px)는
        // extentTolerancePx(40)보다 작다.
        final doorHint = _seg(
          id: 'door-hint-outside-extent',
          x1: 60,
          y1: 50,
          x2: 80,
          y2: 50,
          category: PixelWallCategory.reviewNeeded,
          noiseCategory: PixelWallNoiseCategory.doorArc,
        );
        final systems = buildWallSystems(candidates: [unrelated], w: w, h: h);
        final result = buildWallOpenings(
          wallSystems: systems,
          allCandidates: [unrelated, reviewWallNearHint, doorHint],
          w: w,
          h: h,
        );

        expect(result.unmatchedSemanticHints, isEmpty);
        expect(result.openings, hasLength(1));
        final opening = result.openings.single;
        expect(opening.isValidInterval, isTrue);
        expect(opening.startT, lessThan(opening.endT));
        // extent 밖에서 온 hint이므로 매칭된 벽의 시작 경계(startT=0)에 붙어야 한다.
        expect(opening.startT, 0.0);
      },
    );

    test(
      'structural도 reviewNeeded도 근처에 전혀 없으면(진짜 벽 geometry가 없으면) '
      'opening을 지어내지 않고 unmatchedSemanticHints로 정직하게 남긴다',
      () {
        final unrelated = _seg(id: 'unrelated', x1: 0, y1: 200, x2: 100, y2: 200);
        final isolatedDoorHint = _seg(
          id: 'isolated-door-hint',
          x1: 150,
          y1: 50,
          x2: 170,
          y2: 50,
          category: PixelWallCategory.reviewNeeded,
          noiseCategory: PixelWallNoiseCategory.doorArc,
        );
        final systems = buildWallSystems(candidates: [unrelated], w: w, h: h);
        final result = buildWallOpenings(
          wallSystems: systems,
          allCandidates: [unrelated, isolatedDoorHint],
          w: w,
          h: h,
        );

        expect(result.openings, isEmpty, reason: '근거 없는 opening을 지어내면 안 된다(§3 원칙)');
        expect(result.extraWallSystems, isEmpty);
        expect(result.unmatchedSemanticHints, hasLength(1));
        expect(result.unmatchedSemanticHints.single.id, 'isolated-door-hint');
      },
    );
  });

  group('matchParentWallSystem — §5 순수 최단거리 금지', () {
    test('TEST 6: extent 안에 있고 collinear한 점은 올바른 벽에 매칭된다', () {
      final a = _seg(id: 'a', x1: 0, y1: 50, x2: 200, y2: 50);
      final systems = buildWallSystems(candidates: [a], w: w, h: h);
      final match = matchParentWallSystem(
        systems: systems,
        orientation: PixelWallOrientation.horizontal,
        crossPx: 51,
        alongPx: 100,
        candidateThicknessPx: 4,
      );
      expect(match?.id, systems.single.id);
    });

    test('TEST 5: cross-axis로는 완전히 collinear(0 거리)해도 벽의 extent 밖이면 거부된다', () {
      final a = _seg(id: 'a', x1: 0, y1: 50, x2: 100, y2: 50);
      final systems = buildWallSystems(candidates: [a], w: w, h: h);
      // crossPx가 axisPx와 정확히 같아 "가장 가까워 보이지만", alongPx(250)는
      // 이 벽의 extent(0..100)에서 한참 벗어나 있다 — 순수 최단거리라면
      // (cross distance=0) 이 벽을 골랐겠지만, extent 검사로 거부돼야 한다.
      final match = matchParentWallSystem(
        systems: systems,
        orientation: PixelWallOrientation.horizontal,
        crossPx: systems.single.axisPx,
        alongPx: 250,
        candidateThicknessPx: 4,
      );
      expect(match, isNull, reason: 'extent 밖이면 cross-axis 거리가 0이어도 매칭되면 안 된다');
    });

    test('방향이 다르면 아무리 가까워도 매칭되지 않는다', () {
      final a = _seg(id: 'a', x1: 0, y1: 50, x2: 200, y2: 50);
      final systems = buildWallSystems(candidates: [a], w: w, h: h);
      final match = matchParentWallSystem(
        systems: systems,
        orientation: PixelWallOrientation.vertical,
        crossPx: 50,
        alongPx: 100,
        candidateThicknessPx: 4,
      );
      expect(match, isNull);
    });
  });

  group('validateOpenings — §10 cross-reference validator', () {
    test('TEST 4: 존재하지 않는 parentWallId는 조용히 버리지 않고 rejected로 보고한다', () {
      const bad = WallOpening(
        id: 'o1',
        kind: OpeningKind.door,
        parentWallId: 'no-such-wall',
        startT: 0.2,
        endT: 0.4,
        confidence: 0.5,
        reviewNeeded: true,
        source: OpeningEvidenceSource.pixel,
      );
      final result = validateOpenings(openings: [bad], validParentWallIds: {'wallsystem-horizontal-0'});
      expect(result.valid, isEmpty);
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.opening.id, 'o1');
      expect(result.rejected.single.reason, contains('parentWallId'));
    });

    test('TEST 3: startT >= endT, 또는 [0,1] 밖이면 유효하지 않은 interval로 거부된다', () {
      const reversed = WallOpening(
        id: 'o-reversed',
        kind: OpeningKind.door,
        parentWallId: 'w1',
        startT: 0.6,
        endT: 0.4,
        confidence: 0.5,
        reviewNeeded: true,
        source: OpeningEvidenceSource.pixel,
      );
      const outOfRange = WallOpening(
        id: 'o-outofrange',
        kind: OpeningKind.door,
        parentWallId: 'w1',
        startT: -0.1,
        endT: 0.4,
        confidence: 0.5,
        reviewNeeded: true,
        source: OpeningEvidenceSource.pixel,
      );
      final result = validateOpenings(openings: [reversed, outOfRange], validParentWallIds: {'w1'});
      expect(result.valid, isEmpty);
      expect(result.rejected, hasLength(2));
      for (final r in result.rejected) {
        expect(r.reason, contains('interval'));
      }
    });

    test('TEST 11: 같은 벽 위에서 서로 다른 종류로 겹치는 opening은 충돌로 거부된다', () {
      const door = WallOpening(
        id: 'o-door',
        kind: OpeningKind.door,
        parentWallId: 'w1',
        startT: 0.2,
        endT: 0.5,
        confidence: 0.6,
        reviewNeeded: false,
        source: OpeningEvidenceSource.semanticAi,
      );
      const window = WallOpening(
        id: 'o-window',
        kind: OpeningKind.window,
        parentWallId: 'w1',
        startT: 0.4,
        endT: 0.7,
        confidence: 0.6,
        reviewNeeded: false,
        source: OpeningEvidenceSource.semanticAi,
      );
      final result = validateOpenings(openings: [door, window], validParentWallIds: {'w1'});
      expect(result.valid, isEmpty);
      expect(result.rejected, hasLength(2));
    });

    test('같은 벽 위에서 겹치지 않는 여러 개구부는 모두 유효로 남는다', () {
      const a = WallOpening(
        id: 'o-a',
        kind: OpeningKind.door,
        parentWallId: 'w1',
        startT: 0.1,
        endT: 0.2,
        confidence: 0.6,
        reviewNeeded: false,
        source: OpeningEvidenceSource.pixel,
      );
      const b = WallOpening(
        id: 'o-b',
        kind: OpeningKind.window,
        parentWallId: 'w1',
        startT: 0.6,
        endT: 0.7,
        confidence: 0.6,
        reviewNeeded: false,
        source: OpeningEvidenceSource.pixel,
      );
      final result = validateOpenings(openings: [a, b], validParentWallIds: {'w1'});
      expect(result.valid, hasLength(2));
      expect(result.rejected, isEmpty);
    });
  });
}
