import 'dart:io';
import 'dart:typed_data';

/// SPACE SHIFT — WO088-4 Image 3 원본 경로.
///
/// 기존 [kRealImage2Path](e2e_v2/real_image2_source.dart)와 동일한 관례:
/// 파일이 사라지면 [loadRealImage3Bytes]는 null을 반환하고, 화면은
/// "SOURCE BLOCKED"로 정직하게 표시한다 — 가짜 이미지로 대체하지 않는다.
final String kRealImage3Path = spaceShiftWorkspacePath('test/image3.png');

/// Resolve local POC inputs and outputs from the SPACE SHIFT repository.
String spaceShiftWorkspacePath(String relativePath) {
  final starts = <Directory>[
    Directory.current,
    if (Platform.script.scheme == 'file') File.fromUri(Platform.script).parent,
    File(Platform.resolvedExecutable).parent,
  ];
  for (final start in starts) {
    var directory = start.absolute;
    while (true) {
      final pubspec = File.fromUri(directory.uri.resolve('pubspec.yaml'));
      if (pubspec.existsSync() &&
          RegExp(r'^name:\s*ason_space\s*$', multiLine: true)
              .hasMatch(pubspec.readAsStringSync())) {
        return File.fromUri(directory.uri.resolve(relativePath)).path;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  }
  // Keep the existing missing-file behavior when source files are unavailable.
  return File(relativePath).absolute.path;
}

Uint8List? loadRealImage3Bytes() {
  final file = File(kRealImage3Path);
  if (!file.existsSync()) return null;
  return file.readAsBytesSync();
}
