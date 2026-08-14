import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ason_space/models/site_meeting_request.dart';
import 'package:ason_space/screens/site_meeting_request_screen.dart';
import 'package:ason_space/screens/result_screen.dart';

void main() {
  testWidgets('결과 화면에서 현장미팅 문의 화면으로 진입한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          selectedStyle: '모던',
          selectedImageBytes: Uint8List.fromList(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
              '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('현장미팅 문의하기'));
    await tester.tap(find.text('현장미팅 문의하기'));
    await tester.pumpAndSettle();

    expect(find.text('현장미팅 문의'), findsOneWidget);
    expect(find.text('이름'), findsOneWidget);
  });

  testWidgets('필수 정보와 개인정보 동의를 제출하면 문의 완료 상태를 표시한다', (tester) async {
    SiteMeetingRequest? submittedRequest;
    await tester.pumpWidget(
      MaterialApp(
        home: SiteMeetingRequestScreen(
          onSubmitted: (request) => submittedRequest = request,
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('meeting_name')), '홍길동');
    await tester.enterText(
      find.byKey(const ValueKey('meeting_contact')),
      '010-1234-5678',
    );
    await tester.enterText(
      find.byKey(const ValueKey('meeting_area')),
      '서울시 강남구',
    );
    await tester.enterText(
      find.byKey(const ValueKey('meeting_datetime')),
      '8월 20일 오후 2시',
    );
    await tester.enterText(
      find.byKey(const ValueKey('meeting_notes')),
      '주말 방문을 희망합니다.',
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('현장미팅 문의하기'));
    await tester.tap(find.text('현장미팅 문의하기'));
    await tester.pump();

    expect(find.text('현장미팅 문의가 접수되었습니다'), findsOneWidget);
    expect(submittedRequest?.name, '홍길동');
    expect(submittedRequest?.contact, '010-1234-5678');
    expect(submittedRequest?.visitArea, '서울시 강남구');
    expect(submittedRequest?.preferredDateTime, '8월 20일 오후 2시');
    expect(submittedRequest?.notes, '주말 방문을 희망합니다.');
    expect(submittedRequest?.privacyAgreed, isTrue);
  });

  testWidgets('개인정보 동의 없이 제출하면 문의를 접수하지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SiteMeetingRequestScreen()),
    );

    await tester.enterText(find.byKey(const ValueKey('meeting_name')), '홍길동');
    await tester.enterText(
      find.byKey(const ValueKey('meeting_contact')),
      '010-1234-5678',
    );
    await tester.enterText(
      find.byKey(const ValueKey('meeting_area')),
      '서울시 강남구',
    );
    await tester.enterText(
      find.byKey(const ValueKey('meeting_datetime')),
      '8월 20일 오후 2시',
    );
    await tester.ensureVisible(find.text('현장미팅 문의하기'));
    await tester.tap(find.text('현장미팅 문의하기'));
    await tester.pump();

    expect(find.text('개인정보 수집 및 이용에 동의해주세요.'), findsOneWidget);
    expect(find.text('현장미팅 문의가 접수되었습니다'), findsNothing);
  });
}
