// SS-수정003 — 공통 머리말은 번호 상자·"다음: …" 개발용 표시 없이 큰 제목 + 한 줄 안내 문장(MASTER 문구 우선).
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/core/ss_stage_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('모든 단계에 안내 문장이 있다', () {
    for (final s in SsStage.values) {
      expect(SsStageGuide.sentenceFor(s).trim(), isNotEmpty, reason: s.name);
    }
    expect(SsStageGuide.sentenceFor(SsStage.projectManagement), '진행 중인 프로젝트를 선택하여 작업을 계속하거나 새로운 프로젝트를 만들어보세요.');
  });

  testWidgets('머리말은 제목과 안내 문장만 보이고, 번호 상자·"다음:" 표시는 없다(모든 단계)', (tester) async {
    for (final stage in SsStage.values) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SsStageHeader(stage: stage))));
      expect(tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data, stage.title, reason: stage.name);
      expect(tester.widget<Text>(find.byKey(const Key('ssStageWhat'))).data, SsStageGuide.sentenceFor(stage), reason: stage.name);
      expect(find.byKey(const Key('ssStageNext')), findsNothing, reason: stage.name);
      expect(find.textContaining('다음:'), findsNothing, reason: stage.name);
      expect(find.text(stage.masterUi), findsNothing, reason: '${stage.name} — 번호 상자 없음');
    }
  });
}
