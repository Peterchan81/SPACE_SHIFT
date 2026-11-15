// SS-수정003 2차 — 홈 MASTER 02 사진 4개, 1024·800·640 폭 넘침 없음, 1280 배치 유지.
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/home_screen.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpHome(WidgetTester tester, Size size) async {
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

String _assetOf(WidgetTester tester, String key) {
  final image = tester.widget<Image>(find.byKey(Key(key)));
  return (image.image as AssetImage).assetName;
}

void main() {
  testWidgets('홈에 MASTER 02 사진 4개(상단 배경 + 시작 카드 3개)가 그려진다', (tester) async {
    await _pumpHome(tester, const Size(1280, 720));
    expect(_assetOf(tester, 'ssHomeHeroImage'), 'assets/images/home_hero.png');
    expect(find.byKey(const Key('ssHomeHeroShade')), findsOneWidget);
    expect(_assetOf(tester, 'ssHomeStartCardImage_floorPlanUpload'), 'assets/images/home_card_upload.png');
    expect(_assetOf(tester, 'ssHomeStartCardImage_directDraw'), 'assets/images/home_card_draw.png');
    expect(_assetOf(tester, 'ssHomeStartCardImage_imageTransform'), 'assets/images/home_card_image.png');
    expect(tester.widget<Image>(find.byKey(const Key('ssHomeHeroImage'))).fit, BoxFit.cover);
    // 글자·로고 문구는 그대로다.
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeHeroTitle1'))).data, '공간의 변화를 만드는');
    expect(tester.widget<Text>(find.byKey(const Key('ssHomeHeroBrand'))).data, 'SPACE SHIFT');
  });

  testWidgets('1280×720에서는 시작 카드 3개가 한 줄이고, 최근 프로젝트와 AI 분석 미리보기가 나란히 있다', (tester) async {
    await _pumpHome(tester, const Size(1280, 720));
    expect(tester.takeException(), isNull);
    final a = tester.getTopLeft(find.byKey(const Key('ssHomeStartCard_floorPlanUpload')));
    final b = tester.getTopLeft(find.byKey(const Key('ssHomeStartCard_directDraw')));
    final c = tester.getTopLeft(find.byKey(const Key('ssHomeStartCard_imageTransform')));
    expect(a.dy, b.dy);
    expect(b.dy, c.dy);
    expect(a.dx < b.dx && b.dx < c.dx, isTrue);
    final ai = tester.getTopLeft(find.byKey(const Key('ssHomeAiPreview')));
    final recent = tester.getTopLeft(find.text('최근 프로젝트'));
    expect(ai.dx, greaterThan(recent.dx), reason: 'AI 분석 미리보기는 최근 프로젝트 오른쪽');
  });

  for (final size in const [Size(1024, 768), Size(800, 600), Size(640, 480)]) {
    testWidgets('${size.width.toInt()}×${size.height.toInt()} 창에서 홈 카드가 넘치지 않고 설명이 한 글자씩 끊기지 않는다', (tester) async {
      await _pumpHome(tester, size);
      expect(tester.takeException(), isNull);
      for (final type in SsSourceType.values) {
        final desc = find.byKey(Key('ssHomeStartCardDesc_${type.name}'));
        expect(desc, findsOneWidget);
        final descSize = tester.getSize(desc);
        expect(descSize.width, greaterThan(120), reason: '${type.name} 설명은 충분한 폭으로 보인다');
        // 12px 글자 3줄(줄 높이 1.35) 이하 — 한 글자씩 세로로 늘어나지 않는다.
        expect(descSize.height, lessThanOrEqualTo(12 * 1.35 * 3 + 1));
      }
    });
  }

  testWidgets('사진이 들어간 시작 카드를 눌러도 지금처럼 프로젝트 생성으로 간다', (tester) async {
    await _pumpHome(tester, const Size(1280, 720));
    await tester.tap(find.byKey(const Key('ssHomeStartCard_imageTransform')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, SsStage.projectCreation.title);
  });
}
