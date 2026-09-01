// SPACE SHIFT MASTER UI 1~9번 화면 이동 흐름과 사진 선택(갤러리/카메라) 기능에
// 대한 위젯 테스트.
//
// image_picker는 실제 플랫폼 선택창을 위젯 테스트에서 직접 열 수 없으므로,
// ImagePickerService를 상속한 가짜 구현으로 이미지 데이터(또는 취소/예외)를
// 주입해 테스트한다.
//
// 1. 로그인 화면(1번) -> 사진 등록 화면(2번) 이동을 확인한다.
// 2. 사진이 없을 때 "다음" 버튼이 비활성화되는지 확인한다.
// 3. 가짜 갤러리/카메라 이미지를 선택하면 미리보기와 출처 안내가 표시되고,
//    "다음" 버튼이 활성화되는지 확인한다.
// 4. 사진 등록(2, 선택 즉시 화면 내 미리보기 포함) -> 공간 작업실(4) ->
//    AI 생성(5) -> 결과 확인(6)으로 이어지는 흐름과, 선택한 사진이 결과
//    화면까지 전달되는지 확인한다. 별도의 사진 미리보기(3번) 화면은
//    PhotoSelectScreen과 기능이 중복되어 활성 흐름에 없다.
// 5. 결과 화면(6)의 저장하기/공유하기 SnackBar 동작을 확인한다.
// 6. 카메라 촬영 취소 시 기존 사진이 유지되고, 실패 시 SnackBar가
//    표시되는지 확인한다.
// 7. 이미지 선택 중에는 카메라/갤러리 버튼이 모두 비활성화되어 중복
//    입력이 차단되는지 확인한다.
// 8. GenerateScreen이 AiGenerationService.generate()를 호출하고, 성공/실패
//    응답에 따라 결과 화면 이동 또는 SnackBar 표시로 이어지는지 확인한다.
// 9. 결과 화면(6)의 "수정 재요청"은 수정된 결과 확인(8번)으로, "완료"는
//    최종 확인(9번)으로 이어지는지 확인한다.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/ai_generation_request.dart';
import 'package:ason_space/models/ai_generation_response.dart';
import 'package:ason_space/screens/final_confirm_screen.dart';
import 'package:ason_space/screens/floor_plan_workspace_screen.dart';
import 'package:ason_space/screens/generate_screen.dart';
import 'package:ason_space/screens/login_screen.dart';
import 'package:ason_space/screens/photo_select_screen.dart';
import 'package:ason_space/screens/result_screen.dart';
import 'package:ason_space/screens/revise_result_screen.dart';
import 'package:ason_space/services/ai_generation_service.dart';
import 'package:ason_space/services/image_picker_service.dart';
import 'package:ason_space/services/result_image_service.dart';
import 'package:ason_space/services/usage_policy_service.dart';
import 'package:ason_space/widgets/gradient_cta_button.dart';
import 'package:ason_space/widgets/region_selector.dart';

/// 테스트에서 사용하는 1x1 픽셀 PNG 이미지 바이트.
/// Image.memory가 실제로 디코딩 가능한 유효한 이미지 데이터가 필요하다.
final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// 실제 플랫폼 선택창 대신 미리 정해진 결과를 즉시 반환하는 가짜 서비스.
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

/// 실제 앱과 동일하게 'photo_select'라는 이름의 라우트로 [PhotoSelectScreen]을
/// 최초 화면으로 그린다. 이렇게 해야 ResultScreen 이후 화면들의
/// popUntil(ModalRoute.withName('photo_select')) 동작을 검증할 수 있다.
Future<void> _pumpFromPhotoSelect(
  WidgetTester tester, {
  ImagePickerService imagePickerService = const ImagePickerService(),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      initialRoute: 'photo_select',
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (context) =>
            PhotoSelectScreen(imagePickerService: imagePickerService),
        settings: settings,
      ),
    ),
  );
}

