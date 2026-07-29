import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 갤러리에서 사진을 선택하는 기능을 감싸는 서비스.
///
/// 화면 위젯이 image_picker 패키지에 직접 의존하지 않도록 분리해,
/// 위젯 테스트에서는 이 클래스를 상속해 실제 플랫폼 선택창 없이
/// 가짜 이미지 데이터를 주입할 수 있도록 한다.
class ImagePickerService {
  const ImagePickerService();

  /// 갤러리에서 이미지 한 장을 선택해 바이트 데이터로 반환한다.
  ///
  /// 웹/모바일 모두에서 동일하게 동작하도록 dart:io의 File 대신
  /// [XFile.readAsBytes]로 읽은 [Uint8List]를 반환한다.
  /// 사용자가 선택을 취소하면 null을 반환한다.
  Future<Uint8List?> pickGalleryImage() async {
    final picker = ImagePicker();
    // imageQuality/maxWidth로 원본을 적당히 압축해
    // 추후 AI API 업로드 비용과 메모리 사용을 줄인다.
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  /// 카메라로 사진 한 장을 촬영해 바이트 데이터로 반환한다.
  ///
  /// 갤러리 선택과 동일한 압축 설정(imageQuality/maxWidth)을 사용하며,
  /// 마찬가지로 dart:io의 File 대신 [Uint8List]를 반환해 웹/모바일 모두에서
  /// 동일하게 동작한다. 사용자가 촬영을 취소하면 null을 반환한다.
  ///
  /// 촬영 중 발생하는 예외는 그대로 던져, 호출하는 화면에서 상황에 맞는
  /// 안내(예: "카메라를 실행하지 못했습니다.")를 표시할 수 있게 한다.
  Future<Uint8List?> pickCameraImage() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }
}
