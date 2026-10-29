// SS005 — 구조화 데이터(SsDrawScene) 단위 테스트: 벽/개구부 생성·수정·삭제, 투영, JSON 왕복.
import 'package:ason_space/models/ss_draw_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SsDrawWall', () {
    test('길이·벽 위의 점·투영이 정확하다', () {
      const w = SsDrawWall(id: 1, a: SsDrawPoint(0, 0), b: SsDrawPoint(1000, 0));
      expect(w.lengthMm, 1000);
      expect(w.pointAt(400), const SsDrawPoint(400, 0));
      final (along, dist) = w.project(const SsDrawPoint(300, 50));
      expect(along, 300);
      expect(dist, 50);
    });

    test('JSON 왕복', () {
      const w = SsDrawWall(id: 3, a: SsDrawPoint(10, 20), b: SsDrawPoint(30, 40), type: SsDrawWallType.exterior, thicknessMm: 200);
      final back = SsDrawWall.tryFromJson(w.toJson())!;
      expect(back.id, 3);
      expect(back.a, const SsDrawPoint(10, 20));
      expect(back.type, SsDrawWallType.exterior);
      expect(back.thicknessMm, 200);
    });
  });

  group('SsDrawScene', () {
    test('벽 추가·수정·삭제(개구부도 함께 지워진다)', () {
      var scene = SsDrawScene.empty.addWall(const SsDrawPoint(0, 0), const SsDrawPoint(1000, 0));
      expect(scene.walls, hasLength(1));
      expect(scene.nextId, 2);
      scene = scene.addOpening(1, SsDrawOpeningKind.door, 400);
      expect(scene.openings, hasLength(1));
      scene = scene.updateWall(1, (w) => w.copyWith(thicknessMm: 300));
      expect(scene.wall(1)!.thicknessMm, 300);
      scene = scene.removeWall(1);
      expect(scene.walls, isEmpty);
      expect(scene.openings, isEmpty, reason: '벽이 사라지면 그 위의 개구부도 함께 사라진다');
    });

    test('JSON 왕복(빈 값/깨진 값은 빈 평면도)', () {
      final scene = SsDrawScene.empty.addWall(const SsDrawPoint(0, 0), const SsDrawPoint(500, 0)).addOpening(1, SsDrawOpeningKind.window, 200);
      final json = scene.toJson();
      final back = SsDrawScene.tryFromJson(json);
      expect(back.walls, hasLength(1));
      expect(back.openings, hasLength(1));
      expect(SsDrawScene.tryFromJson(null), SsDrawScene.empty);
      expect(SsDrawScene.tryFromJson('broken').isEmpty, isTrue);
    });
  });
}
