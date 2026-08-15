// SPACE SHIFT 화면 이동 흐름 및 사진 선택(갤러리/카메라) 기능에 대한 위젯 테스트.
//
// image_picker는 실제 플랫폼 선택창을 위젯 테스트에서 직접 열 수 없으므로,
// ImagePickerService를 상속한 가짜 구현으로 이미지 데이터(또는 취소/예외)를
// 주입해 테스트한다.
//
// 1. 스플래시 화면 -> 사진 선택 화면 이동을 확인한다.
// 2. 사진이 없을 때 스타일 선택하기 버튼이 비활성화되는지 확인한다.
// 3. 가짜 갤러리/카메라 이미지를 선택하면 미리보기와 출처 안내가 표시되고,
//    스타일 선택하기 버튼이 활성화되는지 확인한다.
// 4. 사진 선택 -> 스타일 선택 -> AI 생성(대기) -> 결과 화면으로 이어지는
//    흐름과, 선택한 사진/스타일이 결과 화면까지 전달되는지 확인한다.
// 5. 결과 화면의 저장하기/공유하기 SnackBar와 '다른 스타일로 다시 만들기'
//    이동이 정상 동작하는지 확인한다.
// 6. 카메라 촬영 취소 시 기존 사진이 유지되고, 실패 시 SnackBar가
//    표시되는지 확인한다.
// 7. 이미지 선택 중에는 카메라/갤러리 버튼이 모두 비활성화되어 중복
//    입력이 차단되는지 확인한다.
// 8. GenerateScreen이 AiGenerationService.generate()를 호출하고, 성공/실패
//    응답에 따라 결과 화면 이동 또는 SnackBar 표시로 이어지는지 확인한다.
// 9. ResultScreen은 generatedImageBytes가 없으면 AI 결과 카드에 기존
//    Placeholder를, 있으면 실제 이미지를 표시하는지 확인한다.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/main.dart';
import 'package:ason_space/models/ai_generation_request.dart';
import 'package:ason_space/models/ai_generation_response.dart';
import 'package:ason_space/screens/generate_screen.dart';
import 'package:ason_space/screens/photo_select_screen.dart';
import 'package:ason_space/screens/result_screen.dart';
import 'package:ason_space/services/ai_generation_service.dart';
import 'package:ason_space/services/image_picker_service.dart';
import 'package:ason_space/services/result_image_service.dart';

/// 테스트에서 사용하는 1x1 픽셀 PNG 이미지 바이트.
/// Image.memory가 실제로 디코딩 가능한 유효한 이미지 데이터가 필요하다.
final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// 실제 플랫폼 선택창 대신 미리 정해진 결과를 즉시 반환하는 가짜 서비스.
///
/// [galleryResult]/[cameraResult]로 각각 반환할 이미지(또는 취소를 뜻하는
/// null)를 지정하고, [throwOnGallery]/[throwOnCamera]로 예외 상황을
/// 흉내낼 수 있다.
class _FakeImagePickerService extends ImagePickerService {
  const _FakeImagePickerService({
    this.galleryResult,
    this.cameraResult,
    this.throwOnGallery = false,
    this.throwOnCamera = false,
  });

  final Uint8List? galleryResult;
  final Uint8List? cameraResult;
  final bool throwOnGallery;
  final bool throwOnCamera;

  @override
  Future<Uint8List?> pickGalleryImage() async {
    if (throwOnGallery) throw Exception('가짜 갤러리 오류');
    return galleryResult;
  }

  @override
  Future<Uint8List?> pickCameraImage() async {
    if (throwOnCamera) throw Exception('가짜 카메라 오류');
    return cameraResult;
  }
}

/// 호출은 기록하되, [release]를 호출하기 전까지 결과를 반환하지 않는
/// 가짜 서비스. 선택창이 열려 있는 동안의 중복 입력 차단을 테스트한다.
class _DelayedFakeImagePickerService extends ImagePickerService {
  _DelayedFakeImagePickerService(this._bytes);

  final Uint8List _bytes;
  final Completer<void> _gate = Completer<void>();

  int galleryCallCount = 0;
  int cameraCallCount = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<Uint8List?> pickGalleryImage() async {
    galleryCallCount++;
    await _gate.future;
    return _bytes;
  }

