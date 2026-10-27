// SS001-UI — 공통 프레임(lib/core/ss_router.dart)이 MASTER UI(Dark Navy·Neon·고정 좌측 메뉴, SsMasterTheme)
// 디자인을 쓰는지 검증한다. SS001·S1의 Route/메뉴 이동 기능 검증은 test/core/ss_router_test.dart가 그대로 맡는다.
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/theme/ss_master_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpStage(WidgetTester tester, SsStage stage) async {
    tester.view.physicalSize = const Size(2000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, initialRoute: stage.routeName));
    await tester.pumpAndSettle();
  }

  testWidgets('공통 프레임 배경은 MASTER 테마의 Dark Navy다', (tester) async {
    await pumpStage(tester, SsStage.home);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, SsMasterTheme.background);
  });

  testWidgets('상단 Header는 무지개 SS 로고 + SPACE SHIFT, 도움말·알림·프로필 아이콘(비활성)을 보인다', (tester) async {
    await pumpStage(tester, SsStage.home);
    expect(find.byKey(const Key('ssTopBar')), findsOneWidget);
    expect(find.text('SPACE SHIFT'), findsOneWidget);
    expect(find.text('SS'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('ssTopBarHelp'))).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byKey(const Key('ssTopBarNotifications'))).onPressed, isNull);
    // SS002 §5 — 프로필 아이콘은 로그아웃 메뉴(PopupMenuButton)로 동작한다(도움말·알림만 비활성).
    expect(find.byKey(const Key('ssTopBarProfile')), findsOneWidget);
    expect(tester.widget<PopupMenuButton<String>>(find.byKey(const Key('ssTopBarProfile'))).onSelected, isNotNull);
  });

  testWidgets('홈 단계는 홈·프로젝트·프로젝트 생성·설정만 보이고(저장/2D 등은 숨김), 홈이 선택 표시된다', (tester) async {
    await pumpStage(tester, SsStage.home);
    expect(find.byKey(const Key('ssNav_home')), findsOneWidget);
    expect(find.byKey(const Key('ssNav_projects')), findsOneWidget);
    expect(find.byKey(const Key('ssNav_createProject')), findsOneWidget);
    expect(find.byKey(const Key('ssNav_settings')), findsOneWidget);
    expect(find.byKey(const Key('ssNav_save')), findsNothing, reason: '쓸 수 없는 항목은 흐리게가 아니라 보이지 않는다');
    expect(find.byKey(const Key('ssNav_export')), findsNothing);
    expect(find.byKey(const Key('ssNav_view2d')), findsNothing);
    expect(find.byKey(const Key('ssNav_view3d')), findsNothing);
    expect(find.byKey(const Key('ssNav_currentProject')), findsNothing);
    expect(find.byKey(const Key('ssNavCurrentProjectsLabel')), findsNothing, reason: '진행 중인 프로젝트 영역은 작업 단계에서만');

    final homeRow = tester.widget<Container>(find.descendant(of: find.byKey(const Key('ssNav_home')), matching: find.byType(Container)).first);
    final homeDecoration = homeRow.decoration as BoxDecoration;
    expect(homeDecoration.gradient, isNotNull, reason: '현재 단계 메뉴 항목은 그라데이션 강조 상자로 선택 표시한다');

    final projectsRow = tester.widget<Container>(find.descendant(of: find.byKey(const Key('ssNav_projects')), matching: find.byType(Container)).first);
    expect((projectsRow.decoration as BoxDecoration).gradient, isNull, reason: '선택되지 않은 항목은 강조 상자가 없다');
  });

  testWidgets('평면도 업로드(작업 단계)는 2D·저장·내보내기 메뉴와 "진행 중인 프로젝트" 영역을 보여주고, 현재 프로젝트가 선택 표시된다', (tester) async {
    await pumpStage(tester, SsStage.floorPlanUpload);
    expect(find.byKey(const Key('ssNav_home')), findsOneWidget);
    expect(find.byKey(const Key('ssNav_currentProject')), findsOneWidget);
    expect(find.byKey(const Key('ssNav_save')), findsOneWidget);
    expect(find.byKey(const Key('ssNav_export')), findsOneWidget);
    expect(find.byKey(const Key('ssNav_view2d')), findsOneWidget);
    expect(find.byKey(const Key('ssNav_view3d')), findsNothing, reason: '평면도 업로드 단계는 아직 3D를 쓰지 않는다');
    expect(find.byKey(const Key('ssNavCurrentProjectsLabel')), findsOneWidget);
    expect(find.byKey(const Key('ssNavCurrentProjectsList')), findsOneWidget);

    final currentRow = tester.widget<Container>(
      find.descendant(of: find.byKey(const Key('ssNav_currentProject')), matching: find.byType(Container)).first,
    );
    expect((currentRow.decoration as BoxDecoration).gradient, isNotNull, reason: '작업 단계에서는 현재 프로젝트가 선택 표시된다');

    final homeRow = tester.widget<Container>(find.descendant(of: find.byKey(const Key('ssNav_home')), matching: find.byType(Container)).first);
    expect((homeRow.decoration as BoxDecoration).gradient, isNull);
  });
}
