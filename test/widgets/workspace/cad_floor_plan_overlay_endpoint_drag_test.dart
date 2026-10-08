// SS CAD TEST — WorkOrder(1차 CAD/DXF E2E) §7: "현재 코드에 존재하지만
// 비활성화된 벽 endpoint drag는 먼저 테스트한다. 안전하게 동작하면
// 활성화한다."
//
// CadFloorPlanOverlay.allowEndpointDrag(non-calibrating 모드에서 CAD 초안을
// 읽기 전용으로만 보여주기 위해 이번 세션에 추가한 플래그)를 실제로
// true로 두고 드래그 제스처를 실행해, 끝점 이동이 정확한 좌표로
// onWallEndpointChanged를 호출하는지 격리된 위젯 테스트로 확인한다 —
// 여기서 안전함이 확인되면 화면(floor_plan_preview.dart)에서 그 플래그를
// 켠다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/widgets/workspace/cad_floor_plan_overlay.dart';
import 'package:ason_space/widgets/workspace/floor_plan_analysis_overlay.dart' show ContainFitTransform;

void main() {
  const wall = CadWall(
    id: 'w1',
    start: Point2(0.2, 0.5),
    end: Point2(0.8, 0.5),
    thicknessNormalized: 0.02,
    wallType: CadWallType.exterior,
    confidence: 1.0,
  );
  final plan = const CadFloorPlan(
    sourceWidthPx: 1000,
    sourceHeightPx: 1000,
    walls: [wall],
    openings: [],
    rooms: [],
    warnings: [],
  );

  Future<void> pumpOverlay(
    WidgetTester tester, {
    required void Function(String wallId, bool isStart, Point2 newPosition) onWallEndpointChanged,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CadFloorPlanOverlay(
              floorPlan: plan,
              selectedId: 'w1',
              onSelect: (_) {},
              onWallEndpointChanged: onWallEndpointChanged,
              allowEndpointDrag: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('allowEndpointDrag:true — 끝점 핸들을 드래그하면 정확한 새 좌표로 onWallEndpointChanged가 호출된다', (
    tester,
  ) async {
    String? changedWallId;
    bool? changedIsStart;
    Point2? changedPosition;
    await pumpOverlay(
      tester,
      onWallEndpointChanged: (wallId, isStart, newPosition) {
        changedWallId = wallId;
        changedIsStart = isStart;
        changedPosition = newPosition;
      },
    );

    // 벽은 (0.2,0.5)~(0.8,0.5) — ContainFitTransform으로 실제 화면 좌표를
    // 정확히 계산한다(1000x1000 정사각 이미지가 800x600 컨테이너에
    // contain-fit되면 letterbox가 생긴다).
    final overlayRect = tester.getRect(find.byType(CadFloorPlanOverlay));
    final transform = ContainFitTransform.compute(overlayRect.size, const Size(1000, 1000));
    final endHandleScreen = overlayRect.topLeft + transform.mapNormalized(wall.end);

    final gesture = await tester.startGesture(endHandleScreen);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(changedWallId, 'w1');
    expect(changedIsStart, isFalse, reason: '끝점(end) 핸들을 옮겼으므로 isStart는 false여야 한다');
    expect(changedPosition, isNotNull);
    // 오른쪽으로 40px만큼 옮겼으므로 정규화 x가 원래(0.8)보다 커야 한다.
    expect(changedPosition!.x, greaterThan(0.8));
    // y는 수평 드래그이므로 거의 그대로여야 한다.
    expect(changedPosition!.y, closeTo(0.5, 0.02));
  });

  testWidgets('allowEndpointDrag:false — 끝점 핸들 자체가 렌더링되지 않아 드래그해도 콜백이 호출되지 않는다(기존 동작 유지 확인)', (
    tester,
  ) async {
    var called = false;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CadFloorPlanOverlay(
              floorPlan: plan,
              selectedId: 'w1',
              onSelect: (_) {},
              onWallEndpointChanged: (_, _, _) => called = true,
              allowEndpointDrag: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final overlayRect = tester.getRect(find.byType(CadFloorPlanOverlay));
    final transform = ContainFitTransform.compute(overlayRect.size, const Size(1000, 1000));
    final endHandleScreen = overlayRect.topLeft + transform.mapNormalized(wall.end);
    final gesture = await tester.startGesture(endHandleScreen);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });
}
