// SpaceCanvas(공간 작업실 캔버스) 위젯에 대한 테스트.
//
// 1. 빈 영역을 드래그하면 정규화된 좌표(0.0~1.0)로 editingRect가 만들어지는지
//    확인한다. (Drag로 새 영역 선택)
// 2. 이미 등록된 작업 영역을 탭하면 onTaskTap이 호출되는지 확인한다.
//    (영역 재선택)
// 3. editingRect의 몸통을 드래그하면 영역이 이동하는지 확인한다. (영역 이동)

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/space_task.dart';
import 'package:ason_space/widgets/space_canvas.dart';

final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  testWidgets('빈 영역을 드래그하면 정규화된 좌표로 editingRect가 생성된다', (
    WidgetTester tester,
  ) async {
    NormalizedRect? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpaceCanvas(
            imageBytes: _fakeImageBytes,
            tasks: const [],
            editingRect: null,
            onEditingRectChanged: (rect) => changed = rect,
          ),
        ),
      ),
    );

    await tester.drag(find.byType(SpaceCanvas), const Offset(100, 80));
    await tester.pump();

    expect(changed, isNotNull);
    expect(changed!.left, greaterThanOrEqualTo(0));
    expect(changed!.top, greaterThanOrEqualTo(0));
    expect(changed!.width, greaterThan(0));
    expect(changed!.height, greaterThan(0));
  });

  testWidgets('등록된 작업 영역을 탭하면 onTaskTap이 호출된다', (WidgetTester tester) async {
    String? tappedId;
    const task = SpaceTask(
      id: 'task_1',
      category: SpaceCategory.wall,
      rect: NormalizedRect(left: 0.1, top: 0.1, width: 0.6, height: 0.6),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpaceCanvas(
            imageBytes: _fakeImageBytes,
            tasks: const [task],
            editingRect: null,
            onEditingRectChanged: (_) {},
            onTaskTap: (id) => tappedId = id,
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(SpaceCanvas)));
    await tester.pump();

    expect(tappedId, 'task_1');
  });

  testWidgets('editingRect의 몸통을 드래그하면 영역이 이동한다', (WidgetTester tester) async {
    NormalizedRect current = const NormalizedRect(
      left: 0.3,
      top: 0.3,
      width: 0.2,
      height: 0.2,
    );

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: SpaceCanvas(
                imageBytes: _fakeImageBytes,
                tasks: const [],
                editingRect: current,
                onEditingRectChanged: (rect) {
                  setState(() => current = rect ?? current);
                },
              ),
            ),
          );
        },
      ),
    );

    final canvasSize = tester.getSize(find.byType(SpaceCanvas));
    final topLeft = tester.getTopLeft(find.byType(SpaceCanvas));
    final bodyPoint =
        topLeft + Offset(canvasSize.width * 0.4, canvasSize.height * 0.4);

    await tester.dragFrom(bodyPoint, const Offset(30, 20));
    await tester.pump();

    expect(current.left, greaterThan(0.3));
    expect(current.top, greaterThan(0.3));
  });
}
