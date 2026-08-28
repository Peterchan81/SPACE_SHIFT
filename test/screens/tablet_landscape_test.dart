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
import 'package:ason_space/screens/photo_preview_screen.dart';
import 'package:ason_space/screens/photo_select_screen.dart';
import 'package:ason_space/screens/result_screen.dart';
import 'package:ason_space/screens/revise_result_screen.dart';
import 'package:ason_space/screens/signup_screen.dart';
import 'package:ason_space/screens/site_meeting_request_screen.dart';
import 'package:ason_space/screens/workspace_screen.dart';
import 'package:ason_space/services/ai_generation_service.dart';

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
      PhotoPreviewScreen(selectedImageBytes: imageBytes),
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
}
