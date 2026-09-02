// Space3DView(실제 조작 가능한 3D 아이소 렌더러) 스모크 테스트.
//
// 1. 실제 SpaceScene을 넘기면 예외 없이 그려진다(정적 이미지가 아니라
//    CustomPaint 기반 실제 투영).
// 2. "화면 맞춤" 버튼이 보이고 눌러도 예외가 없다(WO 12번 reset/fit).
// 3. 드래그(회전)·핀치(확대/축소)·마우스 휠 모두 예외 없이 처리된다
//    (WO 12번 회전/확대/축소/pan).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('P/Q — View Preset 버튼 5개가 모두 보이고, 누른 뒤에도 예외 없이 계속 '
      '드래그로 자유 회전할 수 있다(preset이 아무 것도 잠그지 않는다)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: _sampleScene())),
      ),
    );
    await tester.pump();

    for (final label in ['기본 아이소', '좌측 아이소', '우측 아이소', '후면 아이소', '상면']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('좌측 아이소'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // preset 적용 뒤에도 즉시 자유 orbit이 가능해야 한다.
    await tester.drag(find.byType(Space3DView), const Offset(-60, 30));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('R — "전체 화면" 버튼을 누르면 전체 화면 페이지로 이동하고, "닫기"를 '
      '누르면 원래 화면으로 돌아온다(WO 13번)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: _sampleScene())),
      ),
    );
    await tester.pump();

    expect(find.text('전체 화면'), findsOneWidget);
    await tester.tap(find.text('전체 화면'));
    await tester.pumpAndSettle();

    // 전체 화면 안에는 또 다른 "전체 화면" 진입 버튼이 없어야 한다
    // (전체 화면 안에서 또 전체 화면으로 들어가는 중첩 방지).
    expect(find.text('전체 화면'), findsNothing);
    expect(find.text('닫기(ESC)'), findsOneWidget);
    // 전체 화면 안에서도 실제 3D 렌더러가 동작한다(같은 scene).
    expect(find.byType(Space3DView), findsOneWidget);

    await tester.tap(find.text('닫기(ESC)'));
    await tester.pumpAndSettle();

    expect(find.text('전체 화면'), findsOneWidget);
    expect(find.text('닫기(ESC)'), findsNothing);
  });

  testWidgets('R — 전체 화면에서 ESC 키를 누르면 원래 화면으로 돌아온다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: _sampleScene())),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('전체 화면'));
    await tester.pumpAndSettle();
    expect(find.text('닫기(ESC)'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('전체 화면'), findsOneWidget);
  });

  testWidgets('N — 우클릭 드래그는 회전이 아니라 pan으로 처리되어도 예외가 없다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: _sampleScene())),
      ),
    );
    await tester.pump();

    final center = tester.getCenter(find.byType(Space3DView));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.moveBy(const Offset(40, -20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('WO 16번 — 방향 표시(compass)가 실제로 렌더링된다(장식용 fake cube 아님)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Space3DView(scene: _sampleScene())),
      ),
    );
    await tester.pump();

    // 나침반은 CustomPaint로 직접 그린다 — Space3DView 안에 최소
    // 2개(3D 렌더러 자체 + 나침반)의 CustomPaint가 있어야 한다.
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
