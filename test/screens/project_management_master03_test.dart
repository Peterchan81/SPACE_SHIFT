// SS-수정003 3차 — MASTER 03 프로젝트 관리: 머리글 한 줄/두 줄, 5단계 점·%, 점선 새 프로젝트 카드, 폭별 열 수.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/project_management_screen.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _railWidth = 236.0;

Future<MemorySsProjectStore> _storeWith(int count) async {
  final store = MemorySsProjectStore();
  for (var i = 0; i < count; i++) {
    final type = SsSourceType.values[i % SsSourceType.values.length];
    var p = SsProject.create(id: 'p$i', name: '프로젝트 이름이 조금 긴 테스트 $i', sourceType: type, now: DateTime(2026, 1, 1 + i));
    final flow = SsFlows.stages[type]!;
    p = p.moveTo(flow[i % flow.length], now: DateTime(2026, 2, 1 + i));
    await store.save(p);
  }
  return store;
}

Future<List<String?>> _pump(WidgetTester tester, SsProjectStore store, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SsProjectStoreProvider.useForTesting(store);
  addTearDown(SsProjectStoreProvider.resetForTesting);
  final pushed = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (s) {
        pushed.add(s.name);
        return MaterialPageRoute<void>(settings: s, builder: (_) => Scaffold(body: Text('route:${s.name}', key: const Key('pushedRoute'))));
      },
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: _railWidth),
            Expanded(child: ProjectManagementScreen(projectStore: store)),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return pushed;
}

int _firstRowCount(WidgetTester tester, int count) {
  final top = tester.getTopLeft(find.byKey(const Key('ssProjectsCreateCard'))).dy;
  var n = 1;
  for (var i = 0; i < count; i++) {
    if ((tester.getTopLeft(find.byKey(Key('ssProjectCard_p$i'))).dy - top).abs() < 1) n++;
  }
  return n;
}

void main() {
  test('열 수 계산 — 1280·1024·800·640 창(왼쪽 메뉴 236·여백 48)', () {
    expect(ssProjectGridColumns(1280 - _railWidth - 48), 4);
    expect(ssProjectGridColumns(1024 - _railWidth - 48), 3);
    expect(ssProjectGridColumns(800 - _railWidth - 48), 2);
    expect(ssProjectGridColumns(640 - _railWidth - 48), 1);
  });

  for (final c in const [(Size(1280, 720), 4), (Size(1024, 768), 3), (Size(800, 600), 2), (Size(640, 480), 1)]) {
    testWidgets('${c.$1.width.toInt()}×${c.$1.height.toInt()} 창에서 카드 ${c.$2}열 · overflow 없음', (tester) async {
      final store = await _storeWith(8);
      await _pump(tester, store, c.$1);
      expect(tester.takeException(), isNull);
      expect(_firstRowCount(tester, 8), c.$2);

      // 목록 보기도 overflow 없이 그려진다.
      await tester.tap(find.byKey(const Key('ssProjectsViewList')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ssProjectSteps_p0')), findsOneWidget);
    });
  }

  testWidgets('카드에 진행률 %와 5단계 점(지난·현재·남은)이 보인다', (tester) async {
    final store = MemorySsProjectStore();
    await store.save(
      SsProject.create(id: 'a', name: '우리집', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1)).moveTo(SsStage.isoRendering, now: DateTime(2026, 1, 2)),
    );
    await _pump(tester, store, const Size(1280, 720));

    expect(find.byKey(const Key('ssProjectSteps_a')), findsOneWidget);
    expect(find.byKey(const Key('ssProjectStep_a_upload_completed')), findsOneWidget);
    expect(find.byKey(const Key('ssProjectStep_a_analysis_completed')), findsOneWidget);
    expect(find.byKey(const Key('ssProjectStep_a_generate_completed')), findsOneWidget);
    expect(find.byKey(const Key('ssProjectStep_a_edit_current')), findsOneWidget);
    expect(find.byKey(const Key('ssProjectStep_a_done_upcoming')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ssProjectProgress_a'))).data, '75%');
    for (final label in const ['업로드', '분석', '생성', '수정', '완료']) {
      expect(find.descendant(of: find.byKey(const Key('ssProjectSteps_a')), matching: find.text(label)), findsOneWidget);
    }
    // 예전 "n/m 단계 · 다음: …" 글은 카드에 보이지 않는다(툴팁으로만).
    expect(find.textContaining('다음: '), findsNothing);
  });

  testWidgets('새 프로젝트 카드는 점선 테두리이고 누르면 프로젝트 생성으로 이동한다', (tester) async {
    final pushed = await _pump(tester, MemorySsProjectStore(), const Size(1280, 720));

    final dashed = tester.widget<CustomPaint>(find.byKey(const Key('ssProjectsCreateCardDashed')));
    expect(dashed.painter, isA<SsDashedRRectPainter>());
    expect(find.text('새 프로젝트 생성'), findsOneWidget);
    expect(find.text('새로운 공간을 디자인해보세요.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssProjectsCreateCard')));
    await tester.pumpAndSettle();
    expect(pushed, contains(SsStage.projectCreation.routeName));
    expect(find.byKey(const Key('pushedRoute')), findsOneWidget);
  });

  testWidgets('머리글 — 넓으면 제목과 검색·보기·정렬이 한 줄', (tester) async {
    await _pump(tester, MemorySsProjectStore(), const Size(1280, 720));
    expect(find.byKey(const Key('ssProjectsHeaderWide')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, '프로젝트');
    final whatBottom = tester.getBottomLeft(find.byKey(const Key('ssStageWhat'))).dy;
    final searchTop = tester.getTopLeft(find.byKey(const Key('ssProjectsSearch'))).dy;
    expect(searchTop < whatBottom, isTrue);
    expect(tester.getTopLeft(find.byKey(const Key('ssProjectsSearch'))).dx > tester.getTopLeft(find.byKey(const Key('ssStageTitle'))).dx, isTrue);
  });

  testWidgets('머리글 — 좁으면 검색·보기·정렬이 제목 아래 줄', (tester) async {
    await _pump(tester, MemorySsProjectStore(), const Size(800, 600));
    expect(find.byKey(const Key('ssProjectsHeaderNarrow')), findsOneWidget);
    final whatBottom = tester.getBottomLeft(find.byKey(const Key('ssStageWhat'))).dy;
    final searchTop = tester.getTopLeft(find.byKey(const Key('ssProjectsSearch'))).dy;
    expect(searchTop >= whatBottom, isTrue);
    expect(tester.takeException(), isNull);
  });
}
