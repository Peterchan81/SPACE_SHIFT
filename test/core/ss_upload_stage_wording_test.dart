// SS-수정003 4차 — 평면도 업로드 단계 안내도 확인·보정 단계와 같은 기준(aiRecognitionConnected)으로 "AI"를 쓴다.
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/core/ss_stage_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI 미연결이면 업로드 단계 안내에 "AI"가 없다', () {
    final off = SsStageGuide.sentenceFor(SsStage.floorPlanUpload, aiRecognitionConnected: false);
    expect(off, '평면도 이미지나 PDF를 업로드하면 공간을 인식합니다.');
    expect(off, isNot(contains('AI')));
    expect(SsStage.floorPlanUpload.whatIsThisFor(aiRecognitionConnected: false), isNot(contains('AI')));
  });

  test('AI가 연결되면 지금 문구 그대로다', () {
    expect(SsStageGuide.sentenceFor(SsStage.floorPlanUpload, aiRecognitionConnected: true), '평면도 이미지나 PDF를 업로드하면 AI가 공간을 인식합니다.');
    expect(SsStage.floorPlanUpload.whatIsThisFor(aiRecognitionConnected: true), SsStage.floorPlanUpload.whatIsThis);
  });

  testWidgets('지금 앱(AI 미연결)의 업로드 머리말에는 "AI"가 없다', (tester) async {
    expect(SsStageGuide.aiRecognitionConnected, isFalse);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SsStageHeader(stage: SsStage.floorPlanUpload))));
    final text = tester.widget<Text>(find.byKey(const Key('ssStageWhat'))).data!;
    expect(text, isNot(contains('AI')));
    expect(text, SsStageGuide.sentenceFor(SsStage.floorPlanUpload));
  });
}
