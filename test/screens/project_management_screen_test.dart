// SS004 — MASTER UI 3(프로젝트 관리): 카드·상태·진행률, 검색, 열기(마지막 단계 복원), 이어서 하기, 삭제 확인, 복원 실패.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/project_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 목록은 정상이지만 broken이면 load가 null(손상된 파일 흉내).
class _BreakableStore implements SsProjectStore {
  final MemorySsProjectStore inner = MemorySsProjectStore();
  bool broken = false;

  @override
  Future<List<String>> list() => inner.list();

  @override
  Future<SsProject?> load(String projectId) async => broken ? null : inner.load(projectId);

  @override
  Future<void> save(SsProject project) => inner.save(project);

  @override
  Future<void> setLastOpened(String projectId) => inner.setLastOpened(projectId);

  @override
  Future<String?> lastOpened() => inner.lastOpened();
}

SsProject _a() => SsProject.create(id: 'a', name: '우리집 리모델링', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1)).moveTo(SsStage.isoEditor, now: DateTime(2026, 3, 1));
SsProject _b() => SsProject.create(id: 'b', name: '상가 인테리어', sourceType: SsSourceType.imageTransform, now: DateTime(2026, 2, 1));

Future<void> _pump(WidgetTester tester, SsProjectStore store) async {
  tester.view.physicalSize = const Size(2000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, home: Scaffold(body: ProjectManagementScreen(projectStore: store))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('카드에 상태·진행률을 보여주고 검색으로 거른다', (tester) async {
    final store = MemorySsProjectStore();
    await store.save(_a());
    await store.save(_b());
    await _pump(tester, store);

    expect(find.byKey(const Key('ssProjectsCreateCard')), findsOneWidget);
    expect(find.byKey(const Key('ssProjectCard_a')), findsOneWidget);
    expect(find.byKey(const Key('ssProjectCard_b')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ssProjectStatus_a'))).data, '진행 중');
    expect(tester.widget<Text>(find.byKey(const Key('ssProjectStatus_b'))).data, '초안');
    expect(tester.widget<Text>(find.byKey(const Key('ssProjectProgress_a'))).data, '50%');
    expect(tester.widget<Text>(find.byKey(const Key('ssProjectProgress_b'))).data, '0%');

    await tester.enterText(find.byKey(const Key('ssProjectsSearch')), '상가');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssProjectCard_a')), findsNothing);
    expect(find.byKey(const Key('ssProjectCard_b')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ssProjectsSearch')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssProjectsNoResult')), findsOneWidget);
  });

  testWidgets('프로젝트를 열면 저장된 마지막 단계로 복원하고 마지막 작업으로 기록한다', (tester) async {
    final store = MemorySsProjectStore();
    await store.save(_a());
    await _pump(tester, store);

    await tester.tap(find.byKey(const Key('ssProjectCard_a')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.isoEditor.title);
    expect(await store.lastOpened(), 'a');
  });

  testWidgets('앱을 다시 열면 마지막 작업 프로젝트를 이어서 할 수 있다', (tester) async {
    final store = MemorySsProjectStore();
    await store.save(_a());
    await store.save(_b());
    await store.setLastOpened('a');
    await _pump(tester, store);

    expect(find.byKey(const Key('ssProjectsResume')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ssProjectsResumeButton')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.isoEditor.title);
  });

  testWidgets('삭제는 확인 창을 거친다 — 취소하면 남고, 확인하면 지워진다', (tester) async {
    final store = MemorySsProjectStore();
    await store.save(_a());
    await _pump(tester, store);

    await tester.tap(find.byKey(const Key('ssProjectMenu_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssProjectMenuDelete_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssProjectDeleteDialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ssProjectDeleteCancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssProjectCard_a')), findsOneWidget);
    expect(await store.list(), contains('a'));

    await tester.tap(find.byKey(const Key('ssProjectMenu_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssProjectMenuDelete_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssProjectDeleteConfirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssProjectCard_a')), findsNothing);
    expect(await store.list(), isEmpty);
  });

  testWidgets('저장 파일을 복원하지 못하면 오류를 알리고 화면을 바꾸지 않는다', (tester) async {
    final store = _BreakableStore();
    await store.save(_a());
    await _pump(tester, store);

    store.broken = true;
    await tester.tap(find.byKey(const Key('ssProjectCard_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssProjectOpenError')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.projectManagement.title);
  });
}
