// SS-수정003·SS-BUG-011 — 홈 히어로(MASTER UI 2)와 안내 카드 3개(가이드·추천·팁) 버튼 동작.
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/home_screen.dart';
import 'package:ason_space/screens/ss_guide_screen.dart';
import 'package:ason_space/screens/ss_recommendation_screen.dart';
import 'package:ason_space/screens/ss_tips_screen.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpHome(WidgetTester tester, {Size size = const Size(1280, 720)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemorySsProjectStore();
  SsProjectStoreProvider.useForTesting(store);
  addTearDown(SsProjectStoreProvider.resetForTesting);
  await tester.pumpWidget(
    MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, home: SsStageScreen(stage: SsStage.home, child: HomeScreen(projectStore: store))),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('홈은 머리말 대신 MASTER 히어로 문구를 보인다', (tester) async {
    await _pumpHome(tester);
    expect(find.byKey(const Key('ssHomeHero')), findsOneWidget);
    expect(find.byKey(const Key('ssStageTitle')), findsNothing);
    expect(find.textContaining('다음:'), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeHeroBadge'))).data, 'SPACE SHIFT');
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeHeroTitle1'))).data, '공간의 변화를 만드는');
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeHeroTitle2'))).data, '새로운 가능성,');
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeHeroBrand'))).data, 'SPACE SHIFT');
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeHeroDescription'))).data, 'AI와 함께, 당신의 공간을 새롭게 디자인하세요.');
  });

  testWidgets('안내 카드 버튼 3개는 모두 누를 수 있다', (tester) async {
    await _pumpHome(tester);
    for (final id in ['guide', 'recommend', 'tips']) {
      expect(tester.widget<TextButton>(find.byKey(Key('ssHomeTip_$id'))).onPressed, isNotNull, reason: id);
    }
  });

  testWidgets('가이드 보기는 3가지 시작 방식과 단계 흐름을 보여주고, 바로 시작하면 프로젝트 생성으로 간다', (tester) async {
    await _pumpHome(tester);
    await _tapVisible(tester, find.byKey(const Key('ssHomeTip_guide')));
    expect(find.byType(SsGuideScreen), findsOneWidget);
    for (final type in SsSourceType.values) {
      expect(find.byKey(Key('ssGuideFlow_${type.name}')), findsOneWidget);
      expect(find.byKey(Key('ssGuideStep_${type.name}_0')), findsOneWidget);
    }
    await _tapVisible(tester, find.byKey(const Key('ssGuideStart_directDraw')));
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.projectCreation.title);
  });

  testWidgets('추천 보기는 스타일 목록을 보여주고, 하나를 고르면 이미지 변환 시작 흐름(프로젝트 생성)으로 간다', (tester) async {
    await _pumpHome(tester);
    await _tapVisible(tester, find.byKey(const Key('ssHomeTip_recommend')));
    expect(find.byType(SsRecommendationScreen), findsOneWidget);
    expect(find.byKey(const Key('ssRecommendStyle_modern')), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('ssRecommendStyle_modern')));
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.projectCreation.title);
  });

  testWidgets('팁 보기는 팁 목록을 연다', (tester) async {
    await _pumpHome(tester);
    await _tapVisible(tester, find.byKey(const Key('ssHomeTip_tips')));
    expect(find.byType(SsTipsScreen), findsOneWidget);
    expect(find.byKey(const Key('ssTip_0')), findsOneWidget);
  });

  testWidgets('640×480 창에서도 홈·가이드·추천·팁 화면이 넘치지 않는다', (tester) async {
    await _pumpHome(tester, size: const Size(640, 480));
    expect(tester.takeException(), isNull);
    await _tapVisible(tester, find.byKey(const Key('ssHomeTip_guide')));
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('ssHomeTip_recommend')));
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('ssHomeTip_tips')));
    expect(tester.takeException(), isNull);
  });
}
