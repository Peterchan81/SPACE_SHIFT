// SS-수정003 4차 — 작업 화면 머리글 MASTER 05: 프로젝트 번호·이름·✎ 이름 바꾸기(저장·목록 반영·검사).
import 'dart:convert';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/core/ss_stage_guide.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/screens/project_management_screen.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:ason_space/widgets/ss_nav_current_projects.dart';
import 'package:ason_space/widgets/ss_project_rename_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SsProject _older() => SsProject.create(id: 'a', name: '우리집 리모델링', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
SsProject _newer() => SsProject.create(id: 'b', name: '상가 인테리어', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 2, 1));

Future<MemorySsProjectStore> _store() async {
  final s = MemorySsProjectStore();
  await s.save(_older());
  await s.save(_newer());
  return s;
}

void _view(WidgetTester tester, [Size size = const Size(1280, 720)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 기존 프로젝트 관리 테스트와 같은 3D ISO 편집 단계 프로젝트(빈 CAD — 3D 위젯은 마운트되지 않는다).
SsProject _isoProject() => SsProject.create(id: 'a', name: '우리집 리모델링', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1))
    .withStageData(
      SsDataSlot.cadData,
      {
        'kind': 'ssCadScene',
        'scene': const SsCadScene(plan: CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 1000, walls: [], openings: [], rooms: [], warnings: [])).toJson(),
      },
      label: 'CAD 완료',
      now: DateTime(2026, 2, 1),
    )
    .moveTo(SsStage.isoEditor, now: DateTime(2026, 3, 1));

