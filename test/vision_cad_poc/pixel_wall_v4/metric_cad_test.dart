// SPACE SHIFT — WO083 METRIC CAD FOUNDATION.
//
// buildMetricCad가 §3B(축척 미확정 시 mm 절대 생성 금지) /
// §5(임의 두께 기본값 금지, virtual bridge 누출 금지) /
// §6(unknown opening 종류 보존) / §7(SOURCE_EVIDENCE_LIMITED 보존) /
// §8(결정론) 원칙을 지키는지 검증한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/gpt_semantic_schema.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/metric_cad.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/virtual_cad_scale.dart';

const _capturePath = 'lib/vision_cad_poc/pixel_wall_v4/captured/semantic_v4.json';

SSSpatialModel _buildFixtureModel() {
  const we1 = SSWallEdge(
    id: 'we1',
    start: Point2(0.1, 0.2),
    end: Point2(0.6, 0.2),
    thicknessNormalized: 0.01, // horizontal wall -> thickness measured against h.
    kind: SSWallKind.exterior,
    confidence: 0.9,
    physicalWallIds: ['w1', 'w2'],
    source: SSEntitySource.inferredTopology,
  );
  const we2 = SSWallEdge(
    id: 'we2',
    start: Point2(0.6, 0.2),
    end: Point2(0.6, 0.7),
    thicknessNormalized: 0.008, // vertical wall -> thickness measured against w.
    kind: SSWallKind.interior,
    confidence: 0.8,
    physicalWallIds: ['w3'],
    source: SSEntitySource.geometry,
    reviewNeeded: true,
    reviewReasons: ['짧고 junction 근거가 약함'],
  );

  const o1 = SSOpening(
    id: 'o1',
    kind: SSOpeningKind.door,
    center: Point2(0.275, 0.2),
    widthNormalized: 0.05,
    confidence: 0.7,
    parentWallId: 'we1',
    startT: 0.3,
    endT: 0.4,
    source: SSEntitySource.vision,
  );
  const o2 = SSOpening(
    id: 'o2',
    kind: SSOpeningKind.unknown,
    center: Point2(0.6, 0.4625),
    widthNormalized: 0.025,
    confidence: 0.5,
    parentWallId: 'we2',
    startT: 0.5,
    endT: 0.55,
    source: SSEntitySource.inferredTopology,
    reviewNeeded: true,
    reviewReasons: ['pixel gap 근거만 있음'],
  );
  const o3 = SSOpening(
    // parentWallId가 없는 방어적 케이스 — geometry가 없어도 kind는 보존돼야 한다.
    id: 'o3',
    kind: SSOpeningKind.window,
    center: Point2(0.5, 0.5),
    widthNormalized: 0.03,
    confidence: 0.4,
    source: SSEntitySource.vision,
    reviewNeeded: true,
  );

  const closedSpace = SSSpace(
    id: 'space-closed',
    polygon: [Point2(0.1, 0.2), Point2(0.6, 0.2), Point2(0.6, 0.7), Point2(0.1, 0.7)],
    areaNormalized: 0.25,
    closed: true,
    confidence: 0.8,
  );
  const openSpace = SSSpace(
    id: 'space-open',
    polygon: [Point2(0.7, 0.2), Point2(0.9, 0.2)],
    areaNormalized: 0,
    closed: false, // SOURCE_EVIDENCE_LIMITED — 경계가 완전히 닫히지 않음.
    confidence: 0.3,
    reviewNeeded: true,
    reviewReasons: ['경계 evidence 부족'],
  );

  return const SSSpatialModel(
    sourceWidthPx: 1000,
    sourceHeightPx: 800,
    spaces: [closedSpace, openSpace],
    walls: [],
    openings: [o1, o2, o3],
    objects: [],
    warnings: [],
    wallEdges: [we1, we2],
  );
}

// 1 virtual unit(px) = 5mm — 이 fixture 안의 sourceWidthPx(1000)와 정합적인
// 값으로 골랐다(§3C User Anchor 그대로 재사용).
RealWorldScale _fixtureScale() =>
    calibrateScaleFromUserAnchor(a: const VirtualCadPoint(0, 0), b: const VirtualCadPoint(1000, 0), realWorldMm: 5000);

