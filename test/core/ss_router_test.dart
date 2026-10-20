// SS001 §4.2/§15/§16 — 단계 이름으로 화면이 열리고(기존 화면 재사용), 아직 없는 단계는 3초 법칙 머리말이 있는 공통 화면.
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/floor_plan_workspace_screen.dart';
import 'package:ason_space/screens/login_screen.dart';
import 'package:ason_space/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('모든 단계 Route가 열리고, 모르는 이름은 기존 Navigator 동작(null)', () {
    for (final s in SsStage.values) {
      expect(SsRouter.onGenerateRoute(RouteSettings(name: s.routeName)), isNotNull, reason: s.name);
    }
    expect(SsRouter.onGenerateRoute(const RouteSettings(name: '/unknown')), isNull);
  });

  test('이미 있는 화면은 그대로 쓴다(새로 만들지 않음) — 로그인, 평면도/CAD 작업 화면, 이미지 시작', () {
    expect(SsRouter.existing.keys, containsAll({SsStage.login, SsStage.floorPlanUpload, SsStage.cadEditor, SsStage.imageEditing}));
  });

  testWidgets('아직 없는 단계는 "무엇을 하는 화면인지·다음에 무엇을" 보이고, 좌측 메뉴는 단계에 맞게 켜진다', (tester) async {
    tester.view.physicalSize = const Size(2000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, initialRoute: SsStage.isoEditor.routeName));
    await tester.pumpAndSettle();
    expect(find.text('3D ISO 디자인'), findsOneWidget);
    expect(find.byKey(const Key('ssStageWhat')), findsOneWidget);
    expect(find.text('다음: ${SsStage.isoEditor.whatNext}'), findsOneWidget);
    expect(find.textContaining('SS013'), findsOneWidget);
    final save = tester.widget<Opacity>(find.ancestor(of: find.byKey(const Key('ssNav_view3d')), matching: find.byType(Opacity)).first);
    expect(save.opacity, 1);
  });

  testWidgets('로그인 Route는 기존 로그인 화면을 연다', (tester) async {
    tester.view.physicalSize = const Size(2000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, initialRoute: SsStage.login.routeName));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  group('SS001 보완(S1) — 좌측 메뉴 선택을 실제 화면 이동으로 연결', () {
    test('메뉴 항목별 이동 대상이 올바르다(홈/프로젝트/생성/현재 프로젝트/2D/3D/설정, 저장·내보내기는 화면 이동 아님)', () {
      SsStage stageOf(SsNavTarget? t) => (t as SsNavStageTarget).stage;
      expect(stageOf(SsNavigation.targetFor(SsNavItem.home, SsStage.isoEditor)), SsStage.home);
      expect(stageOf(SsNavigation.targetFor(SsNavItem.projects, SsStage.isoEditor)), SsStage.projectManagement);
      expect(stageOf(SsNavigation.targetFor(SsNavItem.createProject, SsStage.isoEditor)), SsStage.projectCreation);
      expect(stageOf(SsNavigation.targetFor(SsNavItem.currentProject, SsStage.cadEditor)), SsStage.cadEditor);
      expect(stageOf(SsNavigation.targetFor(SsNavItem.view2d, SsStage.isoEditor)), SsStage.cadEditor);
      expect(stageOf(SsNavigation.targetFor(SsNavItem.view3d, SsStage.cadEditor)), SsStage.isoEditor);
      expect(SsNavigation.targetFor(SsNavItem.settings, SsStage.home), isA<SsNavSettingsTarget>());
      expect(SsNavigation.targetFor(SsNavItem.save, SsStage.cadEditor), isNull);
      expect(SsNavigation.targetFor(SsNavItem.export, SsStage.cadEditor), isNull);
    });

    testWidgets('"홈" 메뉴를 선택하면 홈 화면으로 이동한다', (tester) async {
      tester.view.physicalSize = const Size(2000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, initialRoute: SsStage.isoEditor.routeName));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ssNav_home')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.home.title);
    });

    testWidgets('"2D" 메뉴를 선택하면 기존 CAD 편집 화면(FloorPlanWorkspaceScreen)으로 이동한다(새 화면을 만들지 않음)', (tester) async {
      tester.view.physicalSize = const Size(2000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, initialRoute: SsStage.isoEditor.routeName));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ssNav_view2d')));
      await tester.pumpAndSettle();
      expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
    });

    testWidgets('"설정" 메뉴를 선택하면 기존 SettingsScreen을 연다(재사용, 새로 만들지 않음)', (tester) async {
      tester.view.physicalSize = const Size(2000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, initialRoute: SsStage.home.routeName));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ssNav_settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.home.title);
    });

    testWidgets('"현재 프로젝트" 메뉴는 이미 있는 화면에 머문다(같은 단계로는 다시 이동하지 않음)', (tester) async {
      tester.view.physicalSize = const Size(2000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, initialRoute: SsStage.isoEditor.routeName));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ssNav_currentProject')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ssStageTitle')), findsOneWidget, reason: '새 화면이 쌓이지 않고 하나만 남는다');
      expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.isoEditor.title);
    });
  });
}
