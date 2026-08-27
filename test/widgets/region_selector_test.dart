// RegionSelector 위젯에 대한 테스트.
//
// 1. 드래그로 새 선택 영역을 만들면 정규화(0~1) 좌표로 콜백된다.
// 2. 기존 영역 안쪽을 드래그하면 크기는 유지된 채 위치만 이동한다.
// 3. 모서리 핸들을 드래그하면 크기가 조절된다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/region_selection.dart';
import 'package:ason_space/widgets/region_selector.dart';

final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// 지정한 크기의 상자 안에 RegionSelector를 올리고, 선택 상태는
/// 테스트 쪽 StatefulBuilder가 들고 있게 해 실제 사용 방식(제어 컴포넌트)을
/// 그대로 재현한다.
Future<void> _pumpSelector(
  WidgetTester tester, {
  required ValueChanged<RegionSelection> onChanged,
  RegionSelection? initialSelection,
  Size size = const Size(400, 300),
}) async {
  RegionSelection? selection = initialSelection;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: StatefulBuilder(
            builder: (context, setState) {
              return RegionSelector(
                imageBytes: _fakeImageBytes,
                selection: selection,
                onChanged: (value) {
                  selection = value;
                  onChanged(value);
                  setState(() {});
                },
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('드래그로 새 영역을 만들면 정규화된 좌표로 전달된다', (tester) async {
    RegionSelection? lastSelection;
    await _pumpSelector(tester, onChanged: (value) => lastSelection = value);

    final topLeft = tester.getTopLeft(find.byType(RegionSelector));
    await tester.dragFrom(topLeft + const Offset(40, 30), const Offset(120, 90));
    await tester.pump();

    expect(lastSelection, isNotNull);
    // 400x300 상자에서 (40,30) -> (160,120) 드래그 => 정규화 좌표로 환산.
    expect(lastSelection!.x, closeTo(40 / 400, 0.02));
    expect(lastSelection!.y, closeTo(30 / 300, 0.02));
    expect(lastSelection!.width, closeTo(120 / 400, 0.02));
    expect(lastSelection!.height, closeTo(90 / 300, 0.02));

    // 정규화 좌표는 항상 0~1 범위를 유지해야 한다(화면 크기 독립적).
    expect(lastSelection!.x, inInclusiveRange(0.0, 1.0));
    expect(lastSelection!.y, inInclusiveRange(0.0, 1.0));
    expect(lastSelection!.width, inInclusiveRange(0.0, 1.0));
    expect(lastSelection!.height, inInclusiveRange(0.0, 1.0));
  });

  testWidgets('기존 영역 안쪽을 드래그하면 크기는 그대로, 위치만 이동한다', (tester) async {
    RegionSelection? lastSelection;
    await _pumpSelector(tester, onChanged: (value) => lastSelection = value);

    final topLeft = tester.getTopLeft(find.byType(RegionSelector));
    await tester.dragFrom(topLeft + const Offset(40, 30), const Offset(100, 80));
    await tester.pump();

    final beforeMove = lastSelection!;

    // 방금 만든 영역([40,30]-[140,110]) 안쪽 지점에서 드래그를 시작해 이동시킨다.
    await tester.dragFrom(topLeft + const Offset(80, 70), const Offset(30, 20));
    await tester.pump();

    final afterMove = lastSelection!;

    expect(afterMove.width, closeTo(beforeMove.width, 0.01));
    expect(afterMove.height, closeTo(beforeMove.height, 0.01));
    expect(afterMove.x, isNot(closeTo(beforeMove.x, 0.001)));
    expect(afterMove.y, isNot(closeTo(beforeMove.y, 0.001)));
  });

  testWidgets('모서리 핸들을 드래그하면 크기가 조절된다', (tester) async {
    RegionSelection? lastSelection;
    await _pumpSelector(tester, onChanged: (value) => lastSelection = value);

    final topLeft = tester.getTopLeft(find.byType(RegionSelector));
    await tester.dragFrom(topLeft + const Offset(40, 30), const Offset(100, 80));
    await tester.pump();

    final beforeResize = lastSelection!;

    // 우측 하단 모서리([140,110])를 잡고 바깥쪽으로 더 끌어 크기를 키운다.
    await tester.dragFrom(topLeft + const Offset(140, 110), const Offset(50, 40));
    await tester.pump();

    final afterResize = lastSelection!;

    expect(afterResize.width, greaterThan(beforeResize.width));
    expect(afterResize.height, greaterThan(beforeResize.height));
    // 좌상단 위치는 그대로 유지되어야 한다.
    expect(afterResize.x, closeTo(beforeResize.x, 0.01));
    expect(afterResize.y, closeTo(beforeResize.y, 0.01));
  });
}
