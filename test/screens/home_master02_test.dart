// SS 수정 01 — 홈 화면 MASTER 02 원본 구성: 머리말 없음, 헤더 심볼·그라데이션 글자, 선택 메뉴 그라데이션,
// 시작 카드 3개 이동, 최근 프로젝트 4칸(0/2/5개·번호·날짜·⋮ 메뉴), 썸네일 예시 사진 금지, AI 예시 표시,
// 안내 카드 3개, 1672×941 한 화면, 여러 창 크기 넘침 없음.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/home_screen.dart';
import 'package:ason_space/screens/project_management_screen.dart';
import 'package:ason_space/screens/ss_recommendation_screen.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:ason_space/theme/ss_master_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _onePixelPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

Future<void> _pump(WidgetTester tester, SsProjectStore store, {Size size = const Size(1672, 941)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SsProjectStoreProvider.useForTesting(store);
  addTearDown(SsProjectStoreProvider.resetForTesting);
  await tester.pumpWidget(
    MaterialApp(onGenerateRoute: SsRouter.onGenerateRoute, home: SsStageScreen(stage: SsStage.home, child: HomeScreen(projectStore: store))),
  );
  await tester.pumpAndSettle();
}

Future<MemorySsProjectStore> _storeWith(int count) async {
  final store = MemorySsProjectStore();
  for (var i = 0; i < count; i++) {
    await store.save(SsProject.create(id: 'p$i', name: '프로젝트 $i', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1 + i)));
  }
  return store;
}

