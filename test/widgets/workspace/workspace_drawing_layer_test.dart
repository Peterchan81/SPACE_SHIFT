import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/workspace_drawing_entity.dart';
import 'package:ason_space/models/workspace_task_item.dart';
import 'package:ason_space/models/workspace_viewport_transform.dart';
import 'package:ason_space/widgets/workspace/workspace_drawing_layer.dart';

/// 300x300 정사각형 캔버스에 documentSize도 300x300(1:1)로 둬서, 화면
/// 픽셀 좌표와 정규화 좌표의 관계가 단순 나눗셈(÷300)이 되게 한다 —
/// 제스처 시뮬레이션 좌표를 예측 가능하게 만들기 위함이다.
Widget _harness({
  required WorkspaceSelectionTool tool,
  List<WorkspaceDrawingEntity> drawings = const [],
  int? selectedDrawingId,
  WorkspaceViewportTransform viewport = WorkspaceViewportTransform.identity,
  required ValueChanged<WorkspaceDrawingEntity> onCreateDrawing,
  ValueChanged<int?>? onSelectDrawing,
  ValueChanged<WorkspaceViewportTransform>? onViewportChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 300,
        height: 300,
        child: WorkspaceDrawingLayer(
          tool: tool,
          drawings: drawings,
          selectedDrawingId: selectedDrawingId,
          viewport: viewport,
          documentSize: const Size(300, 300),
          onCreateDrawing: onCreateDrawing,
          onSelectDrawing: onSelectDrawing ?? (_) {},
          onViewportChanged: onViewportChanged ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('line creation — 드래그로 직선을 만들면 정확한 document 좌표로 저장된다', (tester) async {
    WorkspaceDrawingEntity? created;
    await tester.pumpWidget(_harness(tool: WorkspaceSelectionTool.line, onCreateDrawing: (e) => created = e));

    final gesture = await tester.startGesture(const Offset(30, 30));
    await gesture.moveTo(const Offset(30, 30));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(const Offset(210, 90));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.type, WorkspaceDrawingType.line);
    expect(created!.points, hasLength(2));
    expect(created!.points[0].x, closeTo(0.1, 0.01));
    expect(created!.points[0].y, closeTo(0.1, 0.01));
    expect(created!.points[1].x, closeTo(0.7, 0.01));
    expect(created!.points[1].y, closeTo(0.3, 0.01));
  });

  testWidgets('circle creation — 드래그로 원을 만들면 center/edge가 저장된다', (tester) async {
    WorkspaceDrawingEntity? created;
    await tester.pumpWidget(_harness(tool: WorkspaceSelectionTool.circle, onCreateDrawing: (e) => created = e));

    final gesture = await tester.startGesture(const Offset(150, 150));
    await gesture.moveTo(const Offset(150, 150));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(const Offset(180, 150));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.type, WorkspaceDrawingType.circle);
    expect(created!.circleCenter.x, closeTo(0.5, 0.01));
    expect(created!.circleCenter.y, closeTo(0.5, 0.01));
    expect(created!.circleRadius, closeTo(0.1, 0.01));
  });

  testWidgets('free region creation — 연속 드래그 경로가 polygon으로 저장된다', (tester) async {
    WorkspaceDrawingEntity? created;
    await tester.pumpWidget(_harness(tool: WorkspaceSelectionTool.freeform, onCreateDrawing: (e) => created = e));

    final gesture = await tester.startGesture(const Offset(30, 30));
    for (final p in [const Offset(30, 30), const Offset(90, 30), const Offset(90, 90), const Offset(30, 90)]) {
      await gesture.moveTo(p);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.type, WorkspaceDrawingType.freeRegion);
    expect(created!.points.length, greaterThanOrEqualTo(2));
  });

  testWidgets('curve creation — 3번의 개별 탭(start/control/end)으로 완성된다', (tester) async {
    WorkspaceDrawingEntity? created;
    await tester.pumpWidget(_harness(tool: WorkspaceSelectionTool.curve, onCreateDrawing: (e) => created = e));

    await tester.tapAt(const Offset(30, 150));
    await tester.pump(const Duration(milliseconds: 50));
    expect(created, isNull, reason: '1번째 탭만으로는 아직 완성되지 않는다');

    await tester.tapAt(const Offset(150, 30));
    await tester.pump(const Duration(milliseconds: 50));
    expect(created, isNull, reason: '2번째 탭(control)까지도 아직 완성되지 않는다');

    await tester.tapAt(const Offset(270, 150));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.type, WorkspaceDrawingType.curve);
    expect(created!.points, hasLength(3));
    expect(created!.points[0].x, closeTo(0.1, 0.01));
    expect(created!.points[1].x, closeTo(0.5, 0.01));
    expect(created!.points[2].x, closeTo(0.9, 0.01));
  });

  testWidgets('selection — 도형을 탭하면 선택되고, 빈 공간을 탭하면 선택 해제된다', (tester) async {
    final now = DateTime(2026);
    final line = WorkspaceDrawingEntity(
      id: 7,
      type: WorkspaceDrawingType.line,
      points: const [Point2(0.1, 0.5), Point2(0.9, 0.5)],
      createdAt: now,
      updatedAt: now,
    );
    int? selected = -1; // -1 = 아직 콜백 안 옴(null과 구분).
    await tester.pumpWidget(
      _harness(
        tool: WorkspaceSelectionTool.select,
        drawings: [line],
        onCreateDrawing: (_) {},
        onSelectDrawing: (id) => selected = id,
      ),
    );

    // 선분(y=0.5 -> 150px) 위를 탭 — 선택돼야 한다.
    await tester.tapAt(const Offset(150, 150));
    await tester.pumpAndSettle();
    expect(selected, 7);

    // 빈 공간(선분에서 먼 위치) 탭 — 선택 해제.
    await tester.tapAt(const Offset(150, 20));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('zoom does not mutate geometry — 확대된 viewport에서도 같은 document 좌표로 그린 도형이 같은 위치에 hit-test된다', (tester) async {
    final now = DateTime(2026);
    final line = WorkspaceDrawingEntity(
      id: 1,
      type: WorkspaceDrawingType.line,
      points: const [Point2(0.5, 0.5), Point2(0.5, 0.5)],
      createdAt: now,
      updatedAt: now,
    );
    // 2배 확대 + (0,0) 오프셋 상태에서, 문서 좌표 (0.5,0.5) = fitted(150,150)
    // 이 화면(300,300)에 그려진다(150*2=300).
    const zoomedViewport = WorkspaceViewportTransform(scale: 2.0, offset: Offset.zero);
    int? selected;
    await tester.pumpWidget(
      _harness(
        tool: WorkspaceSelectionTool.select,
        drawings: [line],
        viewport: zoomedViewport,
        onCreateDrawing: (_) {},
        onSelectDrawing: (id) => selected = id,
      ),
    );

    await tester.tapAt(const Offset(299, 299));
    await tester.pumpAndSettle();
    expect(selected, 1, reason: '2배 확대 상태에서도 문서 좌표 (0.5,0.5)는 화면 (300,300) 근처에서 정확히 히트해야 한다');
  });
}
