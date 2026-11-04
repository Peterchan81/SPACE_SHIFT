import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/iso_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// WO098/floor_plan_workspace_screen_test.dart의 선례(코멘트 "3D 아이소 만들기를 실제로 누르지
// 않으므로(네이티브 GPU 위젯)")를 그대로 따른다 — 실제 geometry가 있는 [Space3DViewGpuV2]를
// flutter_test 안에서 마운트하면 네이티브 GPU 초기화가 끝나지 않아 테스트가 불안정해진다. 이
// 파일은 그 위젯이 아예 마운트되지 않는 상태(로딩/CAD 없음/빈 scene 플레이스홀더)만 widget test로
// 확인하고, 실제 geometry 선택/편집 흐름은 GPU가 필요 없는
// test/core/ss_iso_editor_controller_test.dart에서 커버한다.
void main() {
  testWidgets('projectId가 없으면 빈 CAD로 로드되어 리본과 빈 scene 안내가 보인다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IsoEditorScreen()));
    await tester.pump();

    expect(find.byKey(const Key('ssIsoEditorScreen')), findsOneWidget);
    expect(find.byKey(const Key('ssIsoRibbon')), findsOneWidget);
    expect(find.byKey(const Key('ssIsoEditorEmptyScene')), findsOneWidget);
    expect(find.byKey(const Key('ssIsoNoSelection')), findsOneWidget);
    expect(find.byKey(const Key('ssIsoUndo')), findsOneWidget);
    expect(find.byKey(const Key('ssIsoRedo')), findsOneWidget);
  });

  testWidgets('CAD 데이터가 없는 프로젝트를 열면 CAD 편집부터 하라는 안내가 보인다', (tester) async {
    final store = MemorySsProjectStore();
    final project = SsProject.create(id: 'p1', name: '테스트', sourceType: SsSourceType.directDraw);
    await store.save(project);

    await tester.pumpWidget(MaterialApp(home: IsoEditorScreen(projectId: 'p1', projectStore: store)));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('ssIsoEditorMissingCad')), findsOneWidget);
  });

  testWidgets('존재하지 않는 프로젝트를 열면 오류 안내가 보인다', (tester) async {
    final store = MemorySsProjectStore();
    await tester.pumpWidget(MaterialApp(home: IsoEditorScreen(projectId: 'missing', projectStore: store)));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('ssIsoEditorLoadError')), findsOneWidget);
  });

  testWidgets('벽이 없는 CAD에서는 가구를 추가해도 scene이 비어있어(가구만으로는 wall/floor가 생기지 않음) 플레이스홀더가 유지된다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IsoEditorScreen()));
    await tester.pump();

    await tester.tap(find.byKey(const Key('ssIsoToolAddFurniture')));
    await tester.pump();

    expect(find.byKey(const Key('ssIsoEditorEmptyScene')), findsOneWidget);
    expect(find.byKey(const Key('ssIsoFurnitureWidth')), findsOneWidget);
  });
}
