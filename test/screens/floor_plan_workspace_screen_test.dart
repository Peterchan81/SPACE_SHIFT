// FloorPlanWorkspaceScreen(신규 MASTER 메인 작업 화면)의 라우팅/시작 방식
// 선택 동작 및 "① 평면도 업로드" 실제 파일 업로드 기능에 대한 위젯 테스트.
//
// 1. 로그인 이후 기본 진입점이 이 화면이며(다른 테스트에서 별도 검증),
//    좌측 "시작 방식 선택" 3가지가 모두 보이는지 확인한다.
// 2. "① 평면도 업로드"는 이미 선택된 상태로, 탭해도 화면 전환 없이 이
//    화면에 남아있는다.
// 3. "② 직접 그리기"는 아직 화면이 없어 준비중 SnackBar만 보여주고, 이
//    화면에 그대로 남아있는다.
// 4. "③ 사진으로 변환"은 기존 PhotoSelectScreen을 push로 불러오고, 뒤로
//    가기(pop)로 다시 이 화면으로 돌아올 수 있다.
// 5. 실사용 진입(demoMode: false, 기본값) 시 작업 목록/선택 항목이 비어
//    있다 — MASTER 미리보기용 demo 6개가 실사용 흐름에 섞이지 않는다.
// 6. 평면도 업로드 action(파일 선택 버튼)이 항상 노출된다.
// 7. 이미지 파일을 선택하면 중앙에 실제 preview와 상태가 반영된다.
// 8. "다시 선택"으로 다른 파일로 교체할 수 있다.
// 9. 2D → 3D → 2D 전환에도 선택한 파일 상태가 유지되고, 3D에서는 정직한
//    준비 안내만 보여준다.
// 10. 파일 선택을 취소해도(null 반환) crash 없이 업로드 이전 상태를 유지한다.
// 11. 좌측 하단 "설정" 버튼이 노출되고, 탭하면 SettingsScreen으로
//     진입하며, 뒤로가기로 이 화면으로 돌아오면 업로드한 평면도/View
//     선택 상태가 유지된다(MASTER 공통 기능, WO 2/12/13).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:ason_space/models/floor_plan_file.dart';
import 'package:ason_space/screens/floor_plan_workspace_screen.dart';
import 'package:ason_space/screens/photo_select_screen.dart';
import 'package:ason_space/screens/settings_screen.dart';
import 'package:ason_space/services/floor_plan_upload_service.dart';

/// 실제 플랫폼 파일 선택창 대신, 미리 정해진 결과를 순서대로 반환하는
/// 가짜 서비스. 취소를 흉내내려면 목록에 null을 넣으면 된다.
class _FakeFloorPlanUploadService extends FloorPlanUploadService {
  _FakeFloorPlanUploadService(this._results);

  final List<FloorPlanFile?> _results;
  int _index = 0;

  @override
  Future<FloorPlanFile?> pickFloorPlanFile() async {
    final result = _index < _results.length ? _results[_index] : null;
    _index++;
    return result;
  }
}

/// 위젯 테스트에서 Image.memory가 실제로 디코딩 가능한 1x1 PNG.
final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

