// #1027-23 남은 문제 2 — 1024 폭에서 "다른 이미지 업로드" 버튼 글자가 한 줄로 보인다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:ason_space/models/floor_plan_file.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/screens/floor_plan_upload_screen.dart';
import 'package:ason_space/services/floor_plan_analysis_service.dart';
import 'package:ason_space/services/floor_plan_upload_service.dart';
import 'package:ason_space/services/ss_spatial_model_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _bytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

const _result = FloorPlanAnalysisResult(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  walls: [],
  openings: [],
  rooms: [],
  warnings: [],
  debugStats: FloorPlanAnalysisDebugStats(
    sourceWidthPx: 800,
    sourceHeightPx: 600,
    analysisWidthPx: 800,
    analysisHeightPx: 600,
    rawHorizontalRuns: 0,
    rawVerticalRuns: 0,
    mergedWallCount: 0,
    roomCandidateCount: 0,
    openingCandidateCount: 0,
    durationMs: 1,
  ),
);

const _model = SSSpatialModel(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  spaces: [
    SSSpace(id: 'space-1', polygon: [Point2(0.05, 0.05), Point2(0.95, 0.05), Point2(0.95, 0.95), Point2(0.05, 0.95)], areaNormalized: 0.8, closed: true, confidence: 0.9),
  ],
  walls: [
    SSWall(id: 'wall-1', start: Point2(0, 0), end: Point2(1, 0), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
    SSWall(id: 'wall-2', start: Point2(0, 0), end: Point2(0, 1), thicknessNormalized: 0.02, kind: SSWallKind.interior, confidence: 0.9),
  ],
  openings: [
    SSOpening(id: 'door-1', kind: SSOpeningKind.door, center: Point2(0.5, 0.0), widthNormalized: 0.05, confidence: 0.8),
  ],
  objects: [],
  warnings: [],
);

class _Upload extends FloorPlanUploadService {
  @override
  Future<FloorPlanFile?> pickFloorPlanFile() async =>
      FloorPlanFile(fileName: 'plan.png', extension: 'png', kind: FloorPlanFileKind.image, sizeBytes: _bytes.length, bytes: _bytes);
}

class _Analysis extends FloorPlanAnalysisService {
  const _Analysis();
  @override
  Future<FloorPlanAnalysisOutcome> analyze(FloorPlanFile file, {void Function(FloorPlanAnalysisStep step)? onStep}) async =>
      const FloorPlanAnalysisOutcome.success(_result);
}

class _Builder extends SSSpatialModelBuilder {
  const _Builder();
  @override
  SSSpatialModel build(FloorPlanAnalysisResult result) => _model;
}

void main() {
  testWidgets('1024×768 창(좌측 메뉴 제외 788×704)에서 "다른 이미지 업로드"가 한 줄로 보인다', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 788,
              height: 704,
              child: FloorPlanUploadScreen(uploadService: _Upload(), analysisService: const _Analysis(), spatialModelBuilder: const _Builder()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssUploadPickButton')));
    await tester.pumpAndSettle();

    expect(find.text('다른 이미지 업로드'), findsOneWidget);
    final label = tester.getSize(find.byKey(const Key('ssUploadPickLabel')));
    expect(label.height, lessThan(24), reason: '한 줄 높이(두 줄로 끊기지 않음)');
    expect(tester.getSize(find.byKey(const Key('ssSourcePanelTitle'))).height, lessThan(30));
    for (final key in ['ssRotateButton', 'ssCropButton', 'ssZoomOutButton', 'ssZoomLevelText', 'ssZoomInButton', 'ssFullscreenButton']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const Key('ssUploadedImage')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
