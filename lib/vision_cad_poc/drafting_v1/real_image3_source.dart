import 'dart:io';
import 'dart:typed_data';

/// SPACE SHIFT — WO088-4 Image 3 원본 경로.
///
/// 기존 [kRealImage2Path](e2e_v2/real_image2_source.dart)와 동일한 관례:
/// 파일이 사라지면 [loadRealImage3Bytes]는 null을 반환하고, 화면은
/// "SOURCE BLOCKED"로 정직하게 표시한다 — 가짜 이미지로 대체하지 않는다.
const String kRealImage3Path = r'C:\ASON\SPACE_SHIFT\test\image3.png';

Uint8List? loadRealImage3Bytes() {
  final file = File(kRealImage3Path);
  if (!file.existsSync()) return null;
  return file.readAsBytesSync();
}
