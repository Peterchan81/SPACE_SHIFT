import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/estimate_request.dart';
import 'package:ason_space/screens/estimate_request_screen.dart';

void main() {
  Future<void> selectDropdown(
    WidgetTester tester,
    int index,
    String value,
  ) async {
    final field = find.byType(DropdownButtonFormField<String>).at(index);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  Future<void> selectColorTone(WidgetTester tester, String value) async {
    final chip = find.widgetWithText(ChoiceChip, value);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  testWidgets('필수 항목을 입력하면 예상견적 요청 완료 상태를 표시한다', (tester) async {
    EstimateRequest? submittedRequest;
    await tester.pumpWidget(
      MaterialApp(
        home: EstimateRequestScreen(
          onSubmitted: (request) => submittedRequest = request,
        ),
      ),
    );

    await selectDropdown(tester, 0, '거실');
    await selectDropdown(tester, 1, '10~20평');
    await selectDropdown(tester, 2, '부분 시공');
    await selectColorTone(tester, '베이지');
    await tester.ensureVisible(find.text('간단한 요청사항 (선택)'));
    await tester.enterText(find.byType(TextFormField).last, '수납공간을 늘리고 싶어요.');
    await tester.ensureVisible(find.text('예상견적 요청하기'));
    await tester.tap(find.text('예상견적 요청하기'));
    await tester.pump();

    expect(find.text('예상견적 요청이 접수되었습니다'), findsOneWidget);
    expect(submittedRequest?.spaceType, '거실');
    expect(submittedRequest?.approximateArea, '10~20평');
    expect(submittedRequest?.constructionScope, '부분 시공');
    expect(submittedRequest?.desiredColorTone, '베이지');
    expect(submittedRequest?.customColorTone, isEmpty);
    expect(submittedRequest?.notes, '수납공간을 늘리고 싶어요.');
  });

  testWidgets('필수 항목이 비어 있으면 요청을 접수하지 않는다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EstimateRequestScreen()));

    await tester.ensureVisible(find.text('예상견적 요청하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('예상견적 요청하기'));
    await tester.pump();

    expect(find.text('항목을 선택해주세요.'), findsNWidgets(3));
    expect(find.text('색상/톤을 선택해주세요.'), findsOneWidget);
    expect(find.text('예상견적 요청이 접수되었습니다'), findsNothing);
  });

  testWidgets('완료 상태의 현장미팅 버튼은 주입된 연결 동작을 실행한다', (tester) async {
    var meetingRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EstimateRequestScreen(
          onSiteMeetingRequested: () => meetingRequested = true,
        ),
      ),
    );

    await selectDropdown(tester, 0, '거실');
    await selectDropdown(tester, 1, '10평 미만');
    await selectDropdown(tester, 2, '아직 모르겠어요');
    await selectColorTone(tester, '화이트');
    await tester.ensureVisible(find.text('예상견적 요청하기'));
    await tester.tap(find.text('예상견적 요청하기'));
    await tester.pump();
    await tester.tap(find.text('현장미팅 문의하기'));

    expect(meetingRequested, isTrue);
  });

  testWidgets('기타 색상/톤을 선택하면 직접 입력값을 요청 모델에 저장한다', (tester) async {
    EstimateRequest? submittedRequest;
    await tester.pumpWidget(
      MaterialApp(
        home: EstimateRequestScreen(
          onSubmitted: (request) => submittedRequest = request,
        ),
      ),
    );

    await selectDropdown(tester, 0, '침실');
    await selectDropdown(tester, 1, '10평 미만');
    await selectDropdown(tester, 2, '부분 시공');
    await selectColorTone(tester, '기타');
    final customField = find.widgetWithText(TextFormField, '원하는 색상/톤 직접 입력');
    await tester.ensureVisible(customField);
    await tester.enterText(customField, '연한 세이지 그린');
    await tester.ensureVisible(find.text('예상견적 요청하기'));
    await tester.tap(find.text('예상견적 요청하기'));
    await tester.pump();

    expect(find.text('예상견적 요청이 접수되었습니다'), findsOneWidget);
    expect(submittedRequest?.desiredColorTone, '기타');
    expect(submittedRequest?.customColorTone, '연한 세이지 그린');
  });
}
