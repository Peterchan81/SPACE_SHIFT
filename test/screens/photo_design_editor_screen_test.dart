// SS006 — MASTER UI 4-2(실제 공간 이미지 AI 디자인 에디터) 화면 위젯 테스트: 도구모음 노출, 가구
// 추가로 객체가 캔버스에 나타나는지, Before/After 토글과 완료하기 버튼이 동작하는지 확인한다.
// 저장소는 MemorySsProjectStore로 대체하고, 원본 사진은 프로젝트 생성 시 미리 넣어 업로드 단계를 건너뛴다.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/photo_design_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 픽셀 PNG(검은 점) — 테스트에서 흔히 쓰는 최소 유효 PNG.
const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

void main() {
  late MemorySsProjectStore store;

  setUp(() async {
    store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: '테스트 사진 디자인', sourceType: SsSourceType.imageTransform, now: DateTime(2026, 1, 1));
    project = project.withSource({'imageBase64': _tinyPngBase64}, label: '원본 사진');
    await store.save(project);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // PhotoDesignEditorScreen의 InkWell(우측 탭 등)은 Material 조상이 필요하다(실제 앱 경로인
    // SsStageScreen은 Scaffold로 이미 그 조상을 제공한다) — 여기서는 Scaffold로 감싸 같은 조건을 만든다.
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PhotoDesignEditorScreen(projectId: 'p1', projectStore: store))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('도구모음과 완료하기 버튼이 보인다', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('ssPhotoTool_select')), findsOneWidget);
    expect(find.byKey(const Key('ssPhotoTool_erase')), findsOneWidget);
    expect(find.byKey(const Key('ssPhotoTool_furnitureAdd')), findsOneWidget);
    expect(find.byKey(const Key('ssPhotoComplete')), findsOneWidget);
    final complete = tester.widget<ElevatedButton>(find.byKey(const Key('ssPhotoComplete')));
    expect(complete.onPressed, isNotNull, reason: '사진이 있으면 완료하기로 다음 단계로 갈 수 있다');
  });

  testWidgets('가구추가 도구로 가구를 고르고 캔버스를 누르면 객체가 생기고 Undo를 쓸 수 있다', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('ssPhotoTool_furnitureAdd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssPhotoRightTab_furniture')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssPhotoFurniture_소파')));
    await tester.pumpAndSettle();

    final canvas = find.byKey(const Key('ssPhotoCanvas'));
    await tester.tapAt(tester.getCenter(canvas));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssPhotoObject_1')), findsOneWidget);
    final undo = tester.widget<IconButton>(find.byKey(const Key('ssPhotoUndo')));
    expect(undo.onPressed, isNotNull, reason: '가구를 추가하면 되돌리기를 쓸 수 있다');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Before/After 토글을 누를 수 있다', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('ssPhotoBeforeAfterToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssPhotoBeforeAfterToggle')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
