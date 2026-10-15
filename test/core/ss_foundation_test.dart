// SS001 §21 검증 — 공통 기반(Route·3 FLOW·프로젝트 데이터·자동저장/복원·History·AI 오류/재시도·단계 변경 추적·선택·단위·입력·내보내기).
import 'dart:io';

import 'package:ason_space/core/ss_ai_task.dart';
import 'package:ason_space/core/ss_editing.dart';
import 'package:ason_space/core/ss_history.dart';
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Route 구조·MASTER UI 매핑(§4.2, §22-2)', () {
    test('17개 단계가 모두 있고 Route 이름이 겹치지 않으며, 모두 MASTER UI와 담당 Work Order가 있다', () {
      expect(SsStage.values, hasLength(17));
      expect(SsStage.values.map((s) => s.routeName).toSet(), hasLength(17));
      for (final s in SsStage.values) {
        expect(s.masterUi, isNotEmpty, reason: s.name);
        expect(s.workOrder, matches(RegExp(r'^SS0\d\d$')), reason: s.name);
        expect(s.whatIsThis, isNotEmpty, reason: '3초 법칙: 무엇을 하는 화면');
        expect(s.whatNext, isNotEmpty, reason: '3초 법칙: 다음에 무엇');
        expect(SsStage.fromRoute(s.routeName), s);
      }
      // MASTER UI 1~12 + 4-1/4-2 계열이 모두 단계에 연결된다
      const master = ['1', '2', '3', '4', '4-1', '4-2', '4-2-1', '4-2-2', '5', '6', '7', '8', '9', '10', '11', '12'];
      expect(SsStage.values.map((s) => s.masterUi).toSet().containsAll(master), isTrue);
    });
  });

  group('3가지 작업 FLOW(§2)', () {
    test('평면도 업로드·직접 그리기는 CAD → 3D ISO → 결과로, 이미지 변환은 CAD/3D와 분리된다', () {
      expect(SsFlows.firstStage(SsSourceType.floorPlanUpload), SsStage.floorPlanUpload);
      expect(SsFlows.firstStage(SsSourceType.directDraw), SsStage.directDrawing);
      expect(SsFlows.firstStage(SsSourceType.imageTransform), SsStage.imageEditing);
      expect(SsFlows.next(SsSourceType.floorPlanUpload, SsStage.floorPlanReview), SsStage.cadConversion);
      expect(SsFlows.next(SsSourceType.directDraw, SsStage.directDrawing), SsStage.cadConversion, reason: '직접 그리기는 CAD 작업 흐름으로 연결');
      expect(SsFlows.stages[SsSourceType.floorPlanUpload]!.last, SsStage.finalResult);
      final image = SsFlows.stages[SsSourceType.imageTransform]!;
      expect(image, [SsStage.imageEditing, SsStage.imageRendering, SsStage.imageResult]);
      expect(image.any((s) => SsFlows.stages[SsSourceType.floorPlanUpload]!.contains(s)), isFalse);
      expect(SsFlows.next(SsSourceType.imageTransform, SsStage.imageResult), isNull);
      expect(SsFlows.previous(SsSourceType.directDraw, SsStage.directDrawing), isNull);
    });

    test('좌측 Navigation은 같은 디자인에서 단계에 필요한 항목만 켠다(§16)', () {
      expect(SsNavigation.enabledFor(SsStage.login), isEmpty);
      expect(SsNavigation.enabledFor(SsStage.home), isNot(contains(SsNavItem.save)));
      expect(SsNavigation.enabledFor(SsStage.imageEditing), containsAll({SsNavItem.save, SsNavItem.export}));
      expect(SsNavigation.enabledFor(SsStage.imageEditing), isNot(contains(SsNavItem.view3d)));
      expect(SsNavigation.enabledFor(SsStage.cadEditor), contains(SsNavItem.view2d));
      expect(SsNavigation.enabledFor(SsStage.isoEditor), containsAll({SsNavItem.view2d, SsNavItem.view3d}));
    });
  });

  group('프로젝트 공통 데이터(§5, §9)', () {
    final t0 = DateTime(2026, 10, 15, 9);

    test('새 프로젝트는 시작 방식의 첫 단계에서 시작하고, 다른 FLOW 단계로는 갈 수 없다', () {
      final p = SsProject.create(id: 'p1', name: '거실', sourceType: SsSourceType.directDraw, now: t0);
      expect(p.currentStage, SsStage.directDrawing);
      expect(p.moveTo(SsStage.cadEditor).currentStage, SsStage.cadEditor);
      expect(() => p.moveTo(SsStage.imageResult), throwsArgumentError);
    });

    test('원본은 한 번만 정하고 보존된다; 단계 칸은 서로 덮어쓰지 않고 revision이 오른다', () {
      var p = SsProject.create(id: 'p2', name: '안방', sourceType: SsSourceType.floorPlanUpload, now: t0);
      p = p.withSource({'file': 'plan.png'});
      expect(() => p.withSource({'file': 'other.png'}), throwsStateError);
      p = p.withStageData(SsDataSlot.recognitionData, {'rooms': 3}, label: 'AI 인식');
      p = p.withStageData(SsDataSlot.userCorrections, {'moved': 1}, label: '사용자 수정 1');
      p = p.withStageData(SsDataSlot.userCorrections, {'moved': 2}, label: '사용자 수정 2');
      expect(p[SsDataSlot.sourceData]!.payload, {'file': 'plan.png'});
      expect(p[SsDataSlot.recognitionData]!.payload, {'rooms': 3});
      expect(p[SsDataSlot.userCorrections]!.revision, 2);
      expect(p.history.map((h) => h.label), ['원본', 'AI 인식', '사용자 수정 1', '사용자 수정 2']);
    });

    test('CAD를 만든 뒤 평면도가 바뀌면 "CAD 업데이트 필요", CAD가 바뀌면 "3D 업데이트 필요"', () {
      var p = SsProject.create(id: 'p3', name: '주방', sourceType: SsSourceType.floorPlanUpload, now: t0);
      p = p.withSource({'f': 1}).withStageData(SsDataSlot.recognitionData, {'r': 1}, label: 'AI').withStageData(SsDataSlot.userCorrections, {'u': 1}, label: '수정');
      p = p.withStageData(SsDataSlot.cadData, {'c': 1}, label: 'CAD 변환');
      p = p.withStageData(SsDataSlot.isoData, {'i': 1}, label: 'ISO');
      expect(p.staleNotices(), isEmpty);
      p = p.withStageData(SsDataSlot.userCorrections, {'u': 2}, label: '평면도 수정');
      expect(p.staleNotices().map((n) => n.message), contains('평면도가 변경되었습니다. CAD를 업데이트해야 합니다.'));
      p = p.withStageData(SsDataSlot.cadData, {'c': 2}, label: 'CAD 다시 변환');
      final msgs = p.staleNotices().map((n) => n.message).toList();
      expect(msgs, contains('CAD가 변경되었습니다. 3D 모델을 업데이트해야 합니다.'));
      expect(msgs, isNot(contains('평면도가 변경되었습니다. CAD를 업데이트해야 합니다.')));
    });

    test('저장 형식으로 그대로 돌아온다(단계·칸·revision·근거·이력)', () {
      var p = SsProject.create(id: 'p4', name: '현관', sourceType: SsSourceType.imageTransform, now: t0);
      p = p.withSource({'photo': 'a.jpg'}).withStageData(SsDataSlot.renderData, {'img': 'r.png'}, label: 'AI 렌더링').moveTo(SsStage.imageResult);
      final back = SsProject.tryFromJson(p.toJson())!;
      expect(back.info.name, '현관');
      expect(back.sourceType, SsSourceType.imageTransform);
      expect(back.currentStage, SsStage.imageResult);
      expect(back[SsDataSlot.renderData]!.basedOn, {SsDataSlot.sourceData: 1});
      expect(back.history, hasLength(2));
      expect(SsProject.tryFromJson({'broken': true}), isNull);
    });
  });

  group('자동저장·복원(§6)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ss_store_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('파일 저장소: 저장한 마지막 단계에서 이어서 열고, 본 파일이 깨지면 마지막 정상 저장본으로 연다', () async {
      final store = FileSsProjectStore(dir);
      var p = SsProject.create(id: 'room/1', name: '방', sourceType: SsSourceType.floorPlanUpload).withSource({'f': 1});
      await store.save(p);
      p = p.moveTo(SsStage.cadEditor);
      await store.save(p);
      expect((await store.load('room/1'))!.currentStage, SsStage.cadEditor);
      // 쓰는 도중 깨진 상황
      File('${dir.path}${Platform.pathSeparator}room_1.json').writeAsStringSync('{"projectInfo":');
      final restored = await store.load('room/1');
      expect(restored, isNotNull, reason: '.bak(직전 정상본)으로 복원');
      expect(restored!.currentStage, SsStage.floorPlanUpload);
      expect(await store.list(), contains('room_1'));
    });

    test('자동저장 상태: 저장 대기 → 저장 중 → 저장 완료, 실패하면 "저장 실패"이고 작업은 그대로, 다시 시도하면 저장', () async {
      final store = MemorySsProjectStore();
      final p = SsProject.create(id: 'a1', name: 'A', sourceType: SsSourceType.directDraw);
      final c = SsAutosaveController(store: store, project: p, delay: const Duration(milliseconds: 10));
      final seen = <SsSaveState>[];
      c.addListener(() => seen.add(c.state));
      c.update(p.withStageData(SsDataSlot.userCorrections, {'w': 1}, label: '벽 그림'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(seen, [SsSaveState.dirty, SsSaveState.saving, SsSaveState.saved]);
      store.failNextSave = true;
      c.update(c.project.moveTo(SsStage.cadConversion));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.state, SsSaveState.failed);
      expect(c.project.currentStage, SsStage.cadConversion, reason: '저장이 실패해도 메모리 작업은 남는다');
      expect(await c.retry(), isTrue);
      expect(c.state, SsSaveState.saved);
      c.dispose();
      // 앱을 다시 열면 마지막 프로젝트·단계에서
      final again = (await SsAutosaveController.restoreLast(store))!;
      expect(again.project.currentStage, SsStage.cadConversion);
      expect(again.project[SsDataSlot.userCorrections]!.payload, {'w': 1});
      again.dispose();
    });
  });

  group('작업 이력 Undo/Redo(§7)', () {
    test('원본 → AI 결과 → 사용자 수정 n, 되돌리기/다시하기, 새로 고치면 다시하기는 버린다', () {
      final h = SsHistory<int>(original: 0);
      h.push(10, kind: SsHistoryKind.aiResult);
      h.push(11);
      h.push(12);
      expect(h.steps.map((s) => s.label), ['원본', 'AI 결과', '사용자 수정 1', '사용자 수정 2']);
      expect(h.undo(), 11);
      expect(h.undo(), 10);
      expect(h.redo(), 11);
      h.push(20);
      expect(h.canRedo, isFalse);
      expect(h.steps.map((s) => s.state), [0, 10, 11, 20]);
    });

    test('마지막 정상 상태로 복원하고, 용량을 넘어도 원본은 남는다', () {
      final h = SsHistory<String>(original: 'orig', capacity: 3);
      h.push('ok1');
      h.push('bad', good: false);
      expect(h.restoreLastGood(), 'ok1');
      h.push('a');
      h.push('b');
      expect(h.steps.first.state, 'orig');
      expect(h.steps, hasLength(3));
      expect(h.jumpTo(0), 'orig');
    });
  });

  group('AI 오류·재시도(§8)', () {
    test('실패해도 이전 결과를 잃지 않고, 다시 시도해 완료할 수 있다', () async {
      final task = SsAiTask<String>(name: '공간 인식', previousResult: '지난 인식');
      var calls = 0;
      expect(await task.run(() async => ++calls == 1 ? const SsAiOutcome<String>.retryable('일시적 오류') : const SsAiOutcome.completed('새 인식')), SsAiStatus.retryable);
      expect(task.lastGoodResult, '지난 인식');
      expect(task.canRetry, isTrue);
      expect(await task.retry(), SsAiStatus.completed);
      expect(task.lastGoodResult, '새 인식');
    });

    test('부분 완료·사용자 확인 필요·입력 수정 필요를 구분하고, 예외는 재시도 가능으로, 횟수를 넘으면 실패', () async {
      final t = SsAiTask<int>(name: 'CAD 변환', maxAttempts: 2);
      expect(await t.run(() async => const SsAiOutcome.partial(1, '벽 2개 인식 못 함')), SsAiStatus.partial);
      expect(await t.run(() async => const SsAiOutcome.needsUserCheck(2, '치수 확인 필요')), SsAiStatus.needsUserCheck);
      expect(await t.run(() async => const SsAiOutcome<int>.inputFixNeeded('평면도가 흐립니다')), SsAiStatus.inputFixNeeded);
      expect(await t.run(() async => throw Exception('network')), SsAiStatus.retryable);
      expect(await t.retry(), SsAiStatus.failed, reason: '2번째 실패 — 횟수 초과');
      expect(t.canRetry, isFalse);
      expect(t.lastGoodResult, 2, reason: '실패해도 마지막 정상 결과 유지');
    });
  });

  group('선택·단위·입력·내보내기(§10~§13)', () {
    test('단위: 내부는 mm, 표시만 바꾼다; Grid 기본 100mm', () {
      const wall = SsLength.mm(3200);
      expect(wall.format(SsLengthUnit.mm), '3,200mm');
      expect(wall.format(SsLengthUnit.cm), '320.0cm');
      expect(wall.format(SsLengthUnit.m), '3.200m');
      expect(SsLength.of(1.5, SsLengthUnit.m).mm, 1500);
      expect(SsLength.gridDefault.mm, 100);
    });

    test('입력: Tab 손가락은 화면 이동, 펜·마우스는 그리기, 두 손가락은 확대/축소', () {
      expect(SsInput.kindOf(PointerDeviceKind.stylus), SsInputKind.stylus);
      expect(SsInput.primaryDrag(SsInputKind.touch, drawToolActive: true), SsGesture.pan);
      expect(SsInput.primaryDrag(SsInputKind.stylus, drawToolActive: true), SsGesture.draw);
      expect(SsInput.primaryDrag(SsInputKind.mouse, drawToolActive: false), SsGesture.drag);
      expect(SsInput.multiTouch, SsGesture.pinchZoom);
    });

    test('선택 표시와 내보내기 공통 형식', () {
      const sel = SsSelection(objectType: '벽', objectId: 'W12', properties: {'길이': '3,200mm'});
      expect(sel.summary(), '벽 W12 · 길이 3,200mm · 편집 가능');
      expect(SsSelection.none.summary(), '선택 없음');
      const job = SsExportJob(fileName: '거실/평면도', format: SsExportFormat.dxf);
      expect(job.fullName, '거실_평면도.dxf');
      expect(job.started().status, SsExportStatus.exporting);
      expect(job.failedWith('권한 없음').error, '권한 없음');
      expect(job.succeeded('/sdcard/x.dxf').location, '/sdcard/x.dxf');
    });
  });
}
