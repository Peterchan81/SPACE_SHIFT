// Space3DView(실제 조작 가능한 3D 아이소 렌더러) 스모크 테스트.
//
// 1. 실제 SpaceScene을 넘기면 예외 없이 그려진다(정적 이미지가 아니라
//    CustomPaint 기반 실제 투영).
// 2. "화면 맞춤" 버튼이 보이고 눌러도 예외가 없다(WO 12번 reset/fit).
// 3. 드래그(회전)·핀치(확대/축소)·마우스 휠 모두 예외 없이 처리된다
//    (WO 12번 회전/확대/축소/pan).

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:ason_space/models/space_scene.dart';
import 'package:ason_space/widgets/workspace/space_3d_view.dart';

SpaceScene _sampleScene() {
  SpaceTriangle wallTri(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c) =>
      SpaceTriangle(
        a: a,
        b: b,
        c: c,
        color: const Color(0xFFC9C2B4),
        sourceKind: SpaceElementKind.wall,
        sourceId: 'wall-0',
      );

  return SpaceScene(
    triangles: [
      wallTri(
        vm.Vector3(0, 0, 0),
        vm.Vector3(4000, 0, 0),
        vm.Vector3(4000, 2400, 0),
      ),
      wallTri(
        vm.Vector3(0, 0, 0),
        vm.Vector3(4000, 2400, 0),
        vm.Vector3(0, 2400, 0),
      ),
    ],
    minBounds: vm.Vector3(0, 0, 0),
    maxBounds: vm.Vector3(4000, 2400, 4000),
    wallCount: 1,
    floorCount: 0,
    warnings: const [],
  );
}

void main() {
  testWidgets('실제 scene을 그려도 예외가 없다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: _sampleScene())),
      ),
    );
    await tester.pump();

    expect(find.byType(Space3DView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"화면 맞춤" 버튼이 보이고 눌러도 예외가 없다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: _sampleScene())),
      ),
    );
    await tester.pump();

    expect(find.text('화면 맞춤'), findsOneWidget);
    await tester.tap(find.text('화면 맞춤'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('드래그(궤도 회전)에도 예외가 없다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: _sampleScene())),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(Space3DView), const Offset(80, 40));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('마우스 휠 스크롤(확대/축소)에도 예외가 없다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: _sampleScene())),
      ),
    );
    await tester.pump();

    final center = tester.getCenter(find.byType(Space3DView));
    final testPointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(testPointer.addPointer(location: center));
    await tester.sendEventToBinding(testPointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('빈 scene(isEmpty)을 넘겨도 예외 없이 배경만 그린다', (tester) async {
    final empty = SpaceScene(
      triangles: const [],
      minBounds: vm.Vector3.zero(),
      maxBounds: vm.Vector3.zero(),
      wallCount: 0,
      floorCount: 0,
      warnings: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: empty)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
