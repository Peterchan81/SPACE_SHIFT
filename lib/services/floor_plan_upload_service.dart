import 'package:file_picker/file_picker.dart';

import '../models/floor_plan_file.dart';

/// 시스템 파일 선택창으로 평면도 파일(JPG/PNG/PDF)을 고르는 기능을 감싸는
/// 서비스. 화면 위젯이 file_picker 패키지에 직접 의존하지 않도록 분리해,
/// 위젯 테스트에서는 이 클래스를 상속해 실제 플랫폼 선택창 없이 가짜
/// 파일을 주입할 수 있도록 한다([ImagePickerService]와 동일한 패턴).
class FloorPlanUploadService {
  const FloorPlanUploadService();

  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

  /// 평면도 파일 한 개를 선택해 반환한다. 사용자가 선택을 취소하면 null을
  /// 반환한다(예외를 던지지 않음 — 취소는 정상 흐름).
  ///
  /// PDF는 렌더링 엔진이 없어 미리보기에 쓰지 않으므로 바이트를 읽지
  /// 않는다(불필요한 메모리 사용 방지) — 파일명/아이콘 placeholder만
  /// 보여주는 데는 바이트가 필요 없다.
  Future<FloorPlanFile?> pickFloorPlanFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (picked == null) return null;

    final extension = (picked.extension ?? '').toLowerCase();
    final kind = extension == 'pdf'
        ? FloorPlanFileKind.pdf
        : FloorPlanFileKind.image;

    final bytes = kind == FloorPlanFileKind.image
        ? await picked.readAsBytes()
        : null;
    final sizeBytes = await picked.length();

    return FloorPlanFile(
      fileName: picked.name,
      extension: extension,
      kind: kind,
      sizeBytes: sizeBytes,
      bytes: bytes,
    );
  }
}
