// WO089 CORE EDITING — FloorPlanWorkspaceScreen에서 실제 편집 결과가
// 데이터 모델에 존재하고, Undo/Redo로 정확히 되돌아오는지 확인한다.
// 평면도를 업로드하지 않은 blank workspace 상태(§19)에서 진행한다 —
// 실제 production Workspace 컴포넌트를 그대로 쓰되, 파일 fixture를
// 새로 준비할 필요가 없다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/workspace_task_item.dart';
import 'package:ason_space/screens/floor_plan_workspace_screen.dart';
import 'package:ason_space/widgets/workspace/workspace_drawing_layer.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: FloorPlanWorkspaceScreen()));
    await tester.pumpAndSettle();
  }

  List<dynamic> currentDrawings(WidgetTester tester) =>
      tester.widget<WorkspaceDrawingLayer>(find.byType(WorkspaceDrawingLayer)).drawings;

  /// WO099 UI COMPACT MODE — 도구 팔레트는 이제 우측 "작업도구" 아이콘을
  /// 눌러야 펼쳐지는 flyout 안에 있고, 각 도구도 상시 텍스트가 아니라
  /// tooltip으로만 이름을 보여준다. 이 파일의 각 테스트는 이 helper를
  /// 정확히 한 번만 부르므로(패널이 항상 접힌 상태에서 시작), 매번
  /// "작업도구"를 펼치는 탭을 무조건 한 번 수행한다.
  Future<void> selectTool(WidgetTester tester, WorkspaceSelectionTool tool) async {
    await tester.tap(find.byTooltip('작업도구'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(tool.label).first);
    await tester.pumpAndSettle();
  }

  Future<void> drawLine(WidgetTester tester) async {
    final rect = tester.getRect(find.byType(WorkspaceDrawingLayer));
    final gesture = await tester.startGesture(rect.topLeft + const Offset(20, 20));
    await gesture.moveTo(rect.topLeft + const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(rect.topLeft + const Offset(120, 60));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('직선을 그리면 실제 데이터에 존재하고, Undo/Redo로 정확히 사라졌다 돌아온다(entity identity 보존)', (tester) async {
    await pumpScreen(tester);

    expect(currentDrawings(tester), isEmpty);

    await selectTool(tester, WorkspaceSelectionTool.line);
    await drawLine(tester);

    final afterCreate = currentDrawings(tester);
    expect(afterCreate, hasLength(1), reason: '드래그로 그린 직선이 실제 데이터 모델에 존재해야 한다');
    final createdId = afterCreate.single.id as int;

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();
    expect(currentDrawings(tester), isEmpty, reason: 'Undo 후 마지막 도형이 사라져야 한다');

    await tester.tap(find.byIcon(Icons.redo_rounded));
    await tester.pumpAndSettle();
    final afterRedo = currentDrawings(tester);
    expect(afterRedo, hasLength(1), reason: 'Redo 후 다시 나타나야 한다');
    expect(afterRedo.single.id, createdId, reason: 'Undo/Redo를 거쳐도 같은 도형은 같은 id를 유지해야 한다(entity identity 보존)');
  });

  testWidgets('overlay does not mutate base floor plan — 도형을 그리고 지워도 평면도 업로드/분석 상태는 전혀 바뀌지 않는다', (tester) async {
    await pumpScreen(tester);

    // blank workspace이므로 "① 평면도 업로드" 시작 카드가 그대로 보여야
    // 한다 — 도형 편집 전후로 이 상태가 절대 바뀌면 안 된다.
    expect(find.byTooltip('평면도 업로드'), findsWidgets);

    await selectTool(tester, WorkspaceSelectionTool.line);
    await drawLine(tester);
    expect(currentDrawings(tester), hasLength(1));

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();

    // 도형 생성/삭제를 거쳤지만 평면도 업로드 관련 UI는 그대로다 —
    // drawing 편집이 base floor plan/분석 상태를 전혀 건드리지 않았다는
    // 증거다.
    expect(find.byTooltip('평면도 업로드'), findsWidgets);
    expect(currentDrawings(tester), isEmpty);
  });
}