/// 사진 등록 화면(2번)에서 갤러리 사진을 고른 뒤 화면 내 미리보기가
/// 표시된 상태로 "다음"을 누를 수 있게 만든다.
Future<void> _pickGalleryAndGoToPreview(WidgetTester tester) async {
  await tester.ensureVisible(find.text('사진 선택'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('사진 선택'));
  await tester.pumpAndSettle();
}

/// 사진 등록(2, 선택 즉시 화면 내 미리보기) -> 공간 작업실(4) -> AI
/// 생성(5) -> 결과 확인(6)까지 진행한다.
Future<void> _proceedToResultScreen(WidgetTester tester) async {
  await _pickGalleryAndGoToPreview(tester);

  await tester.ensureVisible(find.byType(GradientCtaButton).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('다음'));
  await tester.pumpAndSettle();

  expect(find.text('공간 작업실'), findsOneWidget);

  // 사진 위에서 손가락(마우스)으로 드래그해 부분 영역을 하나 선택한다.
  await tester.drag(find.byType(RegionSelector), const Offset(160, 140));
  await tester.pump();

  // 선택한 부분을 어떻게 바꾸고 싶은지 작업 지시를 입력한다.
  await tester.enterText(
    find.byType(TextField).first,
    '좌측 벽 부분을 밝은 아이보리 컬러로 변경해주세요.',
  );
  await tester.pump();

  // 공간의 변화 만들기 버튼을 누르면 AI 생성(대기) 화면으로 이동
  await tester.ensureVisible(find.text('공간의 변화 만들기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('공간의 변화 만들기'));
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

void main() {
  // 여러 테스트가 GenerateScreen을 거치므로, 하루 무료 횟수 카운터(전역
  // 싱글턴)가 테스트 간에 누적되어 WorkspaceScreen의 한도 초과 안내가
  // 뜨는 일이 없도록 매 테스트 전에 초기화한다.
  setUp(() {
    UsagePolicyService.instance.resetForTesting();
  });

  testWidgets('로그인 화면에서 로그인을 누르면 신규 MASTER 메인 작업 화면으로 이동한다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('SPACE SHIFT'), findsOneWidget);
    expect(find.text('로그인'), findsWidgets);

    await tester.tap(find.widgetWithText(GradientCtaButton, '로그인'));
    await tester.pumpAndSettle();

    expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
    expect(find.text('평면도 업로드 작업실'), findsOneWidget);
    expect(find.text('시작 방식 선택'), findsOneWidget);
    // 기존 "공간 사진 등록" 화면이 로그인 직후 자동으로 나타나지 않는다.
    expect(find.text('공간 사진 등록'), findsNothing);
  });

  testWidgets('사진이 없을 때 다음 버튼이 비활성화된다', (WidgetTester tester) async {
    await _pumpFromPhotoSelect(tester);

    final button = tester.widget<GradientCtaButton>(
      find.byType(GradientCtaButton),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('가짜 갤러리 이미지를 선택하면 미리보기와 출처가 표시되고 다음 버튼이 활성화된다', (
    WidgetTester tester,
  ) async {
    await _pumpFromPhotoSelect(
      tester,
      imagePickerService: _FakeImagePickerService(
        galleryResult: _fakeImageBytes,
      ),
    );

    await tester.ensureVisible(find.text('사진 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 선택'));
    await tester.pumpAndSettle();

    expect(find.text('선택된 사진이 없습니다'), findsNothing);
    expect(find.text('사진이 선택되었습니다.'), findsOneWidget);
    expect(find.text('갤러리에서 선택한 사진'), findsOneWidget);

    final button = tester.widget<GradientCtaButton>(
      find.byType(GradientCtaButton),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('가짜 카메라 이미지를 선택하면 미리보기와 출처가 표시된다', (WidgetTester tester) async {
    await _pumpFromPhotoSelect(
      tester,
      imagePickerService: _FakeImagePickerService(
        cameraResult: _fakeImageBytes,
      ),
    );

    await tester.ensureVisible(find.text('카메라 촬영'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라 촬영'));
    await tester.pumpAndSettle();

    expect(find.text('선택된 사진이 없습니다'), findsNothing);
    expect(find.text('사진이 선택되었습니다.'), findsOneWidget);
    expect(find.text('카메라로 촬영한 사진'), findsOneWidget);
  });

  testWidgets('카메라 촬영을 취소하면 기존에 선택되어 있던 사진이 그대로 유지된다', (
    WidgetTester tester,
  ) async {
    final fakeService = _FakeImagePickerService(
      galleryResult: _fakeImageBytes,
      // cameraResult를 지정하지 않으면 촬영 취소(null 반환)를 의미한다.
    );
    await _pumpFromPhotoSelect(tester, imagePickerService: fakeService);

    await tester.ensureVisible(find.text('사진 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 선택'));
    await tester.pumpAndSettle();

    expect(find.text('갤러리에서 선택한 사진'), findsOneWidget);

    await tester.tap(find.text('카메라 촬영'));
    await tester.pumpAndSettle();

    expect(find.text('사진이 선택되었습니다.'), findsOneWidget);
    expect(find.text('갤러리에서 선택한 사진'), findsOneWidget);
  });

  testWidgets('갤러리 선택이 실패하면 안내 SnackBar가 표시된다', (WidgetTester tester) async {
    await _pumpFromPhotoSelect(
      tester,
      imagePickerService: const _FakeImagePickerService(throwOnGallery: true),
    );

    await tester.ensureVisible(find.text('사진 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 선택'));
    await tester.pump();

    expect(find.text('사진을 불러오지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
  });

  testWidgets('카메라 촬영이 실패하면 안내 SnackBar가 표시된다', (WidgetTester tester) async {
    await _pumpFromPhotoSelect(
      tester,
      imagePickerService: const _FakeImagePickerService(throwOnCamera: true),
    );

    await tester.ensureVisible(find.text('카메라 촬영'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라 촬영'));
    await tester.pump();

    expect(find.text('카메라를 실행하지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
  });

  testWidgets('이미지 선택 중에는 카메라/갤러리 버튼이 비활성화되어 중복 입력이 차단된다', (
    WidgetTester tester,
  ) async {
    final fakeService = _DelayedFakeImagePickerService(_fakeImageBytes);
    await _pumpFromPhotoSelect(tester, imagePickerService: fakeService);

    await tester.ensureVisible(find.text('사진 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 선택'));
    await tester.pump();

    // 선택창이 열려 있는 동안 두 버튼을 다시 눌러도 반응하지 않아야 한다.
    await tester.tap(find.text('사진 선택'));
    await tester.tap(find.text('카메라 촬영'));
    await tester.pump();

    expect(fakeService.galleryCallCount, 1);
    expect(fakeService.cameraCallCount, 0);

    fakeService.release();
    await tester.pumpAndSettle();

    expect(find.text('사진이 선택되었습니다.'), findsOneWidget);
  });

  testWidgets('사진을 등록하면 미리보기 화면을 거쳐 공간 작업실로 이동하고 결과 화면까지 이미지가 전달된다', (
    WidgetTester tester,
  ) async {
    await _pumpFromPhotoSelect(
      tester,
      imagePickerService: _FakeImagePickerService(
        galleryResult: _fakeImageBytes,
      ),
    );

    await _proceedToResultScreen(tester);

    expect(find.text('생성 결과'), findsOneWidget);
    expect(find.text('공간 변화가 완성되었습니다'), findsOneWidget);
    expect(find.text('원본 사진'), findsNothing);
    expect(find.text('생성된 이미지'), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('결과 화면에서 저장하기를 누르면 생성 이미지를 저장한다', (WidgetTester tester) async {
    final service = _FakeResultImageService();
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
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

  testWidgets('결과 화면의 더보기 메뉴에서 추가 옵션 시트를 열 수 있다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          selectedImageBytes: _fakeImageBytes,
          generatedImageBytes: _fakeImageBytes,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('추가 옵션'), findsOneWidget);
    expect(find.text('고화질 다운로드'), findsOneWidget);
    expect(find.text('프로젝트 정보'), findsOneWidget);
  });

  testWidgets('결과 화면에서 수정 재요청을 누르면 공간 작업실로 돌아가고, 재생성 후 수정된 결과 확인 화면으로 이동한다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          selectedImageBytes: _fakeImageBytes,
          generatedImageBytes: _fakeImageBytes,
        ),
      ),
    );

    await tester.ensureVisible(find.text('수정 재요청'));
    await tester.tap(find.text('수정 재요청'));
    await tester.pumpAndSettle();

    expect(find.text('공간 작업실'), findsOneWidget);

    await tester.drag(find.byType(RegionSelector), const Offset(160, 140));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '조명을 밝게 해주세요.');
    await tester.pump();

    await tester.ensureVisible(find.text('공간의 변화 만들기'));
    await tester.tap(find.text('공간의 변화 만들기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('수정 요청 처리 중'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.byType(ReviseResultScreen), findsOneWidget);
    expect(find.text('수정된 공간을 확인해주세요'), findsOneWidget);
    expect(find.text('무료 예상견적 받기'), findsOneWidget);
    expect(find.text('현장 미팅 문의하기'), findsOneWidget);
  });

  testWidgets('결과 화면에서 완료를 누르면 최종 확인 화면으로 이동하고, 이대로 확정하면 사진 등록 화면으로 돌아간다', (
    WidgetTester tester,
  ) async {
    await _pumpFromPhotoSelect(
      tester,
      imagePickerService: _FakeImagePickerService(
        galleryResult: _fakeImageBytes,
      ),
    );
    await _proceedToResultScreen(tester);

    await tester.ensureVisible(find.text('완료'));
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(find.byType(FinalConfirmScreen), findsOneWidget);
    expect(find.text('변경 요약'), findsOneWidget);

    await tester.ensureVisible(find.text('이대로 확정하기'));
    await tester.tap(find.text('이대로 확정하기'));
    await tester.pumpAndSettle();

    expect(find.text('공간 변화가 확정되었습니다'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('공간 사진 등록'), findsOneWidget);
  });

  testWidgets('선택한 이미지가 ResultScreen 원본 카드에 표시된다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ResultScreen(selectedImageBytes: _fakeImageBytes)),
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
            selectedStyle: '',
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
          selectedStyle: '',
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
          selectedStyle: '',
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