void main() {
  test('withName은 이름만 바꾸고 저장 형식·다른 칸은 그대로다', () {
    final before = _isoProject();
    final after = before.withName('새 이름');
    expect(after.info.name, '새 이름');
    final expected = before.toJson();
    (expected['projectInfo'] as Map<String, Object?>)['name'] = '새 이름';
    expect(jsonEncode(after.toJson()), jsonEncode(expected));
  });

  test('Route 인자에서 프로젝트 id를 찾는다', () {
    expect(SsStageHeader.projectIdFromArguments('a'), 'a');
    expect(SsStageHeader.projectIdFromArguments({'projectId': 'b', 'wallId': 'w1'}), 'b');
    expect(SsStageHeader.projectIdFromArguments(SsSourceType.directDraw), isNull);
    expect(SsStageHeader.projectIdFromArguments(null), isNull);
    expect(SsStageHeader.projectIdFromArguments(''), isNull);
  });

  testWidgets('프로젝트를 연 머리글은 번호 상자·이름·연필·이 단계 안내 한 줄을 보인다', (tester) async {
    _view(tester);
    final store = await _store();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SsStageHeader(stage: SsStage.floorPlanUpload, projectId: 'a', projectStore: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 최근 수정순 목록 번호 — b(2월)가 01, a(1월)가 02.
    expect(tester.widget<Text>(find.byKey(const Key('ssStageProjectNumber'))).data, '02');
    expect(tester.widget<Text>(find.byKey(const Key('ssStageProjectName'))).data, '우리집 리모델링');
    expect(find.byKey(const Key('ssStageProjectRename')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ssStageWhat'))).data, SsStageGuide.sentenceFor(SsStage.floorPlanUpload));
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.floorPlanUpload.title);
    // 번호 상자는 이름 왼쪽, 안내는 이름 아래.
    expect(tester.getTopLeft(find.byKey(const Key('ssStageProjectNumberBox'))).dx, lessThan(tester.getTopLeft(find.byKey(const Key('ssStageProjectName'))).dx));
    expect(tester.getTopLeft(find.byKey(const Key('ssStageWhat'))).dy, greaterThan(tester.getTopLeft(find.byKey(const Key('ssStageProjectName'))).dy));
  });

  testWidgets('Route 인자의 프로젝트를 읽어 머리글에 보인다', (tester) async {
    _view(tester);
    final store = await _store();
    SsProjectStoreProvider.useForTesting(store);
    addTearDown(SsProjectStoreProvider.resetForTesting);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('go'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(arguments: 'b'),
                    builder: (_) => const Scaffold(body: SsStageHeader(stage: SsStage.floorPlanReview)),
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
    expect(tester.widget<Text>(find.byKey(const Key('ssStageProjectNumber'))).data, '01');
    expect(tester.widget<Text>(find.byKey(const Key('ssStageProjectName'))).data, '상가 인테리어');
  });

  testWidgets('프로젝트가 없는 머리말은 지금 그대로다', (tester) async {
    _view(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SsStageHeader(stage: SsStage.floorPlanReview))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssStageProjectName')), findsNothing);
    expect(find.byKey(const Key('ssStageProjectRename')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.floorPlanReview.title);
  });

  testWidgets('이름 바꾸기 — 빈 이름·30자 초과는 거부, 저장하면 저장소와 진행 중 목록에 바로 반영', (tester) async {
    _view(tester);
    final store = await _store();
    final before = (await store.load('a'))!;
    final revisionBefore = SsProjectRenames.revision.value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SsStageHeader(stage: SsStage.floorPlanUpload, projectId: 'a', projectStore: store),
              SizedBox(width: 236, height: 300, child: SsNavCurrentProjects(projectStore: store)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ssStageProjectRename')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssProjectRenameDialog')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ssProjectRenameField')), '   ');
    await tester.tap(find.byKey(const Key('ssProjectRenameSave')));
    await tester.pumpAndSettle();
    expect(find.text('프로젝트 이름을 입력하세요.'), findsOneWidget);
    expect(find.byKey(const Key('ssProjectRenameDialog')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ssProjectRenameField')), 'x' * 31);
    await tester.tap(find.byKey(const Key('ssProjectRenameSave')));
    await tester.pumpAndSettle();
    expect(find.text('프로젝트 이름은 30자 이내로 입력하세요.'), findsOneWidget);
    expect(find.byKey(const Key('ssProjectRenameDialog')), findsOneWidget);
    expect((await store.load('a'))!.info.name, '우리집 리모델링');

    await tester.enterText(find.byKey(const Key('ssProjectRenameField')), '  새 이름  ');
    await tester.tap(find.byKey(const Key('ssProjectRenameSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssProjectRenameDialog')), findsNothing);

    final after = (await store.load('a'))!;
    expect(after.info.name, '새 이름');
    final expected = before.toJson();
    (expected['projectInfo'] as Map<String, Object?>)['name'] = '새 이름';
    expect(jsonEncode(after.toJson()), jsonEncode(expected), reason: '이름 칸만 바뀐다');
    expect(SsProjectRenames.revision.value, greaterThan(revisionBefore));

    expect(tester.widget<Text>(find.byKey(const Key('ssStageProjectName'))).data, '새 이름');
    expect(find.descendant(of: find.byKey(const Key('ssNavCurrentProject_a')), matching: find.text('새 이름')), findsOneWidget);
  });

  testWidgets('취소하면 이름이 바뀌지 않는다', (tester) async {
    _view(tester);
    final store = await _store();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SsStageHeader(stage: SsStage.floorPlanUpload, projectId: 'a', projectStore: store))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssStageProjectRename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ssProjectRenameField')), '다른 이름');
    await tester.tap(find.byKey(const Key('ssProjectRenameCancel')));
    await tester.pumpAndSettle();
    expect((await store.load('a'))!.info.name, '우리집 리모델링');
    expect(tester.widget<Text>(find.byKey(const Key('ssStageProjectName'))).data, '우리집 리모델링');
  });

  testWidgets('renameSsProject는 규칙에 맞지 않는 이름을 거부한다', (tester) async {
    final store = await _store();
    await expectLater(renameSsProject(store, 'a', ''), throwsArgumentError);
    await expectLater(renameSsProject(store, 'a', 'x' * 31), throwsArgumentError);
    expect(await renameSsProject(store, 'zzz', '이름'), isNull);
    final ok = await renameSsProject(store, 'a', 'x' * 30);
    expect(ok!.info.name, 'x' * 30);
  });

  testWidgets('프로젝트 관리에서 연 작업 화면에서 이름을 바꾸면 돌아온 목록 카드에도 반영된다', (tester) async {
    _view(tester, const Size(2000, 1200));
    final store = MemorySsProjectStore();
    await store.save(_isoProject());
    SsProjectStoreProvider.useForTesting(store);
    addTearDown(SsProjectStoreProvider.resetForTesting);
    await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, home: Scaffold(body: ProjectManagementScreen(projectStore: store))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ssProjectCard_a')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.isoEditor.title);
    expect(tester.widget<Text>(find.byKey(const Key('ssStageProjectNumber'))).data, '01');
    expect(tester.widget<Text>(find.byKey(const Key('ssStageProjectName'))).data, '우리집 리모델링');

    await tester.tap(find.byKey(const Key('ssStageProjectRename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ssProjectRenameField')), '바뀐 이름');
    await tester.tap(find.byKey(const Key('ssProjectRenameSave')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ssStageProjectName'))).data, '바뀐 이름');
    expect(find.descendant(of: find.byKey(const Key('ssNavCurrentProject_a')), matching: find.text('바뀐 이름')), findsOneWidget);

    Navigator.of(tester.element(find.byKey(const Key('ssStageProjectName')))).pop();
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('ssProjectCard_a')), matching: find.text('바뀐 이름')), findsOneWidget);
    expect((await store.load('a'))!.info.name, '바뀐 이름');
  });
}