FloorPlanFile _fakeImageFile(String name) => FloorPlanFile(
  fileName: name,
  extension: 'png',
  kind: FloorPlanFileKind.image,
  sizeBytes: _fakeImageBytes.length,
  bytes: _fakeImageBytes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // SettingsScreen이 내부에서 PackageInfo.fromPlatform()을 호출하므로,
    // 좌측 하단 "설정" 진입 테스트를 위해 미리 mock 값을 채워 둔다.
    PackageInfo.setMockInitialValues(
      appName: 'SPACE SHIFT',
      packageName: 'com.example.ason_space',
      version: '1.0.0',
      buildNumber: '2016',
      buildSignature: '',
    );
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    FloorPlanUploadService uploadService = const FloorPlanUploadService(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: FloorPlanWorkspaceScreen(uploadService: uploadService)),
    );
    await tester.pump();
  }

  testWidgets('좌측 시작 방식 선택 3가지가 모두 보인다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('평면도 업로드'), findsOneWidget);
    expect(find.text('직접 그리기'), findsOneWidget);
    expect(find.text('사진으로 변환'), findsOneWidget);
  });

  testWidgets('"직접 그리기"를 탭하면 준비중 안내만 보여주고 이 화면에 남는다', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('직접 그리기'));
    await tester.pump();

    expect(find.textContaining('준비 중입니다'), findsOneWidget);
    expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
    expect(find.byType(PhotoSelectScreen), findsNothing);
  });

  testWidgets('"사진으로 변환"을 탭하면 기존 PhotoSelectScreen이 열리고, 뒤로가기로 돌아올 수 있다', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('사진으로 변환'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoSelectScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
    expect(find.byType(PhotoSelectScreen), findsNothing);
  });

  testWidgets('실사용 진입 시 작업 목록/선택 항목이 비어 있다(demo 데이터가 섞이지 않는다)', (tester) async {
    await pumpScreen(tester);

    expect(find.text('아직 등록된 작업이 없습니다.'), findsOneWidget);
    expect(find.text('선택된 항목이 없습니다.\n평면도에서 작업할 영역을 선택해주세요.'), findsOneWidget);
    expect(find.text('거실 벽 (TV 벽체)'), findsNothing);
  });

  testWidgets('평면도 업로드 action(파일 선택 버튼)이 노출된다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('평면도를 업로드해주세요'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '파일 선택'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '평면도 선택'), findsOneWidget);
  });

  testWidgets('이미지 파일을 선택하면 중앙에 실제 preview와 상태가 반영된다', (tester) async {
    final service = _FakeFloorPlanUploadService([
      _fakeImageFile('floor_plan_1.png'),
    ]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();

    expect(find.textContaining('평면도가 선택되었습니다'), findsOneWidget);
    expect(find.textContaining('floor_plan_1.png'), findsWidgets);
    expect(find.text('평면도 분석 시작'), findsOneWidget);
    expect(find.text('평면도를 업로드해주세요'), findsNothing);
  });

  testWidgets('"다시 선택"으로 다른 파일로 교체할 수 있다', (tester) async {
    final service = _FakeFloorPlanUploadService([
      _fakeImageFile('floor_plan_1.png'),
      _fakeImageFile('floor_plan_2.png'),
    ]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    expect(find.textContaining('floor_plan_1.png'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, '다시 선택'));
    await tester.pumpAndSettle();

    expect(find.textContaining('floor_plan_2.png'), findsWidgets);
    expect(find.textContaining('floor_plan_1.png'), findsNothing);
  });

  testWidgets('2D → 3D → 2D 전환에도 선택한 파일 상태가 유지되고, 3D에서는 준비 안내만 보여준다', (
    tester,
  ) async {
    final service = _FakeFloorPlanUploadService([
      _fakeImageFile('floor_plan_1.png'),
    ]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    expect(find.textContaining('평면도가 선택되었습니다'), findsOneWidget);

    await tester.tap(find.text('3D 아이소'));
    await tester.pump();

    expect(find.text('3D 공간이 아직 생성되지 않았습니다'), findsOneWidget);
    expect(find.textContaining('평면도가 선택되었습니다'), findsNothing);

    await tester.tap(find.text('2D 평면도'));
    await tester.pump();

    // 3D를 다녀왔어도 업로드한 파일 상태 자체는 그대로 남아있다.
    expect(find.textContaining('평면도가 선택되었습니다'), findsOneWidget);
    expect(find.textContaining('floor_plan_1.png'), findsWidgets);
  });

  testWidgets('파일 선택을 취소해도 crash 없이 업로드 이전 상태를 유지한다', (tester) async {
    final service = _FakeFloorPlanUploadService([null]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('평면도를 업로드해주세요'), findsOneWidget);
  });

  testWidgets('좌측 하단 "설정" 버튼이 노출된다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('설정'), findsOneWidget);
  });

  testWidgets('"설정"을 탭하면 SettingsScreen으로 진입하고, 뒤로가기로 이 화면으로 돌아온다', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
  });

  testWidgets('설정 진입 후 돌아와도 업로드한 평면도와 선택한 View 상태가 유지된다', (tester) async {
    final service = _FakeFloorPlanUploadService([
      _fakeImageFile('floor_plan_1.png'),
    ]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3D 아이소'));
    await tester.pump();
    expect(find.text('3D 공간이 아직 생성되지 않았습니다'), findsOneWidget);

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 설정 화면을 다녀와도 workspace의 State가 그대로 유지되어, 업로드한
    // 파일과 선택했던 View(3D 아이소)가 초기화되지 않는다.
    expect(find.text('3D 공간이 아직 생성되지 않았습니다'), findsOneWidget);
    await tester.tap(find.text('2D 평면도'));
    await tester.pump();
    expect(find.textContaining('floor_plan_1.png'), findsWidgets);
  });
}
