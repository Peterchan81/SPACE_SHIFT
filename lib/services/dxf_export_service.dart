import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:share_plus/share_plus.dart';

/// GPT CAD 핵심 이식 — 생성된 DXF 텍스트를 기기에 저장하거나 다른 앱으로
/// 공유한다. 기존 [ResultImageService](인테리어 결과 이미지 저장/공유)와
/// 정확히 같은 패턴(file_saver + share_plus)을 텍스트 파일에 맞게
/// 그대로 재사용한다 — 새 저장/공유 메커니즘을 만들지 않는다.
class DxfExportService {
  const DxfExportService();

  static const String _fileName = 'space_shift_floor_plan';

  Future<void> save(String dxfContent) async {
    await FileSaver.instance.saveFile(
      name: _fileName,
      bytes: utf8.encode(dxfContent),
      fileExtension: 'dxf',
      mimeType: MimeType.other,
    );
  }

  Future<void> share(String dxfContent) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(utf8.encode(dxfContent), mimeType: 'application/dxf')],
        fileNameOverrides: const ['space_shift_floor_plan.dxf'],
        title: 'SPACE SHIFT 평면도 DXF',
      ),
    );
  }
}
