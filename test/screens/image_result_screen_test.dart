// SS007 — MASTER UI 4-2-2(이미지 변환 완료) 화면 위젯 테스트: 최종 이미지·Before/After 비교·내보내기
// 성공/실패 표시가 되는지 확인한다.
import 'dart:typed_data';

import 'package:ason_space/core/ss_editing.dart';
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/image_result_screen.dart';
import 'package:ason_space/services/ss_image_export_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

class _FakeExportService extends SsImageExportService {
  const _FakeExportService({this.fail = false});
  final bool fail;

  @override
  Future<String?> save(Uint8List pngBytes, SsExportJob job, {int jpgQuality = 90, bool chooseLocation = false}) async {
    if (fail) throw Exception('저장 실패(시험)');
    return '/fake/path/${job.fullName}';
  }
}

void main() {
  late MemorySsProjectStore store;

  setUp(() async {
    store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: '결과 테스트', sourceType: SsSourceType.imageTransform, now: DateTime(2026, 1, 1));
    project = project.withSource({'imageBase64': _tinyPngBase64}, label: '원본 사진');
    project = project.withStageData(SsDataSlot.renderData, {'imageBase64': _tinyPngBase64}, label: 'AI 렌더링 결과');
    await store.save(project);
  });

  Future<void> pump(WidgetTester tester, {SsImageExportService exportService = const SsImageExportService()}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ImageResultScreen(projectId: 'p1', projectStore: store, exportService: exportService))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('최종 이미지와 완료하기·수정 작업으로 돌아가기 버튼이 보인다', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('ssResultFinalImage')), findsOneWidget);
    expect(find.byKey(const Key('ssResultComplete')), findsOneWidget);
    expect(find.byKey(const Key('ssResultBackToEdit')), findsOneWidget);
  });

  testWidgets('Before/After 비교 토글을 누르면 원본과 결과가 함께 보인다', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('ssResultCompareToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssResultBeforeImage')), findsOneWidget);
    expect(find.byKey(const Key('ssResultAfterImage')), findsOneWidget);
  });

  testWidgets('내보내기를 누르면 성공 상태가 표시된다', (tester) async {
    await pump(tester, exportService: const _FakeExportService());
    await tester.tap(find.byKey(const Key('ssResultExportButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssResultExportStatus')), findsOneWidget);
  });

  testWidgets('내보내기가 실패해도 네트워크 오류로 표시하지 않고 다시 시도할 수 있다', (tester) async {
    await pump(tester, exportService: const _FakeExportService(fail: true));
    await tester.tap(find.byKey(const Key('ssResultExportButton')));
    await tester.pumpAndSettle();

    final statusText = tester.widget<Text>(
      find.descendant(of: find.byKey(const Key('ssResultExportStatus')), matching: find.byType(Text)),
    );
    expect(statusText.data, isNot(contains('네트워크')));

    final button = tester.widget<ElevatedButton>(find.byKey(const Key('ssResultExportButton')));
    expect(button.onPressed, isNotNull);
  });
}