  @override
  Future<Uint8List?> pickCameraImage() async {
    cameraCallCount++;
    await _gate.future;
    return _bytes;
  }
}

/// 실제 3초 대기 없이 미리 정해진 응답을 즉시 반환하고, 호출 여부/횟수와
/// 마지막으로 전달받은 요청을 기록하는 가짜 AI 생성 서비스.
class _FakeAiGenerationService extends AiGenerationService {
  _FakeAiGenerationService(this._response);

  final AiGenerationResponse _response;

  int callCount = 0;
  AiGenerationRequest? lastRequest;

  @override
  Future<AiGenerationResponse> generate(AiGenerationRequest request) async {
    callCount++;
    lastRequest = request;
    return _response;
  }
}

/// 절대 완료되지 않는 AI 생성 서비스.
/// GenerateScreen이 응답을 기다리는 동안의 순차적 안내 문구 전환을
/// 시간 경과에 따라 관찰하기 위해 사용한다.
class _NeverCompletingAiGenerationService extends AiGenerationService {
  const _NeverCompletingAiGenerationService();

  @override
  Future<AiGenerationResponse> generate(AiGenerationRequest request) {
    return Completer<AiGenerationResponse>().future;
  }
}

class _FakeResultImageService extends ResultImageService {
  int saveCallCount = 0;
  int shareCallCount = 0;
  Uint8List? lastSavedBytes;
  Uint8List? lastSharedBytes;

  @override
  Future<void> save(Uint8List imageBytes) async {
    saveCallCount++;
    lastSavedBytes = imageBytes;
  }

  @override
  Future<void> share(Uint8List imageBytes) async {
    shareCallCount++;
    lastSharedBytes = imageBytes;
  }
}

/// PhotoSelectScreen을 가짜 갤러리 이미지 선택 서비스와 함께 단독으로
/// 그린 뒤, 갤러리에서 선택 버튼을 눌러 사진이 선택된 상태로 만든다.
Future<void> _pumpPhotoSelectScreenWithFakeGalleryImage(
  WidgetTester tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PhotoSelectScreen(
        imagePickerService: _FakeImagePickerService(
          galleryResult: _fakeImageBytes,
        ),
      ),
    ),
  );

  await tester.ensureVisible(find.text('갤러리에서 선택'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('갤러리에서 선택'));
  await tester.pumpAndSettle();
}

/// PhotoSelectScreen을 가짜 카메라 촬영 서비스와 함께 단독으로 그린 뒤,
/// 카메라로 촬영 버튼을 눌러 사진이 선택된 상태로 만든다.
Future<void> _pumpPhotoSelectScreenWithFakeCameraImage(
  WidgetTester tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PhotoSelectScreen(
        imagePickerService: _FakeImagePickerService(
          cameraResult: _fakeImageBytes,
        ),
      ),
    ),
  );

  await tester.ensureVisible(find.text('카메라로 촬영'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('카메라로 촬영'));
  await tester.pumpAndSettle();
}

