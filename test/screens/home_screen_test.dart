// SS003 — MASTER UI 2(홈 화면): 3가지 시작 카드, 최근/진행 중 프로젝트, 빈 상태/로딩/오류, 재개 흐름.
import 'dart:io';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// list()를 한 번 실패시키고(파일 시스템 오류 흉내), 그 다음부터는 정상 동작하는
/// 가짜 저장소 — "다시 시도" 버튼이 실제로 다시 불러오는지 검증한다.
class _FlakyThenOkStore implements SsProjectStore {
  bool _first = true;
  final MemorySsProjectStore _inner = MemorySsProjectStore();

  @override
  Future<List<String>> list() async {
    if (_first) {
      _first = false;
      throw const FileSystemException('목록을 읽을 수 없습니다(시험)');
    }
    return _inner.list();
  }

  @override
  Future<SsProject?> load(String projectId) => _inner.load(projectId);

  @override
  Future<void> save(SsProject project) => _inner.save(project);

  @override
  Future<void> setLastOpened(String projectId) => _inner.setLastOpened(projectId);

  @override
  Future<String?> lastOpened() => _inner.lastOpened();
}

Future<void> _pumpHome(WidgetTester tester, SsProjectStore store) async {
  tester.view.physicalSize = const Size(2000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, home: HomeScreen(projectStore: store)));
}

void main() {
  testWidgets('프로젝트가 없으면 빈 상태를 보여준다(로딩 표시는 사라진다)', (tester) async {
    await _pumpHome(tester, MemorySsProjectStore());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssHomeEmptyProjects')), findsOneWidget);
    expect(find.byKey(const Key('ssHomeLoading')), findsNothing);
    expect(find.byKey(const Key('ssHomeProjectsError')), findsNothing);
  });

  testWidgets('목록을 읽지 못하면 오류와 다시 시도 버튼을 보여주고, 다시 시도하면 정상 목록을 불러온다', (tester) async {
    final store = _FlakyThenOkStore();
    await store.save(SsProject.create(id: 'p1', name: '거실', sourceType: SsSourceType.directDraw));

    await _pumpHome(tester, store);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssHomeProjectsError')), findsOneWidget);
    expect(find.byKey(const Key('ssHomeRetryButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssHomeRetryButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssHomeProjectsError')), findsNothing);
    expect(find.byKey(const Key('ssHomeRecentProjectsList')), findsOneWidget);
    expect(find.byKey(const Key('ssHomeProjectCard_p1')), findsOneWidget);
  });

  testWidgets('최근 프로젝트는 이름·상태·수정일을 보여주고, AI 결과가 있는 프로젝트는 미리보기에 연결된다', (tester) async {
    final store = MemorySsProjectStore();
    final inProgress = SsProject.create(id: 'inprog', name: '우리집', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1));
    final done = SsProject.create(id: 'done', name: '상가', sourceType: SsSourceType.imageTransform, now: DateTime(2026, 2, 1))
        .withSource({'photo': 'a.jpg'}, now: DateTime(2026, 2, 1))
        .withStageData(SsDataSlot.renderData, {'img': 'r.png'}, label: 'AI 렌더링', now: DateTime(2026, 2, 2))
        .moveTo(SsStage.imageResult, now: DateTime(2026, 2, 2));
    await store.save(inProgress);
    await store.save(done);

    await _pumpHome(tester, store);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssHomeProjectCard_inprog')), findsOneWidget);
    expect(find.byKey(const Key('ssHomeProjectCard_done')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeProjectStatus_inprog'))).data, '진행중');
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeProjectStatus_done'))).data, '완료');

    // AI 미리보기는 렌더링 결과가 있는 프로젝트("상가")에 연결된다.
    expect(find.byKey(const Key('ssHomeAiPreviewOpen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssHomeProjectCard_inprog')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssStageTitle')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data,
      SsStage.directDrawing.title,
      reason: '직접 그리기 프로젝트를 고르면 저장된 단계(직접 그리기)에서 이어서 연다',
    );
  });

  testWidgets('3가지 시작 카드는 각자의 sourceType을 들고 프로젝트 생성 흐름으로 연결된다', (tester) async {
    await _pumpHome(tester, MemorySsProjectStore());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssHomeStartCard_floorPlanUpload')), findsOneWidget);
    expect(find.byKey(const Key('ssHomeStartCard_directDraw')), findsOneWidget);
    expect(find.byKey(const Key('ssHomeStartCard_imageTransform')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssHomeStartCard_directDraw')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data,
      SsStage.projectCreation.title,
      reason: '시작 카드는 프로젝트 생성 단계로 연결된다(SS004이 sourceType 인자를 받아 처리)',
    );
  });
}
