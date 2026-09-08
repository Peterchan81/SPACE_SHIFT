import 'package:flutter/material.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/workspace_viewport_transform.dart';
import 'package:ason_space/widgets/workspace/floor_plan_analysis_overlay.dart' show ContainFitTransform;

void main() {
  group('WorkspaceViewportTransform — apply/invert round trip', () {
    test('identity transform은 좌표를 바꾸지 않는다', () {
      const t = WorkspaceViewportTransform.identity;
      const p = Offset(123.0, 45.0);
      expect(t.apply(p), p);
      expect(t.invert(p), p);
    });

    test('임의의 scale/offset에서도 apply -> invert가 원래 값으로 되돌아온다(transform round trip)', () {
      const t = WorkspaceViewportTransform(scale: 2.3, offset: Offset(40, -15));
      const original = Offset(200, 150);
      final screen = t.apply(original);
      final back = t.invert(screen);
      expect(back.dx, closeTo(original.dx, 1e-9));
      expect(back.dy, closeTo(original.dy, 1e-9));
    });
  });

  group('WorkspaceViewportTransform.panBy — pan은 geometry에 영향 없음', () {
    test('panBy는 offset만 바꾸고 scale은 그대로 유지한다', () {
      const t = WorkspaceViewportTransform(scale: 1.5, offset: Offset(10, 10));
      final panned = t.panBy(const Offset(5, -5));
      expect(panned.scale, 1.5);
      expect(panned.offset, const Offset(15, 5));
    });
  });

  group('WorkspaceViewportTransform.zoomBy — 초점 고정 확대/축소', () {
    test('focalPoint는 확대 후에도 화면상 같은 위치에 남는다', () {
      const t = WorkspaceViewportTransform(scale: 1.0, offset: Offset.zero);
      const focal = Offset(100, 100);
      final zoomed = t.zoomBy(2.0, focalPoint: focal);
      // focal의 fitted-space 위치가 확대 전/후 같은 화면 위치(focal)에 있어야 한다.
      final fittedBefore = t.invert(focal);
      final screenAfter = zoomed.apply(fittedBefore);
      expect(screenAfter.dx, closeTo(focal.dx, 1e-9));
      expect(screenAfter.dy, closeTo(focal.dy, 1e-9));
    });

    test('배율은 min/max 범위로 clamp된다', () {
      const t = WorkspaceViewportTransform.identity;
      final tooSmall = t.zoomBy(0.01, focalPoint: Offset.zero);
      expect(tooSmall.scale, WorkspaceViewportTransform.minScale);
      final tooBig = t.zoomBy(100.0, focalPoint: Offset.zero);
      expect(tooBig.scale, WorkspaceViewportTransform.maxScale);
    });
  });

  group('screenToDocument / documentToScreen 합성 — §5 zoom/pan이 document 좌표를 바꾸지 않는다', () {
    // WorkspaceDrawingLayer와 동일한 합성 순서(fit + viewport)를 재현한다.
    Point2? screenToDocument(Offset screen, ContainFitTransform fit, WorkspaceViewportTransform viewport) {
      final fitted = viewport.invert(screen);
      return fit.inverse(fitted);
    }

    Offset documentToScreen(Point2 doc, ContainFitTransform fit, WorkspaceViewportTransform viewport) {
      final fitted = fit.mapNormalized(doc);
      return viewport.apply(fitted);
    }

    test('zoom does not mutate geometry — 같은 문서 좌표가 확대 배율과 무관하게 항상 같은 document 좌표로 역변환된다', () {
      final fit = ContainFitTransform.compute(const Size(400, 300), const Size(400, 300));
      const doc = Point2(0.3, 0.7);

      const viewportA = WorkspaceViewportTransform.identity;
      final viewportB = viewportA.zoomBy(3.0, focalPoint: const Offset(200, 150));

      // 같은 document 점을 두 배율에서 각각 화면 좌표로 그린 뒤, 다시
      // document로 되돌리면 정확히 같은 값이어야 한다 — 확대 자체가
      // 저장된 geometry를 절대 바꾸지 않는다는 것을 고정한다.
      final screenA = documentToScreen(doc, fit, viewportA);
      final screenB = documentToScreen(doc, fit, viewportB);
      final backA = screenToDocument(screenA, fit, viewportA)!;
      final backB = screenToDocument(screenB, fit, viewportB)!;

      expect(backA.x, closeTo(doc.x, 1e-9));
      expect(backA.y, closeTo(doc.y, 1e-9));
      expect(backB.x, closeTo(doc.x, 1e-9));
      expect(backB.y, closeTo(doc.y, 1e-9));
    });

    test('pan does not mutate geometry — 이동 후에도 같은 document 좌표로 정확히 되돌아온다', () {
      final fit = ContainFitTransform.compute(const Size(400, 300), const Size(400, 300));
      const doc = Point2(0.6, 0.2);
      final viewport = WorkspaceViewportTransform.identity.panBy(const Offset(80, -40));

      final screen = documentToScreen(doc, fit, viewport);
      final back = screenToDocument(screen, fit, viewport)!;
      expect(back.x, closeTo(doc.x, 1e-9));
      expect(back.y, closeTo(doc.y, 1e-9));
    });

    test('drawing under zoom stores correct document coordinate — 확대된 상태에서 화면을 탭하면 정확한 document 좌표로 변환된다', () {
      final fit = ContainFitTransform.compute(const Size(400, 300), const Size(400, 300));
      // 2배 확대 + (50,50) 이동된 상태에서 화면 좌표 (250,200)을 탭했다고 가정.
      const viewport = WorkspaceViewportTransform(scale: 2.0, offset: Offset(50, 50));
      final doc = screenToDocument(const Offset(250, 200), fit, viewport)!;

      // 역으로 검증: 이 document 좌표를 다시 같은 변환으로 화면에 옮기면
      // 원래 탭 위치(250,200)로 정확히 돌아와야 한다.
      final backToScreen = documentToScreen(doc, fit, viewport);
      expect(backToScreen.dx, closeTo(250, 1e-9));
      expect(backToScreen.dy, closeTo(200, 1e-9));
    });
  });
}