/// PhotoSelectScreen에서 이미 사진이 선택된 상태를 가정하고,
/// 스타일 선택 -> AI 생성 대기 -> 결과 화면 도착까지 진행한다.
Future<void> _proceedToResultScreen(WidgetTester tester) async {
  await tester.ensureVisible(find.text('스타일 선택하기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('스타일 선택하기'));
  await tester.pumpAndSettle();

  // 스타일 카드 하나를 선택한다.
  await tester.tap(find.text('모던'));
  await tester.pump();

  // AI로 공간 만들기 버튼을 누르면 AI 생성(대기) 화면으로 이동
  await tester.ensureVisible(find.text('AI로 공간 만들기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('AI로 공간 만들기'));
  // CircularProgressIndicator는 무한 반복 애니메이션이므로 pumpAndSettle 대신
  // 화면 전환 애니메이션만큼만 진행한다.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  expect(find.text('AI 생성'), findsOneWidget);
  // 아직 1초가 지나지 않았으므로 첫 번째 안내 문구가 표시된다.
  expect(find.text('사진을 분석하고 있습니다...'), findsOneWidget);

  // 3초 후 자동으로 결과 화면으로 이동한다.
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 갤러리에서 사진을 선택하고 스타일까지 고른 뒤 결과 화면에 도착하기까지의
/// 공통 절차. Splash 화면은 사진 선택과 무관하므로 거치지 않는다.
Future<void> _pumpToResultScreen(WidgetTester tester) async {
  await _pumpPhotoSelectScreenWithFakeGalleryImage(tester);
  await _proceedToResultScreen(tester);
}

void main() {
  testWidgets('스플래시 화면에서 시작하기를 누르면 사진 선택 화면으로 이동한다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AsonSpaceApp());

    expect(find.text('SPACE SHIFT'), findsOneWidget);
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();

    expect(find.text('사진 선택'), findsOneWidget);
    expect(find.text('우리 집 사진을 선택해주세요'), findsOneWidget);
    expect(find.text('선택된 사진이 없습니다'), findsOneWidget);
  });

  testWidgets('사진이 없을 때 스타일 선택하기 버튼이 비활성화된다', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PhotoSelectScreen()));

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('가짜 갤러리 이미지를 선택하면 미리보기와 출처가 표시된다', (WidgetTester tester) async {
    await _pumpPhotoSelectScreenWithFakeGalleryImage(tester);

    expect(find.text('선택된 사진이 없습니다'), findsNothing);
    expect(find.text('사진이 선택되었습니다.'), findsOneWidget);
    expect(find.text('갤러리에서 선택한 사진'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('갤러리 사진 선택 후 스타일 선택하기 버튼이 활성화된다', (WidgetTester tester) async {
    await _pumpPhotoSelectScreenWithFakeGalleryImage(tester);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('가짜 카메라 이미지를 선택하면 미리보기와 출처가 표시된다', (WidgetTester tester) async {
    await _pumpPhotoSelectScreenWithFakeCameraImage(tester);

    expect(find.text('선택된 사진이 없습니다'), findsNothing);
    expect(find.text('사진이 선택되었습니다.'), findsOneWidget);
    expect(find.text('카메라로 촬영한 사진'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('카메라 사진 선택 후 스타일 선택하기 버튼이 활성화된다', (WidgetTester tester) async {
    await _pumpPhotoSelectScreenWithFakeCameraImage(tester);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('카메라 촬영을 취소하면 기존에 선택되어 있던 사진이 그대로 유지된다', (
    WidgetTester tester,
  ) async {
    final fakeService = _FakeImagePickerService(
      galleryResult: _fakeImageBytes,
      // cameraResult를 지정하지 않으면 촬영 취소(null 반환)를 의미한다.
    );
    await tester.pumpWidget(
      MaterialApp(home: PhotoSelectScreen(imagePickerService: fakeService)),
    );

    // 먼저 갤러리에서 사진을 선택해 둔다.
    await tester.ensureVisible(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();

    expect(find.text('갤러리에서 선택한 사진'), findsOneWidget);

    // 카메라 촬영을 시도했지만 취소한 경우, 기존 사진이 유지되어야 한다.
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();

    expect(find.text('사진이 선택되었습니다.'), findsOneWidget);
    expect(find.text('갤러리에서 선택한 사진'), findsOneWidget);
  });

  testWidgets('갤러리 선택이 실패하면 안내 SnackBar가 표시된다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoSelectScreen(
          imagePickerService: const _FakeImagePickerService(
            throwOnGallery: true,
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pump();

    expect(find.text('사진을 불러오지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
  });

  testWidgets('카메라 촬영이 실패하면 안내 SnackBar가 표시된다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoSelectScreen(
          imagePickerService: const _FakeImagePickerService(
            throwOnCamera: true,
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pump();

    expect(find.text('카메라를 실행하지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
  });

  testWidgets('이미지 선택 중에는 카메라/갤러리 버튼이 비활성화되어 중복 입력이 차단된다', (
    WidgetTester tester,
  ) async {
    final fakeService = _DelayedFakeImagePickerService(_fakeImageBytes);
    await tester.pumpWidget(
      MaterialApp(home: PhotoSelectScreen(imagePickerService: fakeService)),
    );

    // 첫 번째 탭으로 선택이 시작되지만 아직 완료되지 않은 상태를 만든다.
    await tester.ensureVisible(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pump();

    // 선택창이 열려 있는 동안 두 버튼을 다시 눌러도 반응하지 않아야 한다.
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pump();

    expect(fakeService.galleryCallCount, 1);
    expect(fakeService.cameraCallCount, 0);

    // 선택을 완료시키면 정상적으로 사진이 반영된다.
    fakeService.release();
    await tester.pumpAndSettle();

    expect(find.text('사진이 선택되었습니다.'), findsOneWidget);
  });

  testWidgets('사진을 선택하고 스타일 선택하기를 누르면 스타일 선택 화면으로 이동한다', (
    WidgetTester tester,
  ) async {
    await _pumpPhotoSelectScreenWithFakeGalleryImage(tester);

    await tester.ensureVisible(find.text('스타일 선택하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('스타일 선택하기'));
    await tester.pumpAndSettle();

    expect(find.text('인테리어 스타일'), findsOneWidget);
    expect(find.text('원하는 스타일을 선택해주세요'), findsOneWidget);
    expect(find.text('모던'), findsOneWidget);

    // 목록을 끝까지 스크롤하여 마지막 스타일 카드도 렌더링되는지 확인한다.
    await tester.scrollUntilVisible(find.text('따뜻한 우드'), 200);
    expect(find.text('따뜻한 우드'), findsOneWidget);
  });

  testWidgets('스타일을 선택하고 AI로 공간 만들기를 누르면 생성 화면을 거쳐 결과 화면으로 이동하고 '
      '선택한 스타일과 사진이 표시된다', (WidgetTester tester) async {
    await _pumpToResultScreen(tester);

    expect(find.text('생성 결과'), findsOneWidget);
    expect(find.text('새로운 공간이 완성되었어요'), findsOneWidget);
    // 선택한 스타일 정보 카드에 '모던'이 표시되는지 확인한다.
    expect(find.text('모던'), findsOneWidget);
    // 원본 카드에는 실제 선택한 사진이, AI 결과 카드에는 실제 AiGenerationService가
    // 반환한 Mock 이미지가 표시되어 두 Placeholder 문구 모두 사라진다.
    expect(find.text('원본 사진'), findsNothing);
    expect(find.text('생성된 이미지'), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('카메라로 촬영한 사진이 ResultScreen 원본 카드까지 전달된다', (
    WidgetTester tester,
  ) async {
    await _pumpPhotoSelectScreenWithFakeCameraImage(tester);
    await _proceedToResultScreen(tester);

    expect(find.text('생성 결과'), findsOneWidget);
    // 원본 카드에 실제 촬영한 사진이, AI 결과 카드에는 Mock 이미지가 표시된다.
    expect(find.text('원본 사진'), findsNothing);
    expect(find.text('생성된 이미지'), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('결과 화면의 무료 예상견적 버튼으로 견적 화면에 진입한다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
          generatedImageBytes: _fakeImageBytes,
        ),
      ),
    );

    await tester.ensureVisible(find.text('무료 예상견적 받기'));
    await tester.tap(find.text('무료 예상견적 받기'));
    await tester.pumpAndSettle();

    expect(find.text('무료 예상견적'), findsOneWidget);
    expect(find.text('공간 종류'), findsOneWidget);
  });

  testWidgets('결과 화면에서 저장하기를 누르면 생성 이미지를 저장한다', (WidgetTester tester) async {
    final service = _FakeResultImageService();
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
          generatedImageBytes: _fakeImageBytes,
          resultImageService: service,
        ),
      ),
    );

    await tester.ensureVisible(find.text('저장하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하기'));
    await tester.pump();

    expect(service.saveCallCount, 1);
    expect(service.lastSavedBytes, equals(_fakeImageBytes));
    expect(find.text('결과 이미지를 저장했습니다.'), findsOneWidget);
  });

  testWidgets('결과 화면에서 공유하기를 누르면 생성 이미지를 공유한다', (WidgetTester tester) async {
    final service = _FakeResultImageService();
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
          generatedImageBytes: _fakeImageBytes,
          resultImageService: service,
        ),
      ),
    );

    await tester.ensureVisible(find.text('공유하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('공유하기'));
    await tester.pump();

    expect(service.shareCallCount, 1);
    expect(service.lastSharedBytes, equals(_fakeImageBytes));
  });

  testWidgets('결과 화면에서 다른 스타일로 다시 만들기를 누르면 스타일 선택 화면으로 돌아간다', (
    WidgetTester tester,
  ) async {
    await _pumpToResultScreen(tester);

    await tester.ensureVisible(find.text('다른 스타일로 다시 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다른 스타일로 다시 만들기'));
    await tester.pumpAndSettle();

    expect(find.text('인테리어 스타일'), findsOneWidget);
    expect(find.text('원하는 스타일을 선택해주세요'), findsOneWidget);
    // 결과 화면과 생성 화면은 스택에서 정리되어 더 이상 존재하지 않는다.
    expect(find.text('생성 결과'), findsNothing);
  });

  testWidgets('선택한 이미지가 ResultScreen 원본 카드에 표시된다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as MemoryImage;
    expect(provider.bytes, equals(_fakeImageBytes));
  });

  testWidgets(
    'GenerateScreen은 AiGenerationService.generate를 호출하고, 성공하면 결과 화면으로 이동한다',
    (WidgetTester tester) async {
      final fakeService = _FakeAiGenerationService(
        const AiGenerationResponse(
          success: true,
          elapsedTime: Duration(seconds: 3),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GenerateScreen(
            selectedStyle: '모던',
            selectedImageBytes: _fakeImageBytes,
            aiGenerationService: fakeService,
          ),
        ),
      );

      // initState에서 시작한 비동기 생성 요청이 처리될 시간을 준다.
      await tester.pump();
      await tester.pump();
      // pushReplacement 전환 애니메이션.
      await tester.pump(const Duration(milliseconds: 300));

      expect(fakeService.callCount, 1);
      expect(fakeService.lastRequest?.selectedStyle, '모던');
      expect(fakeService.lastRequest?.imageBytes, equals(_fakeImageBytes));
      expect(find.text('생성 결과'), findsOneWidget);
    },
  );

  testWidgets('GenerateScreen은 실패 시 재시도 UI를 표시하고 다시 생성할 수 있다', (
    WidgetTester tester,
  ) async {
    final fakeService = _FakeAiGenerationService(
      const AiGenerationResponse(
        success: false,
        errorMessage: '가짜 오류',
        elapsedTime: Duration(seconds: 3),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GenerateScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
          aiGenerationService: fakeService,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(fakeService.callCount, 1);
    expect(find.text('이미지를 생성하지 못했습니다'), findsOneWidget);
    expect(find.text('가짜 오류'), findsOneWidget);
    expect(find.text('다시 시도하기'), findsOneWidget);
    // 실패했으므로 GenerateScreen에 그대로 머무른다.
    expect(find.text('AI 생성'), findsOneWidget);
    expect(find.text('생성 결과'), findsNothing);

    await tester.tap(find.text('다시 시도하기'));
    await tester.pump();
    await tester.pump();
    expect(fakeService.callCount, 2);
  });

  testWidgets('generatedImageBytes가 없으면 AI 결과 카드에 기존 Placeholder가 표시된다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
          // generatedImageBytes를 생략하면 null이다.
        ),
      ),
    );

    expect(find.text('생성된 이미지'), findsOneWidget);
    // 원본 카드만 실제 이미지이므로 Image 위젯은 하나만 존재해야 한다.
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('generatedImageBytes가 있으면 AI 결과 카드에 실제 이미지가 표시된다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
          generatedImageBytes: _fakeImageBytes,
        ),
      ),
    );

    expect(find.text('생성된 이미지'), findsNothing);
    // 원본 카드와 AI 결과 카드 모두 실제 이미지를 표시한다.
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('GenerateScreen은 시간이 지남에 따라 안내 문구를 순차적으로 바꾼다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GenerateScreen(
          selectedStyle: '모던',
          selectedImageBytes: _fakeImageBytes,
          aiGenerationService: const _NeverCompletingAiGenerationService(),
        ),
      ),
    );

    // 0~1초: 첫 번째 문구
    expect(find.text('사진을 분석하고 있습니다...'), findsOneWidget);

    // 1~2초: 두 번째 문구로 전환(AnimatedSwitcher 페이드 시간까지 진행)
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('인테리어 스타일을 적용하고 있습니다...'), findsOneWidget);

    // 2~3초: 세 번째 문구로 전환
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('새로운 공간을 생성하고 있습니다...'), findsOneWidget);
  });
}
