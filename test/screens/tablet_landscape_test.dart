import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/ai_generation_request.dart';
import 'package:ason_space/models/ai_generation_response.dart';
import 'package:ason_space/screens/estimate_request_screen.dart';
import 'package:ason_space/screens/final_confirm_screen.dart';
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
      ResultScreen(selectedImageBytes: imageBytes, generatedImageBytes: imageBytes),
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
    ];

    for (final screen in screens) {
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Galaxy Tab 가로 화면의 공간 작업실은 사진/작업 부위/지시 입력/CTA가 스크롤 없이 동시에 보인다',
    (tester) async {
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
    },
  );

  testWidgets(
    'Galaxy Tab 가로 화면의 회원가입은 프로필 사진/입력 폼/가입 버튼이 스크롤 없이 한 화면에 보인다',
    (tester) async {
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
    },
  );
}
