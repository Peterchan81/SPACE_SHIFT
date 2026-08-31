// 공간 작업실(SpaceWorkshopScreen)에 대한 위젯 테스트.
//
// 1. 작업을 하나도 등록하지 않으면 "공간의 변화 만들기"가 동작하지 않는다.
// 2. 영역을 그려 작업을 등록하면 작업 카드가 생기고, 변경 내용 텍스트를
//    입력해야만 AI 생성으로 진행할 수 있다. (복수 작업 등록 포함)
// 3. 작업을 삭제하면 카드가 사라지고 등록 전 안내 문구로 돌아간다.
// 4. 수정 재요청 등으로 재진입할 때 전달되는 initialTasks가 그대로
//    이어서 표시된다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/space_task.dart';
import 'package:ason_space/screens/space_workshop_screen.dart';
import 'package:ason_space/services/image_picker_service.dart';
import 'package:ason_space/widgets/space_canvas.dart';

final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

final Uint8List _fakeReferenceImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

class _FakeImagePickerService extends ImagePickerService {
  const _FakeImagePickerService(this._bytes);

  final Uint8List? _bytes;

  @override
  Future<Uint8List?> pickGalleryImage() async => _bytes;
}

Future<void> _drawRegion(
  WidgetTester tester, [
  Offset offset = const Offset(100, 80),
]) async {
  await tester.drag(find.byType(SpaceCanvas), offset);
  await tester.pump();
}

void main() {
  testWidgets('작업을 등록하지 않으면 공간의 변화 만들기 버튼이 동작하지 않는다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SpaceWorkshopScreen(imageBytes: _fakeImageBytes)),
    );

    await tester.ensureVisible(find.text('공간의 변화 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('공간의 변화 만들기'));
    await tester.pump();

    expect(find.text('AI 생성'), findsNothing);
  });

  testWidgets(
    '영역을 선택하고 작업을 추가하면 작업 카드가 생기고, 텍스트를 입력해야 '
    '공간의 변화 만들기가 동작한다',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SpaceWorkshopScreen(imageBytes: _fakeImageBytes)),
      );

      await _drawRegion(tester);
      await tester.ensureVisible(find.text('이 영역으로 작업 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이 영역으로 작업 추가'));
      await tester.pump();

      expect(find.text('작업 1 · 전체'), findsOneWidget);

      // 텍스트를 입력하지 않은 상태에서는 진행되지 않는다.
      await tester.ensureVisible(find.text('공간의 변화 만들기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('공간의 변화 만들기'));
      await tester.pump();
      expect(find.text('AI 생성'), findsNothing);

      await tester.enterText(find.byType(TextField), '천장에 간접조명을 추가해줘');
      await tester.pump();

      await tester.ensureVisible(find.text('공간의 변화 만들기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('공간의 변화 만들기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('AI 생성'), findsOneWidget);

      // AiGenerationService(Mock)의 3초 지연 Timer를 흘려보내 테스트 종료 시
      // "Pending timers" 오류가 나지 않게 한다.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    },
  );

  testWidgets('작업을 삭제하면 카드가 사라지고 등록 전 안내로 돌아간다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SpaceWorkshopScreen(imageBytes: _fakeImageBytes)),
    );

    await _drawRegion(tester);
    await tester.ensureVisible(find.text('이 영역으로 작업 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 영역으로 작업 추가'));
    await tester.pump();

    expect(find.text('작업 1 · 전체'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();

    expect(find.text('작업 1 · 전체'), findsNothing);
    expect(
      find.text('먼저 사진 위에서 영역을 하나 이상 선택해 작업을 등록해주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('initialTasks로 재진입하면 기존 작업이 그대로 이어서 표시된다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SpaceWorkshopScreen(
          imageBytes: _fakeImageBytes,
          initialTasks: const [
            SpaceTask(
              id: 'existing',
              category: SpaceCategory.floor,
              rect: NormalizedRect(
                left: 0.1,
                top: 0.6,
                width: 0.4,
                height: 0.3,
              ),
              instruction: '바닥을 밝은 오크로 변경해줘',
            ),
          ],
        ),
      ),
    );

    expect(find.text('작업 1 · 바닥'), findsOneWidget);
    expect(find.text('바닥을 밝은 오크로 변경해줘'), findsOneWidget);
  });

  testWidgets('작업 카드에서 참고 이미지를 선택하면 썸네일이 표시되고, 제거하면 다시 첨부 버튼이 보인다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SpaceWorkshopScreen(
          imageBytes: _fakeImageBytes,
          imagePickerService: _FakeImagePickerService(
            _fakeReferenceImageBytes,
          ),
        ),
      ),
    );

    await _drawRegion(tester);
    await tester.ensureVisible(find.text('이 영역으로 작업 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 영역으로 작업 추가'));
    await tester.pump();

    expect(find.text('참고 이미지 첨부'), findsOneWidget);

    await tester.ensureVisible(find.text('참고 이미지 첨부'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('참고 이미지 첨부'));
    await tester.pumpAndSettle();

    expect(find.text('참고 이미지 첨부'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(find.text('참고 이미지 첨부'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });
}