void main() {
  testWidgets('홈에는 번호 머리말·홈 제목·"시작 화면입니다"·"다음:" 안내가 없다', (tester) async {
    await _pump(tester, MemorySsProjectStore());
    expect(find.byKey(const Key('ssStageTitle')), findsNothing);
    expect(find.byKey(const Key('ssStageProjectNumberBox')), findsNothing);
    expect(find.textContaining('시작 화면입니다'), findsNothing);
    expect(find.textContaining('다음:'), findsNothing);
    expect(find.byKey(const Key('ssHomeHero')), findsOneWidget);
  });

  testWidgets('헤더는 공식 심볼 그림과 그라데이션 SPACE SHIFT 글자, 흰 원 사용자 아이콘을 쓴다', (tester) async {
    await _pump(tester, MemorySsProjectStore());
    final symbol = tester.widget<Image>(find.byKey(const Key('ssTopBarSymbol')));
    expect((symbol.image as AssetImage).assetName, 'assets/icons/space_shift_symbol.png');
    final topBarHeight = tester.getSize(find.byKey(const Key('ssTopBar'))).height;
    expect(symbol.height, closeTo(topBarHeight * 0.6, 0.01));
    final brand = find.byKey(const Key('ssTopBarBrand'));
    expect(tester.widget(brand), isA<ShaderMask>());
    expect(find.descendant(of: brand, matching: find.text('SPACE SHIFT')), findsOneWidget);
    expect(find.byKey(const Key('ssTopBarProfileCircle')), findsOneWidget);
  });

  testWidgets('선택된 홈 메뉴는 파랑→보라→분홍 그라데이션과 바깥 빛을 가진다', (tester) async {
    await _pump(tester, MemorySsProjectStore());
    final row = tester.widget<Container>(find.descendant(of: find.byKey(const Key('ssNav_home')), matching: find.byType(Container)).first);
    final deco = row.decoration as BoxDecoration;
    expect(deco.gradient, SsMasterTheme.selectedNavItem);
    expect((deco.gradient as LinearGradient).colors.length, 3);
    expect(deco.boxShadow, isNotEmpty);
    expect(tester.getSize(find.byKey(const Key('ssNavRail'))).width, lessThanOrEqualTo(190));
  });

  testWidgets('시작 카드 3개는 각각 프로젝트 생성으로 이동한다', (tester) async {
    await _pump(tester, MemorySsProjectStore());
    for (final type in SsSourceType.values) {
      await tester.tap(find.byKey(Key('ssHomeStartCard_${type.name}')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.projectCreation.title, reason: type.name);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('프로젝트 0개 — 점선 빈 칸 4개와 한 줄 안내', (tester) async {
    await _pump(tester, MemorySsProjectStore());
    expect(find.byKey(const Key('ssHomeEmptyProjects')), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('ssHomeRecentEmptySlot_$i')), findsOneWidget);
    }
  });

  testWidgets('프로젝트 2개 — 카드 2개(번호·날짜) + 빈 칸 2개, 칸 크기 같음', (tester) async {
    final store = await _storeWith(2);
    await _pump(tester, store);
    // 최근 수정순 — p1(1월 2일)이 01.
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeProjectNumber_p1'))).data, '01');
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeProjectNumber_p0'))).data, '02');
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeProjectDate_p1'))).data, '2026. 01. 02');
    expect(find.byKey(const Key('ssHomeRecentEmptySlot_2')), findsOneWidget);
    expect(find.byKey(const Key('ssHomeRecentEmptySlot_3')), findsOneWidget);
    final card = tester.getSize(find.byKey(const Key('ssHomeProjectCard_p1')));
    final empty = tester.getSize(find.byKey(const Key('ssHomeRecentEmptySlot_3')));
    expect(card.width, closeTo(empty.width, 1));
  });

  testWidgets('프로젝트 5개 — 4칸만 보이고 빈 칸은 없다', (tester) async {
    final store = await _storeWith(5);
    await _pump(tester, store);
    for (final id in ['p4', 'p3', 'p2', 'p1']) {
      expect(find.byKey(Key('ssHomeProjectCard_$id')), findsOneWidget);
    }
    expect(find.byKey(const Key('ssHomeProjectCard_p0')), findsNothing);
    expect(find.byKey(const Key('ssHomeRecentEmptySlot_3')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeProjectNumber_p4'))).data, '01');
  });

  testWidgets('⋮ 메뉴 — 이름 바꾸기 창으로 이름을 바꾼다', (tester) async {
    final store = await _storeWith(1);
    await _pump(tester, store);
    await tester.tap(find.byKey(const Key('ssHomeProjectMenu_p0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssHomeProjectMenuRename')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssProjectRenameDialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ssProjectRenameField')), '새 이름');
    await tester.tap(find.byKey(const Key('ssProjectRenameSave')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeProjectName_p0'))).data, '새 이름');
    expect((await store.load('p0'))!.info.name, '새 이름');
  });

  testWidgets('⋮ 메뉴 — 열기는 저장된 단계로, 프로젝트 관리에서 보기는 관리 화면으로', (tester) async {
    final store = await _storeWith(1);
    await _pump(tester, store);
    await tester.tap(find.byKey(const Key('ssHomeProjectMenu_p0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssHomeProjectMenuManage')));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectManagementScreen), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ssHomeProjectMenu_p0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssHomeProjectMenuOpen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssDrawScreen')), findsOneWidget);
  });

  testWidgets('썸네일 — 저장된 이미지가 없으면 자리 그림(예시 사진 아님), 있으면 그 이미지', (tester) async {
    final store = MemorySsProjectStore();
    await store.save(SsProject.create(id: 'plain', name: '빈', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1)));
    await store.save(
      SsProject.create(id: 'pic', name: '사진', sourceType: SsSourceType.imageTransform, now: DateTime(2026, 1, 2))
          .withSource({'imageBase64': _onePixelPng}, now: DateTime(2026, 1, 2)),
    );
    await _pump(tester, store);
    final plainCard = find.byKey(const Key('ssHomeProjectCard_plain'));
    expect(find.byKey(const Key('ssHomeProjectThumbPlaceholder_plain')), findsOneWidget);
    expect(find.descendant(of: plainCard, matching: find.byType(Image)), findsNothing, reason: '예시 방 사진을 사용자 프로젝트처럼 쓰지 않는다');
    final picImage = tester.widget<Image>(find.byKey(const Key('ssHomeProjectThumbImage_pic')));
    expect(picImage.image, isA<MemoryImage>());
  });

  testWidgets('AI 결과가 없으면 예시 그림에 "예시" 표시, 결과보기는 결과 없음 안내', (tester) async {
    await _pump(tester, MemorySsProjectStore());
    expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('ssHomeAiExampleBadge')), matching: find.byType(Text))).data, '예시');
    expect((tester.widget<Image>(find.byKey(const Key('ssHomeAiExamplePlan'))).image as AssetImage).assetName, HomeScreen.aiPlanExampleAsset);
    expect((tester.widget<Image>(find.byKey(const Key('ssHomeAiExample3d'))).image as AssetImage).assetName, HomeScreen.ai3dExampleAsset);
    expect(find.byKey(const Key('ssHomeAiPreviewOpen')), findsNothing);
    await tester.tap(find.byKey(const Key('ssHomeAiPreviewNoResult')));
    await tester.pump();
    expect(find.byKey(const Key('ssHomeAiNoResultMessage')), findsOneWidget);
  });

  testWidgets('AI 결과가 있으면 예시 표시 없이 결과보기가 그 프로젝트에 연결된다', (tester) async {
    final store = MemorySsProjectStore();
    await store.save(
      SsProject.create(id: 'done', name: '상가', sourceType: SsSourceType.imageTransform, now: DateTime(2026, 2, 1))
          .withSource({'imageBase64': _onePixelPng}, now: DateTime(2026, 2, 1))
          .withStageData(SsDataSlot.renderData, {'imageBase64': _onePixelPng}, label: 'AI 렌더링', now: DateTime(2026, 2, 2)),
    );
    await _pump(tester, store);
    expect(find.byKey(const Key('ssHomeAiExampleBadge')), findsNothing);
    expect(find.byKey(const Key('ssHomeAiResult')), findsOneWidget);
    expect(find.byKey(const Key('ssHomeAiResultImage')), findsOneWidget);
    expect(tester.widget<TextButton>(find.byKey(const Key('ssHomeAiPreviewOpen'))).onPressed, isNotNull);
  });

  testWidgets('안내 카드 3개 — 알약 버튼, 추천은 원본 문구와 "예시" 표시, 추천 화면 연결', (tester) async {
    await _pump(tester, MemorySsProjectStore());
    for (final id in ['guide', 'recommend', 'tips']) {
      expect(find.byKey(Key('ssHomeTipCard_$id')), findsOneWidget);
      final button = tester.widget<TextButton>(find.byKey(Key('ssHomeTip_$id')));
      expect(button.onPressed, isNotNull);
      expect(button.style?.backgroundColor?.resolve(<WidgetState>{}), isNotNull, reason: '$id 버튼은 색이 채워진 알약');
    }
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeTipDesc_recommend'))).data, 'AI가 제안하는 인테리어 스타일을 확인해보세요.');
    expect(find.byKey(const Key('ssHomeRecommendExampleBadge')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ssHomeTip_recommend')));
    await tester.pumpAndSettle();
    expect(find.byType(SsRecommendationScreen), findsOneWidget);
  });

  for (final size in const [Size(1672, 941), Size(1280, 800)]) {
    testWidgets('${size.width.toInt()}×${size.height.toInt()} — 스크롤 없이 안내 카드까지 한 화면에 보인다', (tester) async {
      await _pump(tester, await _storeWith(3), size: size);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ssHomeFit')), findsOneWidget);
      expect(find.byKey(const Key('ssHomeScroll')), findsNothing);
      for (final id in ['guide', 'recommend', 'tips']) {
        expect(tester.getBottomLeft(find.byKey(Key('ssHomeTipCard_$id'))).dy, lessThanOrEqualTo(size.height));
      }
    });
  }

  for (final size in const [Size(1280, 720), Size(1024, 768), Size(800, 600), Size(640, 480), Size(800, 1280)]) {
    testWidgets('${size.width.toInt()}×${size.height.toInt()} — 넘침 없이 같은 구성이 모두 있다', (tester) async {
      await _pump(tester, await _storeWith(2), size: size);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ssHomeHero')), findsOneWidget);
      for (final type in SsSourceType.values) {
        expect(find.byKey(Key('ssHomeStartCard_${type.name}')), findsOneWidget);
      }
      expect(find.byKey(const Key('ssHomeRecentProjectsList')), findsOneWidget);
      expect(find.byKey(const Key('ssHomeAiPreview')), findsOneWidget);
      for (final id in ['guide', 'recommend', 'tips']) {
        expect(find.byKey(Key('ssHomeTipCard_$id')), findsOneWidget);
      }
    });
  }
}
