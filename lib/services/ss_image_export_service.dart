/// SS007 — MASTER UI 4-2-2 "파일 내보내기"(JPG/PNG). 기존 ResultImageService/DxfExportService와
/// 같은 file_saver 패턴을 쓰되, 형식(PNG/JPG)·품질·저장 위치를 사용자가 고를 수 있게 한다.
library;

import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:image/image.dart' as img;

import '../core/ss_editing.dart';

class SsImageExportService {
  const SsImageExportService();

  /// [pngBytes]는 항상 PNG로 들고 있는 최종 렌더 결과 — [job]의 format이 JPG이면 그때 변환해 인코딩한다.
  /// [jpgQuality]는 1~100. [chooseLocation]이 true이면 저장 위치를 직접 고르는 대화상자를 연다(취소하면
  /// null을 돌려준다 — 실패가 아니다).
  Future<String?> save(Uint8List pngBytes, SsExportJob job, {int jpgQuality = 90, bool chooseLocation = false}) async {
    final bytes = job.format == SsExportFormat.jpg ? _toJpg(pngBytes, jpgQuality) : pngBytes;
    final mime = job.format == SsExportFormat.jpg ? MimeType.jpeg : MimeType.png;
    if (chooseLocation) {
      return FileSaver.instance.saveAs(name: job.fileName, bytes: bytes, fileExtension: job.format.extension, mimeType: mime);
    }
    return FileSaver.instance.saveFile(name: job.fileName, bytes: bytes, fileExtension: job.format.extension, mimeType: mime);
  }

  Uint8List _toJpg(Uint8List pngBytes, int quality) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return pngBytes;
    return img.encodeJpg(decoded, quality: quality.clamp(1, 100));
  }
}
