import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:share_plus/share_plus.dart';

/// 생성된 인테리어 결과 이미지를 기기에 저장하거나 다른 앱으로 공유한다.
class ResultImageService {
  const ResultImageService();

  static const String _fileName = 'space_shift_result';

  Future<void> save(Uint8List imageBytes) async {
    await FileSaver.instance.saveFile(
      name: _fileName,
      bytes: imageBytes,
      fileExtension: 'png',
      mimeType: MimeType.png,
    );
  }

  Future<void> share(Uint8List imageBytes) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(imageBytes, mimeType: 'image/png')],
        fileNameOverrides: const ['space_shift_result.png'],
        title: 'SPACE SHIFT 인테리어 결과',
      ),
    );
  }
}