void main() {
  group('toMetricCadPoint — Normalized -> Virtual CAD -> mm', () {
    test('calibrate된 scale이면 정확한 mm 좌표를 반환한다', () {
      final scale = _fixtureScale();
      final p = toMetricCadPoint(const Point2(0.1, 0.2), scale, sourceWidthPx: 1000, sourceHeightPx: 800);
      expect(p, isNotNull);
      expect(p!.xMm, closeTo(500, 1e-6)); // 0.1*1000*5.
      expect(p.yMm, closeTo(800, 1e-6)); // 0.2*800*5.
    });

    test('scale이 unknown이면 null을 반환하고 임의 mm를 만들지 않는다', () {
      final p = toMetricCadPoint(const Point2(0.1, 0.2), const RealWorldScale.unknown(), sourceWidthPx: 1000, sourceHeightPx: 800);
      expect(p, isNull);
    });
  });

  group('buildMetricCad — scale 미확정(§3B)', () {
    test('scale이 unknown이면 walls/openings/rooms 모두 빈 목록이다', () {
      final result = buildMetricCad(_buildFixtureModel(), const RealWorldScale.unknown());
      expect(result.walls, isEmpty);
      expect(result.openings, isEmpty);
      expect(result.rooms, isEmpty);
      expect(result.scale.isCalibrated, isFalse);
    });
  });

  group('buildMetricCad — MetricWall', () {
    test('wall length/centerline mm이 정확히 계산된다', () {
      final result = buildMetricCad(_buildFixtureModel(), _fixtureScale());
      final we1 = result.walls.firstWhere((w) => w.id == 'we1');
      expect(we1.lengthMm, closeTo(2500, 1e-6));
      expect(we1.start.xMm, closeTo(500, 1e-6));
      expect(we1.start.yMm, closeTo(800, 1e-6));
      expect(we1.end.xMm, closeTo(3000, 1e-6));
      expect(we1.end.yMm, closeTo(800, 1e-6));

      final we2 = result.walls.firstWhere((w) => w.id == 'we2');
      expect(we2.lengthMm, closeTo(2000, 1e-6));
    });

    test('두께는 evidence 기반 thicknessNormalized에서만 계산되고 임의 기본값이 섞이지 않는다', () {
      final result = buildMetricCad(_buildFixtureModel(), _fixtureScale());
      final we1 = result.walls.firstWhere((w) => w.id == 'we1'); // horizontal -> * h(800).
      final we2 = result.walls.firstWhere((w) => w.id == 'we2'); // vertical -> * w(1000).
      expect(we1.thicknessMm, closeTo(0.01 * 800 * 5, 1e-6));
      expect(we2.thicknessMm, closeTo(0.008 * 1000 * 5, 1e-6));
    });

    test('provenance(source/reviewNeeded)가 SSWallEdge에서 그대로 보존된다', () {
      final result = buildMetricCad(_buildFixtureModel(), _fixtureScale());
      final we1 = result.walls.firstWhere((w) => w.id == 'we1');
      final we2 = result.walls.firstWhere((w) => w.id == 'we2');
      expect(we1.source, SSEntitySource.inferredTopology);
      expect(we1.reviewNeeded, isFalse);
      expect(we2.source, SSEntitySource.geometry);
      expect(we2.reviewNeeded, isTrue);
    });

    test('MetricWall은 오직 SSSpatialModel.wallEdges에서만 만들어진다 — virtual bridge/합성 벽 누출 금지', () {
      final model = _buildFixtureModel();
      final result = buildMetricCad(model, _fixtureScale());
      expect(result.walls.length, model.wallEdges.length);
      final sourceIds = model.wallEdges.map((e) => e.id).toSet();
      for (final w in result.walls) {
        expect(sourceIds, contains(w.sourceWallEdgeId));
      }
    });
  });

  group('buildMetricCad — MetricOpening', () {
    test('parent wall을 따라 opening 폭(widthMm)이 정확히 계산된다', () {
      final result = buildMetricCad(_buildFixtureModel(), _fixtureScale());
      final o1 = result.openings.firstWhere((o) => o.id == 'o1');
      expect(o1.widthMm, closeTo(250, 1e-6)); // (0.4-0.3)*500(virtual)*5mm.
      final o2 = result.openings.firstWhere((o) => o.id == 'o2');
      expect(o2.widthMm, closeTo(100, 1e-6)); // (0.55-0.5)*400(virtual)*5mm.
    });

    test('parent wall 위 opening 중심 위치가 startT/endT 보간으로 보존된다', () {
      final result = buildMetricCad(_buildFixtureModel(), _fixtureScale());
      final o1 = result.openings.firstWhere((o) => o.id == 'o1');
      expect(o1.center, isNotNull);
      expect(o1.center!.xMm, closeTo(1375, 1e-6));
      expect(o1.center!.yMm, closeTo(800, 1e-6));

      final o2 = result.openings.firstWhere((o) => o.id == 'o2');
      expect(o2.center, isNotNull);
      expect(o2.center!.xMm, closeTo(3000, 1e-6));
      expect(o2.center!.yMm, closeTo(1850, 1e-6));
    });

    test('kind가 unknown/window인 opening은 종류를 임의로 확정하지 않고 그대로 유지한다', () {
      final result = buildMetricCad(_buildFixtureModel(), _fixtureScale());
      expect(result.openings.firstWhere((o) => o.id == 'o2').kind, SSOpeningKind.unknown);
      expect(result.openings.firstWhere((o) => o.id == 'o3').kind, SSOpeningKind.window);
    });

    test('parentWallId가 없으면 geometry 없이도 opening kind/provenance는 보존된다', () {
      final result = buildMetricCad(_buildFixtureModel(), _fixtureScale());
      final o3 = result.openings.firstWhere((o) => o.id == 'o3');
      expect(o3.center, isNull);
      expect(o3.widthMm, isNull);
      expect(o3.kind, SSOpeningKind.window);
      expect(o3.source, SSEntitySource.vision);
      expect(o3.reviewNeeded, isTrue);
    });
  });

  group('buildMetricCad — MetricRoom', () {
    test('닫힌 polygon은 mm 좌표로 변환되고 shoelace 면적이 정확하다', () {
      final result = buildMetricCad(_buildFixtureModel(), _fixtureScale());
      final room = result.rooms.firstWhere((r) => r.id == 'space-closed');
      expect(room.polygon, hasLength(4));
      expect(room.areaMm2, closeTo(2500 * 2000, 1e-3)); // 2500mm x 2000mm 사각형.
    });

    test('SOURCE_EVIDENCE_LIMITED(닫히지 않은) 공간은 폴리곤/면적을 임의로 채우지 않는다', () {
      final result = buildMetricCad(_buildFixtureModel(), _fixtureScale());
      final room = result.rooms.firstWhere((r) => r.id == 'space-open');
      expect(room.polygon, isEmpty);
      expect(room.areaMm2, isNull);
    });
  });

  group('buildMetricCad — 결정론(§8/§15)', () {
    test('동일한 model/scale 입력에 대해 항상 동일한 Metric CAD 출력을 만든다', () {
      final model = _buildFixtureModel();
      final scale = _fixtureScale();
      final a = buildMetricCad(model, scale);
      final b = buildMetricCad(model, scale);

      expect(a.walls.length, b.walls.length);
      for (var i = 0; i < a.walls.length; i++) {
        expect(a.walls[i].id, b.walls[i].id);
        expect(a.walls[i].start, b.walls[i].start);
        expect(a.walls[i].end, b.walls[i].end);
        expect(a.walls[i].lengthMm, b.walls[i].lengthMm);
        expect(a.walls[i].thicknessMm, b.walls[i].thicknessMm);
      }
      expect(a.openings.length, b.openings.length);
      for (var i = 0; i < a.openings.length; i++) {
        expect(a.openings[i].widthMm, b.openings[i].widthMm);
        expect(a.openings[i].center, b.openings[i].center);
      }
      expect(a.rooms.length, b.rooms.length);
      for (var i = 0; i < a.rooms.length; i++) {
        expect(a.rooms[i].areaMm2, b.rooms[i].areaMm2);
        expect(a.rooms[i].polygon, b.rooms[i].polygon);
      }
    });
  });

  group('실제 이미지 2 — Metric CAD 레이어가 기존 evidence/topology 회귀에 영향을 주지 않는다', () {
    test('scale 미확정 상태에서도 96/105/23/9 회귀는 그대로이고 Metric 목록은 비어 있다', () {
      final bytes = loadRealImage2Bytes();
      if (bytes == null || !File(_capturePath).existsSync()) {
        // ignore: avoid_print
        print('SKIP: 실제 이미지 2 또는 캡처된 semantic_v4.json 없음');
        return;
      }
      final json = jsonDecode(File(_capturePath).readAsStringSync()) as Map<String, dynamic>;
      final semantic = GptSemanticResponse.fromJson(json);
      final result = runPixelWallPipeline(imageBytes: bytes, semantic: semantic);
      final fd = result.floorDomain;

      expect(fd.graphVertexCount, 96);
      expect(fd.graphEdgeCount, 105);
      expect(fd.tJunctionCount, 23);
      expect(fd.isValid, isFalse);
      expect(fd.sourceEvidenceLimited, isTrue);
      expect(result.physicalRooms.length, 9);

      // scale 미확정 — Metric CAD는 아직 mm 기하를 만들지 않는다(§3B).
      final unscaled = buildMetricCad(result.model, const RealWorldScale.unknown());
      expect(unscaled.walls, isEmpty);
      expect(unscaled.openings, isEmpty);
      expect(unscaled.rooms, isEmpty);

      // 실제 모델의 두 WallEdge 끝점을 User Anchor로 골라 calibrate하면
      // (§3C) 모든 wallEdge가 결정론적으로 mm 벽으로 변환된다 — 새 evidence
      // 없이 이미 확정된 topology/scale만으로 계산됐는지 확인한다.
      final firstEdge = result.model.wallEdges.first;
      final a = VirtualCadPoint.fromNormalized(firstEdge.start, w: result.model.sourceWidthPx, h: result.model.sourceHeightPx);
      final b = VirtualCadPoint.fromNormalized(firstEdge.end, w: result.model.sourceWidthPx, h: result.model.sourceHeightPx);
      final scale = calibrateScaleFromUserAnchor(a: a, b: b, realWorldMm: 3000);
      expect(scale.confidence, ScaleConfidence.userAnchored);

      final scaled = buildMetricCad(result.model, scale);
      expect(scaled.walls.length, result.model.wallEdges.length);
      for (final w in scaled.walls) {
        expect(w.lengthMm, greaterThan(0));
        expect(w.lengthMm.isFinite, isTrue);
      }
    });
  });
}
