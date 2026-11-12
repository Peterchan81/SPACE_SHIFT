// SS-BUG-011 — 상단 도움말 아이콘은 가이드 화면을, 알림 아이콘은 실제 저장소 최근 활동만 보여주는 알림 패널을 연다.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/ss_guide_screen.dart';
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

void main() {
  testWidgets('도움말 아이콘을 누르면 가이드 화면이 열린다', (tester) async {
    await _pumpFrame(tester, MemorySsProjectStore());
    await tester.tap(find.byKey(const Key('ssTopBarHelp')));
    await tester.pumpAndSettle();
    expect(find.byType(SsGuideScreen), findsOneWidget);
  });

  testWidgets('프로젝트가 없으면 알림 패널은 "새 알림이 없습니다"를 보여주고 닫을 수 있다', (tester) async {
    await _pumpFrame(tester, MemorySsProjectStore());
    await tester.tap(find.byKey(const Key('ssTopBarNotifications')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssNotificationsPanel')), findsOneWidget);
    expect(find.text('새 알림이 없습니다'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ssNotificationsClose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssNotificationsPanel')), findsNothing);
  });

  testWidgets('알림 패널은 실제 저장소의 최근 수정 프로젝트와 그 단계만 보여준다', (tester) async {
    final store = MemorySsProjectStore();
    await store.save(
      SsProject.create(id: 'p1', name: '거실 리모델링', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1)).moveTo(SsStage.cadEditor, now: DateTime(2026, 3, 2)),
    );
    await _pumpFrame(tester, store, size: const Size(640, 480));
    await tester.tap(find.byKey(const Key('ssTopBarNotifications')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('ssNotificationsPanel'));
    expect(panel, findsOneWidget);
    expect(find.byKey(const Key('ssNotification_p1')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('거실 리모델링')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.textContaining(SsStage.cadEditor.title)), findsOneWidget);
    expect(find.text('새 알림이 없습니다'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
