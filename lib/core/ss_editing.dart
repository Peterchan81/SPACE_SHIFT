/// SS001 §10~§13 — 편집 화면(평면도·CAD·ISO·이미지)이 함께 쓰는 선택 상태, 단위, 입력 방식, 파일 내보내기 기반.
/// 세부 기능(Snap/Grid, 형식별 Export, 펜 도구 등)은 각 Work Order에서 구현한다.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/foundation.dart';

// ---------------- §10 선택 ----------------

/// 선택된 객체 — 종류·ID·주요 속성·편집 가능 여부를 한 형식으로(평면도/CAD/ISO/이미지 공통).
@immutable
class SsSelection {
  const SsSelection({required this.objectType, required this.objectId, this.properties = const {}, this.editable = true});
  static const SsSelection none = SsSelection(objectType: '', objectId: '');

  final String objectType;
  final String objectId;
  final Map<String, Object?> properties;
  final bool editable;

  bool get isEmpty => objectId.isEmpty;

  /// 선택 정보 표시줄 한 줄(예: "벽 W12 · 길이 3,200mm · 편집 가능").
  String summary({String Function(String key, Object? value)? format}) {
    if (isEmpty) return '선택 없음';
    final props = [for (final e in properties.entries) format?.call(e.key, e.value) ?? '${e.key} ${e.value}'];
    return [('$objectType $objectId').trim(), ...props, editable ? '편집 가능' : '읽기 전용'].join(' · ');
  }
}

// ---------------- §11 단위 ----------------

enum SsLengthUnit {
  mm('mm', 1),
  cm('cm', 10),
  m('m', 1000);

  const SsLengthUnit(this.symbol, this.mmPerUnit);
  final String symbol;
  final double mmPerUnit;
}

/// 길이는 내부적으로 항상 mm, 표시할 때만 단위를 바꾼다.
@immutable
class SsLength {
  const SsLength.mm(this.mm);
  SsLength.of(double value, SsLengthUnit unit) : mm = value * unit.mmPerUnit;

  final double mm;
  static const SsLength gridDefault = SsLength.mm(100); // 직접 그리기 기본 Grid(§11)

  double inUnit(SsLengthUnit unit) => mm / unit.mmPerUnit;

  String format(SsLengthUnit unit, {int? decimals}) {
    final v = inUnit(unit);
    final d = decimals ?? (unit == SsLengthUnit.mm ? 0 : unit == SsLengthUnit.cm ? 1 : 3);
    final text = v.toStringAsFixed(d);
    final parts = text.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '${parts.length > 1 ? '$whole.${parts[1]}' : whole}${unit.symbol}';
  }

  @override
  bool operator ==(Object other) => other is SsLength && other.mm == mm;
  @override
  int get hashCode => mm.hashCode;
}

// ---------------- §12 입력 ----------------

/// PC 마우스, Galaxy Tab 터치·S Pen을 같은 기준으로 다룬다.
enum SsInputKind { mouse, touch, stylus, unknown }

enum SsGesture { draw, select, drag, pan, zoom, pinchZoom }

abstract final class SsInput {
  static SsInputKind kindOf(PointerDeviceKind k) => switch (k) {
    PointerDeviceKind.mouse || PointerDeviceKind.trackpad => SsInputKind.mouse,
    PointerDeviceKind.touch => SsInputKind.touch,
    PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => SsInputKind.stylus,
    _ => SsInputKind.unknown,
  };

  /// 한 손가락/펜/마우스 왼쪽 드래그가 무엇을 하는가 — 편집 도구가 켜져 있으면 펜·마우스는 그리기, 손가락은 화면 이동
  /// (Tab에서 손으로 화면을 옮기다 선이 그려지지 않게). 두 손가락은 언제나 확대/축소.
  static SsGesture primaryDrag(SsInputKind kind, {required bool drawToolActive}) {
    if (!drawToolActive) return kind == SsInputKind.touch ? SsGesture.pan : SsGesture.drag;
    return kind == SsInputKind.touch ? SsGesture.pan : SsGesture.draw;
  }

  static const SsGesture multiTouch = SsGesture.pinchZoom;
}

// ---------------- §13 파일 내보내기 ----------------

enum SsExportFormat {
  png('PNG', 'png', 'image/png'),
  jpg('JPG', 'jpg', 'image/jpeg'),
  dxf('DXF', 'dxf', 'application/dxf');

  const SsExportFormat(this.label, this.extension, this.mime);
  final String label;
  final String extension;
  final String mime;
}

enum SsExportStatus {
  pending('준비'),
  exporting('내보내는 중'),
  succeeded('완료'),
  failed('실패');

  const SsExportStatus(this.label);
  final String label;
}

/// 내보내기 한 건 — 파일명·형식·저장 위치·상태·결과를 같은 형식으로.
@immutable
class SsExportJob {
  const SsExportJob({required this.fileName, required this.format, this.location, this.status = SsExportStatus.pending, this.error});

  final String fileName;
  final SsExportFormat format;
  final String? location;
  final SsExportStatus status;
  final String? error;

  /// 확장자를 붙이고 파일 이름에 쓸 수 없는 글자를 바꾼다.
  String get fullName {
    final base = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final ext = '.${format.extension}';
    return base.toLowerCase().endsWith(ext) ? base : '$base$ext';
  }

  SsExportJob started() => SsExportJob(fileName: fileName, format: format, location: location, status: SsExportStatus.exporting);
  SsExportJob succeeded(String savedTo) => SsExportJob(fileName: fileName, format: format, location: savedTo, status: SsExportStatus.succeeded);
  SsExportJob failedWith(String reason) => SsExportJob(fileName: fileName, format: format, location: location, status: SsExportStatus.failed, error: reason);
}
