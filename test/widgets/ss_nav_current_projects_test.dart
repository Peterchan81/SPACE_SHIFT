// SS-BUG-011 — 좌측 메뉴 "진행 중인 프로젝트": 실제 저장소의 미완료 프로젝트를 번호·이름·진행률로 보여주고,
// 누르면 마지막 저장 단계로 재개한다. 없으면 짧은 빈 안내.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpFrame(WidgetTester tester, SsProjectStore store, {Size size = const Size(1280, 720)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SsProjectStoreProvider.useForTesting(store);
  addTearDown(SsProjectStoreProvider.resetForTesting);
  await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, home: const SsStageScreen(stage: SsStage.finalResult)));
  await tester.pumpAndSettle();
}

Future<MemorySsProjectStore> _storeWithProjects() async {
  final store = MemorySsProjectStore();
  await store.save(SsProject.create(id: 'd', name: '거실 그리기', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1)));
  await store.save(
    SsProject.create(id: 'c', name: '안방 CAD', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 2)).moveTo(SsStage.cadEditor, now: DateTime(2026, 3, 1)),
  );
  await store.save(
    SsProject.create(id: 'done', name: '완료된 상가', sourceType: SsSourceType.imageTransform, now: DateTime(2026, 1, 3))
        .moveTo(SsStage.imageResult, now: DateTime(2026, 3, 5)),
  );
  return store;
}

void main() {
  testWidgets('진행 중 프로젝트를 번호·이름·진행률로 보여주고, 완료된 프로젝트는 빼고 최근 수정순이다', (tester) async {
    await _pumpFrame(tester, await _storeWithProjects());
    final list = find.byKey(const Key('ssNavCurrentProjectsList'));
    expect(find.byKey(const Key('ssNavCurrentProject_c')), findsOneWidget);
    expect(find.byKey(const Key('ssNavCurrentProject_d')), findsOneWidget);
    expect(find.byKey(const Key('ssNavCurrentProject_done')), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('ssNavCurrentProject_c')), matching: find.text('01')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('ssNavCurrentProject_d')), matching: find.text('02')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ssNavCurrentProjectPercent_c'))).data, '25%');
    expect(tester.widget<Text>(find.byKey(const Key('ssNavCurrentProjectPercent_d'))).data, '0%');
    expect(find.descendant(of: list, matching: find.byType(LinearProgressIndicator)), findsNWidgets(2));
  });

  testWidgets('진행 중 프로젝트를 누르면 마지막 저장 단계로 재개한다', (tester) async {
    final store = await _storeWithProjects();
    await _pumpFrame(tester, store);
    await tester.tap(find.byKey(const Key('ssNavCurrentProject_d')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssDrawScreen')), findsOneWidget, reason: '직접 그리기 단계에 저장된 프로젝트는 그 단계로 재개한다');
    expect(await store.lastOpened(), 'd');
  });

  testWidgets('프로젝트가 없으면 짧은 빈 안내를 보여준다', (tester) async {
    await _pumpFrame(tester, MemorySsProjectStore());
    expect(find.byKey(const Key('ssNavCurrentProjectsEmpty')), findsOneWidget);
  });

  testWidgets('640×480 창에서도 좌측 메뉴와 진행 중인 프로젝트가 넘치지 않는다', (tester) async {
    await _pumpFrame(tester, await _storeWithProjects(), size: const Size(640, 480));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ssNavCurrentProjectsLabel')), findsOneWidget);
  });
}
