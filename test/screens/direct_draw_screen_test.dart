// SS005 — MASTER UI 4-1(직접 그리기) 화면 위젯 테스트: 도구모음 노출, 마우스 드래그로 벽 그리기,
// Undo 활성화, '평면도 업로드로 →' 다음 버튼 활성화. 저장소는 MemorySsProjectStore로 대체한다.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/direct_draw_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemorySsProjectStore store;

  setUp(() async {
    store = MemorySsProjectStore();
    final project = SsProject.create(id: 'p1', name: '테스트 평면도', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1));
    await store.save(project);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DirectDrawScreen(projectId: 'p1', projectStore: store)));
    await tester.pumpAndSettle();
  }

  testWidgets('도구모음(선택/벽체/문/창문)과 다음 버튼이 보인다', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('ssDrawTool_select')), findsOneWidget);
    expect(find.byKey(const Key('ssDrawTool_wall')), findsOneWidget);
    expect(find.byKey(const Key('ssDrawTool_door')), findsOneWidget);
    expect(find.byKey(const Key('ssDrawTool_window')), findsOneWidget);
    expect(find.byKey(const Key('ssDrawNext')), findsOneWidget);
    final next = tester.widget<InkWell>(find.byKey(const Key('ssDrawNext')));
    expect(next.onTap, isNull, reason: '벽을 하나도 그리지 않았으면 다음 단계로 갈 수 없다');
  });

  testWidgets('벽 도구를 고르고 마우스로 드래그하면 벽이 생기고 Undo·다음 버튼이 켜진다', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('ssDrawTool_wall')));
    await tester.pumpAndSettle();

    final canvas = find.byKey(const Key('ssDrawCanvas'));
    final start = tester.getTopLeft(canvas) + const Offset(200, 200);
    final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.moveTo(start + const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.up();
    await tester.pumpAndSettle();

    final undo = tester.widget<IconButton>(find.byKey(const Key('ssDrawUndo')));
    expect(undo.onPressed, isNotNull, reason: '벽을 그리면 되돌리기를 쓸 수 있다');
    final next = tester.widget<InkWell>(find.byKey(const Key('ssDrawNext')));
    expect(next.onTap, isNotNull, reason: '벽을 그리면 다음 단계(CAD 변환)로 진행할 수 있다');

    // 자동저장 타이머가 남지 않도록 화면을 내려 정리한다(§6 자동저장 — pending Timer 방지).
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
