import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/ai_generation_request.dart';
import 'package:ason_space/models/ai_generation_response.dart';
import 'package:ason_space/screens/estimate_request_screen.dart';
import 'package:ason_space/screens/final_confirm_screen.dart';
import 'package:ason_space/screens/floor_plan_workspace_screen.dart';
import 'package:ason_space/screens/generate_screen.dart';
import 'package:ason_space/screens/login_screen.dart';
import 'package:ason_space/screens/photo_select_screen.dart';
import 'package:ason_space/screens/result_screen.dart';
import 'package:ason_space/screens/revise_result_screen.dart';
import 'package:ason_space/screens/signup_screen.dart';
import 'package:ason_space/screens/site_meeting_request_screen.dart';
import 'package:ason_space/screens/workspace_screen.dart';
import 'package:ason_space/services/ai_generation_service.dart';
import 'package:ason_space/widgets/gradient_cta_button.dart';
import 'package:ason_space/widgets/region_selector.dart';
import 'package:ason_space/widgets/work_area_panel.dart';
import 'package:ason_space/widgets/workspace/selected_item_header.dart';
import 'package:ason_space/widgets/workspace/start_method_panel.dart';
import 'package:ason_space/widgets/workspace/user_workspace_panel.dart';
import 'package:ason_space/widgets/workspace/workspace_canvas.dart';
import 'package:ason_space/widgets/workspace/workspace_task_list.dart';
import 'package:ason_space/widgets/workspace/workspace_view_switcher.dart';

class _PendingAiGenerationService extends AiGenerationService {
  @override
  Future<AiGenerationResponse> generate(AiGenerationRequest request) {
    return Completer<AiGenerationResponse>().future;
  }
}

void main() {
  final imageBytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );

  testWidgets('Galaxy Tab 가로 화면에서 MASTER UI 1~9번 화면에 렌더링 오류가 없다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final screens = <Widget>[
      const LoginScreen(),
      const SignupScreen(),
      const PhotoSelectScreen(),
      WorkspaceScreen(selectedImageBytes: imageBytes),
      GenerateScreen(
        selectedStyle: '',
        selectedImageBytes: imageBytes,
        aiGenerationService: _PendingAiGenerationService(),
      ),
      GenerateScreen(
        selectedStyle: '',
        selectedImageBytes: imageBytes,
        isRevision: true,
        aiGenerationService: _PendingAiGenerationService(),
      ),
      ResultScreen(
        selectedImageBytes: imageBytes,
        generatedImageBytes: imageBytes,
      ),
      ReviseResultScreen(
        selectedImageBytes: imageBytes,
        generatedImageBytes: imageBytes,
      ),
      FinalConfirmScreen(
        selectedStyle: '',
        selectedImageBytes: imageBytes,
        generatedImageBytes: imageBytes,
      ),
      EstimateRequestScreen(),
      SiteMeetingRequestScreen(),
      const FloorPlanWorkspaceScreen(),
    ];

    for (final screen in screens) {
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Galaxy Tab 가로 화면의 공간 작업실은 사진/작업 부위/지시 입력/CTA가 스크롤 없이 동시에 보인다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(selectedImageBytes: imageBytes)),
    );
    await tester.pump();

    expect(find.byType(RegionSelector), findsOneWidget);
    expect(find.byType(WorkAreaPanel), findsOneWidget);
    expect(find.byType(GradientCtaButton), findsOneWidget);

    // CTA가 화면(800px 높이) 안쪽에 그대로 보여야 한다. 스크롤이 필요하면
    // 이 좌표가 800을 넘어가므로, 넘어가지 않는지로 "스크롤 없이 핵심
    // 버튼이 보인다"를 검증한다.
    final ctaBottom = tester.getBottomLeft(find.byType(GradientCtaButton)).dy;
    expect(ctaBottom, lessThanOrEqualTo(800));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Galaxy Tab 가로 화면의 회원가입은 프로필 사진/입력 폼/가입 버튼이 스크롤 없이 한 화면에 보인다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    await tester.pump();

    // 왼쪽 열(프로필 사진 선택)과 오른쪽 열(입력 폼)이 동시에 보인다.
    expect(find.text('프로필 사진 (선택)'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.byType(GradientCtaButton), findsOneWidget);

    final ctaBottom = tester.getBottomLeft(find.byType(GradientCtaButton)).dy;
    expect(ctaBottom, lessThanOrEqualTo(800));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Galaxy Tab 가로 화면의 공간 사진 등록은 안내/미리보기/촬영·선택 버튼이 스크롤 없이 한 화면에 보인다',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: PhotoSelectScreen()));
      await tester.pump();

      // 왼쪽 열(안내 문구)과 오른쪽 열(사진 미리보기+버튼)이 동시에 보인다.
      expect(find.text('변화시킬 공간을 보여주세요'), findsOneWidget);
      expect(find.text('카메라 촬영'), findsOneWidget);
      expect(find.text('사진 선택'), findsOneWidget);
      expect(find.byType(GradientCtaButton), findsOneWidget);

      final ctaBottom = tester.getBottomLeft(find.byType(GradientCtaButton)).dy;
      expect(ctaBottom, lessThanOrEqualTo(800));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Galaxy Tab 가로 화면의 평면도 업로드 작업실(demo)은 좌/중앙/우측 패널이 스크롤 없이 동시에 보이고 선택이 동기화된다',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 이 테스트는 마커/작업 목록/우측 패널의 3-way 동기화를 검증하는
      // MASTER UI 미리보기 목적이므로 demoMode로 데모 6개 항목을 채운다.
      // 실사용(demoMode: false, 기본값) 흐름의 빈 초기 상태 검증은
      // floor_plan_workspace_screen_test.dart에서 다룬다.
      await tester.pumpWidget(
        const MaterialApp(home: FloorPlanWorkspaceScreen(demoMode: true)),
      );
      await tester.pump();

      expect(find.byType(StartMethodPanel), findsOneWidget);
      expect(find.byType(WorkspaceViewSwitcher), findsOneWidget);
      expect(find.byType(WorkspaceCanvas), findsOneWidget);
      expect(find.byType(WorkspaceTaskList), findsOneWidget);
      expect(find.byType(UserWorkspacePanel), findsOneWidget);

      // 기본 선택(1번 항목)이 우측 "작업" 탭의 선택된 항목 헤더에 반영된다.
      expect(
        find.descendant(
          of: find.byType(SelectedItemHeader),
          matching: find.text('거실 벽 (TV 벽체)'),
        ),
        findsOneWidget,
      );

      // 작업 목록에서 3번째 항목("안방 벽")을 선택하면 우측 패널도 함께 바뀐다
      // (marker/작업 목록/작업 탭이 같은 id를 공유하는 양방향 동기화 검증).
      await tester.tap(find.text('안방 벽'));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(SelectedItemHeader),
          matching: find.text('안방 벽'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // 우측 패널의 가구/디스플레이/정보 탭 전환도 렌더링 오류 없이 동작한다.
      for (final label in ['가구', '디스플레이', '정보', '작업']) {
        await tester.tap(find.text(label).last);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
