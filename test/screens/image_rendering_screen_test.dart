// SS007 — MASTER UI 4-2-1(이미지 AI 렌더링) 화면 위젯 테스트: 렌더링이 끝나면 결과를 저장하고 다음
// 화면으로 넘어가는지, 실패하면 재시도/수정 작업으로 돌아가기 버튼이 보이고 원본·편집 데이터가 그대로
// 남아 있는지 확인한다.
import 'dart:typed_data';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_render_step.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/ss_photo_scene.dart';
import 'package:ason_space/screens/image_rendering_screen.dart';
import 'package:ason_space/services/ss_photo_render_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

class _AlwaysFailRenderService extends SsPhotoRenderService {
  const _AlwaysFailRenderService() : super(stepDelay: Duration.zero);

  @override
  Future<Uint8List> render(SsPhotoScene scene, {void Function(SsRenderStep step)? onStep}) async {
    onStep?.call(SsRenderStep.analyzingImage);
    throw Exception('렌더링 실패(시험)');
  }
}

void main() {
  late MemorySsProjectStore store;

  setUp(() async {
    store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: '렌더링 테스트', sourceType: SsSourceType.imageTransform, now: DateTime(2026, 1, 1));
    project = project.withSource({'imageBase64': _tinyPngBase64}, label: '원본 사진');
    await store.save(project);
  });

  Future<void> pump(WidgetTester tester, {SsPhotoRenderService renderService = const SsPhotoRenderService(stepDelay: Duration.zero)}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImageRenderingScreen(projectId: 'p1', projectStore: store, renderService: renderService)),
        onGenerateRoute: (settings) {
          if (settings.name == SsStage.imageResult.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('RESULT', key: Key('ssFakeResultScreen'))), settings: settings);
          }
          if (settings.name == SsStage.imageEditing.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('EDIT', key: Key('ssFakeEditScreen'))), settings: settings);
          }
          return null;
        },
      ),
    );
  }

  testWidgets('렌더링이 끝나면 결과를 저장하고 결과 화면으로 넘어간다', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeResultScreen')), findsOneWidget);

    final saved = await store.load('p1');
    expect(saved?.currentStage, SsStage.imageResult);
    expect(saved?.data[SsDataSlot.renderData], isNotNull);
  });

  testWidgets('렌더링이 실패하면 다시 시도·수정 작업으로 돌아가기 버튼이 보이고 원본 데이터는 그대로다', (tester) async {
    await pump(tester, renderService: const _AlwaysFailRenderService());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssRenderRetry')), findsOneWidget);
    expect(find.byKey(const Key('ssRenderBackToEditFromFail')), findsOneWidget);

    final saved = await store.load('p1');
    expect(saved?.data[SsDataSlot.renderData], isNull);
    expect(saved?.data[SsDataSlot.sourceData], isNotNull);
  });
}
