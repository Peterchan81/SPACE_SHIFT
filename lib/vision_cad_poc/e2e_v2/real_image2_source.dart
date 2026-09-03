import 'dart:io';
import 'dart:typed_data';

/// SPACE SHIFT — Image 2 GPT Detailed CAD Geometry POC.
///
/// 실제 "이미지 2" 원본 파일 경로. 이 세션에서 파일시스템을 직접 조사해
/// 찾은 실제 파일이다(채팅 첨부 이미지를 추출한 것이 아니라, 사용자가
/// 이 PC에 실제로 저장해 둔 동일한 도면 파일을 발견한 것) — 합성
/// fixture가 아니다.
///
/// 이 경로가 사라지면(파일 이동/삭제) [loadRealImage2Bytes]는 null을
/// 반환하고, 화면은 "SOURCE BLOCKED"로 정직하게 표시해야 한다 — 가짜
/// 좌표나 합성 이미지로 조용히 대체하지 않는다.
const String kRealImage2Path = r'C:\Users\user\Desktop\스크린샷\평면도1.PNG';

Uint8List? loadRealImage2Bytes() {
  final file = File(kRealImage2Path);
  if (!file.existsSync()) return null;
  return file.readAsBytesSync();
}
