// WorkspaceScreen(4번 화면, 공간 작업실)에 대한 위젯 테스트.
//
// 1. 작업 부위를 선택하면 강조 상태와 질문 문구가 바뀐다.
// 2. 사진 위에서 드래그하면 선택 영역 정보가 표시된다.
// 3. "다른 부분 작업 추가"를 누르면 작업 목록에 추가되고 입력값이 초기화된다.
// 4. 참고 이미지를 추가/제거할 수 있다.
// 5. 필수 정보가 없으면 안내만 표시하고 다음 화면으로 넘어가지 않는다.
// 6. 하루 무료 한도를 채우면 안내 다이얼로그가 뜨고 진행되지 않는다.
// 7. 선택 영역 + 작업 지시를 채워 제출하면 AI 생성을 거쳐 결과 화면까지
//    작업 지시 데이터가 그대로 전달된다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/screens/workspace_screen.dart';
import 'package:ason_space/services/image_picker_service.dart';
import 'package:ason_space/services/usage_policy_service.dart';
import 'package:ason_space/widgets/reference_image_picker.dart';
import 'package:ason_space/widgets/region_selector.dart';

final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _FakeImagePickerService extends ImagePickerService {
  const _FakeImagePickerService(this._bytes);
  final Uint8List _bytes;

  @override
  Future<Uint8List?> pickGalleryImage() async => _bytes;
}

Future<void> _drawSelection(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(RegionSelector));
  await tester.pump();
  await tester.drag(find.byType(RegionSelector), const Offset(160, 120));
  await tester.pump();
}

Future<void> _tapCta(WidgetTester tester) async {
  await tester.ensureVisible(find.text('공간의 변화 만들기'));
  await tester.pump();
  await tester.tap(find.text('공간의 변화 만들기'));
}

void main() {
  setUp(() {
    UsagePolicyService.instance.resetForTesting();
  });

  testWidgets('작업 부위를 선택하면 강조 상태와 질문 문구가 바뀐다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 기본 선택 부위는 '벽'이다.
    expect(find.text('선택한 벽 부분을 어떻게 바꾸고 싶으세요?'), findsOneWidget);

    await tester.ensureVisible(find.text('천장'));
    await tester.tap(find.text('천장'));
    await tester.pump();

    expect(find.text('선택한 천장 부분을 어떻게 바꾸고 싶으세요?'), findsOneWidget);
  });

  testWidgets('사진 위에서 드래그하면 선택 영역 정보가 표시된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('사진 위에서 손가락(또는 마우스)으로 드래그해 변경하고 싶은 부분을 선택해주세요.'),
      findsOneWidget,
    );
    expect(find.text('선택 영역'), findsNothing);

    await _drawSelection(tester);

    expect(find.text('선택 영역'), findsOneWidget);
  });

  testWidgets('작업 지시를 입력하고 다른 부분 작업 추가를 누르면 작업 목록에 추가된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _drawSelection(tester);
    await tester.enterText(
      find.byType(TextField).first,
      '좌측 벽 부분을 밝은 아이보리 컬러로 변경해주세요.',
    );
    await tester.pump();

    await tester.ensureVisible(find.text('다른 부분 작업 추가'));
    await tester.tap(find.text('다른 부분 작업 추가'));
    await tester.pump();

    expect(find.text('작업 목록'), findsOneWidget);
    expect(find.textContaining('작업 1 · 벽'), findsOneWidget);

    // 추가 후에는 draft가 초기화되어 다시 안내 문구가 보인다.
    expect(
      find.text('사진 위에서 손가락(또는 마우스)으로 드래그해 변경하고 싶은 부분을 선택해주세요.'),
      findsOneWidget,
    );
    final textField = tester.widget<TextField>(find.byType(TextField).first);
    expect(textField.controller?.text, isEmpty);
  });

  testWidgets('참고 이미지를 추가하고 제거할 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
          imagePickerService: _FakeImagePickerService(_fakeImageBytes),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addFinder = find.descendant(
      of: find.byType(ReferenceImagePicker),
      matching: find.byIcon(Icons.add_rounded),
    );
    await tester.ensureVisible(addFinder);
    await tester.pump();
    await tester.tap(addFinder);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('필수 정보가 없으면 안내만 표시하고 다음 화면으로 넘어가지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapCta(tester);
    await tester.pump();

    expect(find.text('먼저 사진 위에서 변경하고 싶은 부분을 선택해주세요.'), findsOneWidget);
    expect(find.text('AI 생성'), findsNothing);

    // 영역은 선택했지만 지시문이 비어 있으면 다른 안내를 준다.
    await _drawSelection(tester);
    await _tapCta(tester);
    await tester.pump();

    expect(find.text('선택한 부분을 어떻게 바꾸고 싶은지 입력해주세요.'), findsOneWidget);
    expect(find.text('AI 생성'), findsNothing);
  });

  testWidgets('하루 무료 한도를 모두 사용하면 한도 초과 안내가 뜨고 진행되지 않는다', (tester) async {
    for (var i = 0; i < UsagePolicyService.freeDailyLimit; i++) {
      UsagePolicyService.instance.recordGeneration();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _drawSelection(tester);
    await tester.enterText(find.byType(TextField).first, '지시문');
    await tester.pump();

    await _tapCta(tester);
    await tester.pumpAndSettle();

    expect(find.text('오늘의 무료 생성 횟수를 모두 사용했어요'), findsOneWidget);
    expect(find.text('AI 생성'), findsNothing);
  });

  testWidgets('선택 영역과 작업 지시를 채워 제출하면 결과 화면까지 작업 지시가 전달된다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _drawSelection(tester);
    await tester.enterText(
      find.byType(TextField).first,
      '좌측 벽 부분을 밝은 아이보리 컬러로 변경해주세요.',
    );
    await tester.pump();

    await _tapCta(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AI 생성'), findsOneWidget);

    // Mock AiGenerationService는 3초 뒤 성공 응답을 반환한다.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('생성 결과'), findsOneWidget);
    expect(find.text('변경된 내용'), findsOneWidget);
    expect(find.textContaining('좌측 벽 부분을 밝은 아이보리 컬러로 변경해주세요.'), findsOneWidget);
  });
}
