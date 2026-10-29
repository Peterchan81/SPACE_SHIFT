// SS004 — MASTER UI 4(프로젝트 생성): 이름·시작 방식 검사, 정확히 하나의 FLOW로 생성, 저장 실패 처리.
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/project_creation_screen.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, SsProjectStore store, {SsSourceType? routeArg}) async {
  tester.view.physicalSize = const Size(2000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // 생성 후 Route로 열리는 첫 단계 화면(예: 직접 그리기)도 같은 저장소를 쓰게 한다.
  SsProjectStoreProvider.useForTesting(store);
  addTearDown(SsProjectStoreProvider.resetForTesting);
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: SsRouter.onGenerateRoute,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('go'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  settings: RouteSettings(arguments: routeArg),
                  builder: (_) => Scaffold(body: ProjectCreationScreen(projectStore: store)),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('go')));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('ssCreateSubmit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ssCreateSubmit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('이름과 시작 방식이 없으면 안내만 하고 만들지 않는다', (tester) async {
    final store = MemorySsProjectStore();
    await _pump(tester, store);
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.projectCreation.title);

    await _submit(tester);
    expect(find.text('프로젝트 이름을 입력하세요.'), findsOneWidget);
    expect(find.byKey(const Key('ssCreateTypeError')), findsOneWidget);
    expect(await store.list(), isEmpty);
  });

  testWidgets('홈에서 넘긴 sourceType이 미리 선택되고, 그 FLOW의 첫 단계로 생성·이동한다', (tester) async {
    final store = MemorySsProjectStore();
    await _pump(tester, store, routeArg: SsSourceType.directDraw);
    expect(find.byKey(const Key('ssCreateTypeSelected_directDraw')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ssCreateName')), '우리집');
    await _submit(tester);

    // SS005부터 직접 그리기 단계는 MASTER UI 4-1 편집기(단계 제목 헤더 없음)로 열린다.
    expect(find.byKey(const Key('ssDrawScreen')), findsOneWidget);
    final ids = await store.list();
    expect(ids, hasLength(1));
    final saved = await store.load(ids.single);
    expect(saved!.info.name, '우리집');
    expect(saved.sourceType, SsSourceType.directDraw);
    expect(saved.currentStage, SsStage.directDrawing);
    expect(await store.lastOpened(), ids.single);
  });

  testWidgets('저장에 실패하면 오류를 보이고 입력을 유지하며, 다시 누르면 생성된다', (tester) async {
    final store = MemorySsProjectStore();
    await _pump(tester, store);

    await tester.enterText(find.byKey(const Key('ssCreateName')), '상가');
    await tester.ensureVisible(find.byKey(const Key('ssCreateType_directDraw')));
    await tester.tap(find.byKey(const Key('ssCreateType_directDraw')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssCreateTypeSelected_directDraw')), findsOneWidget);

    store.failNextSave = true;
    await _submit(tester);
    expect(find.byKey(const Key('ssCreateSaveError')), findsOneWidget);
    expect(await store.list(), isEmpty);

    await _submit(tester);
    expect(find.byKey(const Key('ssDrawScreen')), findsOneWidget);
    final ids = await store.list();
    expect(ids, hasLength(1));
    expect((await store.load(ids.single))!.sourceType, SsSourceType.directDraw);
  });
}
