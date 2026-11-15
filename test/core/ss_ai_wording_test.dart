// #1027-23 남은 문제 3 — AI 인식이 연결되지 않았으면 확인·보정 단계 부제·팁에 "AI"라고 하지 않는다.
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/core/ss_stage_guide.dart';
import 'package:ason_space/screens/ss_tips_screen.dart';
import 'package:ason_space/services/floor_plan_analysis_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('연결 기준은 평면도 분석 서비스의 실제 값과 같다', () {
    expect(SsStageGuide.aiRecognitionConnected, const FloorPlanAnalysisService().aiRecognitionConnected);
  });

  test('AI 미연결이면 평면도 확인·보정 부제에 "AI"가 없고, 연결되면 지금 문구 그대로다', () {
    final off = SsStageGuide.sentenceFor(SsStage.floorPlanReview, aiRecognitionConnected: false);
    expect(off, isNot(contains('AI')));
    expect(off, '인식한 공간을 확인하고, 틀린 곳을 고친 뒤 CAD 변환을 진행하세요.');
    expect(
      SsStageGuide.sentenceFor(SsStage.floorPlanReview, aiRecognitionConnected: true),
      'AI가 인식한 공간을 확인하고, 틀린 곳을 고친 뒤 CAD 변환을 진행하세요.',
    );
    expect(SsStage.floorPlanReview.whatIsThisFor(aiRecognitionConnected: false), '인식한 공간을 확인합니다');
    expect(SsStage.floorPlanReview.whatIsThisFor(aiRecognitionConnected: true), 'AI가 인식한 공간을 확인합니다');
  });

  testWidgets('지금 앱(AI 미연결)의 확인·보정 머리말에는 "AI"가 없다', (tester) async {
    expect(SsStageGuide.aiRecognitionConnected, isFalse);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SsStageHeader(stage: SsStage.floorPlanReview))));
    final text = tester.widget<Text>(find.byKey(const Key('ssStageWhat'))).data!;
    expect(text, isNot(contains('AI')));
  });

  testWidgets('팁 화면의 인식 결과 팁도 같은 기준을 따른다', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SsTipsScreen(aiRecognitionConnected: false)));
    await tester.pumpAndSettle();
    final off = tester.widget<Text>(find.byKey(const Key('ssTipBody_2'))).data!;
    expect(off, isNot(contains('AI')));
    expect(off, startsWith('인식한 벽·문·창'));

    await tester.pumpWidget(const MaterialApp(home: SsTipsScreen(aiRecognitionConnected: true)));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ssTipBody_2'))).data, startsWith('AI가 인식한 벽·문·창'));
  });
}
