// SS-수정003 4차 — 1280·1024·800·640 창에서 홈 시작 카드·히어로 부제·프로젝트 관리 안내·이어서 하기 줄·
// 작업 화면 머리글 안내·인식 부족 안내 상자의 한국어가 단어 중간에서 끊기지 않는다.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/home_screen.dart';
import 'package:ason_space/screens/project_management_screen.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:ason_space/widgets/workspace/ss_recognition_shortfall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ss_keep_words_expect.dart';

const _sizes = [Size(1280, 720), Size(1024, 768), Size(800, 600), Size(640, 480)];

SsProject _reviewProject() =>
    SsProject.create(id: 'a', name: '우리집 리모델링', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1)).moveTo(SsStage.floorPlanReview, now: DateTime(2026, 1, 2));

Future<MemorySsProjectStore> _prepare(WidgetTester tester, Size size, {bool withProject = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemorySsProjectStore();
  if (withProject) {
    await store.save(_reviewProject());
    await store.setLastOpened('a');
  }
  SsProjectStoreProvider.useForTesting(store);
  addTearDown(SsProjectStoreProvider.resetForTesting);
  return store;
}

void main() {
  for (final size in _sizes) {
    final w = size.width.toInt();

    testWidgets('$w 폭 — 홈 시작 카드 설명·히어로 부제는 단어 중간에서 끊기지 않는다', (tester) async {
      final store = await _prepare(tester, size);
      await tester.pumpWidget(
        MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, home: SsStageScreen(stage: SsStage.home, child: HomeScreen(projectStore: store))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final type in SsSourceType.values) {
        expectKeepsWords(tester, find.byKey(Key('ssHomeStartCardDesc_${type.name}')), reason: '$w ${type.name}');
      }
      expectKeepsWords(tester, find.byKey(const Key('ssHomeHeroDescription')), reason: '$w 히어로 부제');
    });

    testWidgets('$w 폭 — 프로젝트 관리 안내·이어서 하기 줄은 단어 중간에서 끊기지 않는다', (tester) async {
      final store = await _prepare(tester, size, withProject: true);
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: SsRouter.onGenerateRoute,
          home: SsStageScreen(stage: SsStage.projectManagement, child: ProjectManagementScreen(projectStore: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectKeepsWords(tester, find.byKey(const Key('ssStageWhat')), reason: '$w 관리 안내');
      expectKeepsWords(tester, find.byKey(const Key('ssProjectsResumeText')), reason: '$w 이어서 하기');
    });

    testWidgets('$w 폭 — 작업 화면 머리글 안내는 단어 중간에서 끊기지 않는다', (tester) async {
      final store = await _prepare(tester, size, withProject: true);
      await tester.pumpWidget(
        MaterialApp(
          home: SsStageScreen(
            stage: SsStage.floorPlanReview,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.topLeft,
                child: SsStageHeader(stage: SsStage.floorPlanReview, projectId: 'a', projectStore: store),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ssStageProjectName')), findsOneWidget);
      expectKeepsWords(tester, find.byKey(const Key('ssStageWhat')), reason: '$w 머리글 안내');
    });

    testWidgets('$w 폭 — 인식 부족 안내 상자는 단어 중간에서 끊기지 않는다', (tester) async {
      await _prepare(tester, size);
      final shortfall = SsRecognitionShortfall(
        headline: '방을 찾지 못했습니다 · 벽 3개만 인식 · 문/창을 찾지 못했습니다',
        reason: SsRecognitionShortfall.reasonFor(aiRecognitionConnected: false),
        engineDetail: '기본 인식 엔진이 찾은 후보: 벽 3 · 방 0 · 문/창 0',
        warnings: const ['도면 해상도가 낮아 선을 일부만 읽었습니다.'],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SsStageScreen(
            stage: SsStage.floorPlanUpload,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SsRecognitionShortfallNotice(shortfall: shortfall, busy: false, onRetry: () {}, onPickOther: () {}, onDirectEdit: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final key in const ['ssShortfallHeadline', 'ssShortfallReason', 'ssShortfallEngineDetail', 'ssShortfallWarning_0']) {
        expectKeepsWords(tester, find.byKey(Key(key)), reason: '$w $key');
      }
    });
  }
}
