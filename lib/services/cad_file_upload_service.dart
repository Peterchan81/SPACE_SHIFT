import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// SS CAD TEST — CAD Editor WO §4(DXF IMPORT). 선택한 CAD 파일의 텍스트
/// 내용만 담는다 — 파싱은 [dxf_import_service.dart]가 한다(이 서비스는
/// [FloorPlanUploadService]와 정확히 같은 이유로 순수 파일 선택
/// 책임만 진다: 위젯 테스트가 실제 플랫폼 선택창 없이 가짜 파일을
/// 주입할 수 있도록).
class CadFile {
  const CadFile({required this.fileName, required this.content});

  final String fileName;
  final String content;
}

class CadFileUploadService {
  const CadFileUploadService();

  static const List<String> allowedExtensions = ['dxf'];

  /// CAD 파일 한 개를 선택해 텍스트로 읽어 반환한다. 사용자가 선택을
  /// 취소하면 null을 반환한다(예외를 던지지 않음 — 취소는 정상 흐름).
  Future<CadFile?> pickCadFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    return CadFile(fileName: picked.name, content: utf8.decode(bytes));
  }
}
