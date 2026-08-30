import 'dart:io';

import 'package:image/image.dart' as img;

/// SS_V1_UI_MASTER.png에서 지정한 픽셀 영역을 잘라 assets/images/에 저장한다.
///
/// 사용법: dart run tool/crop_master_assets.dart <x> <y> <w> <h> <output_filename>
void main(List<String> args) {
  if (args.length != 5) {
    stderr.writeln('usage: dart run tool/crop_master_assets.dart <x> <y> <w> <h> <output_filename>');
    exit(1);
  }

  final x = int.parse(args[0]);
  final y = int.parse(args[1]);
  final w = int.parse(args[2]);
  final h = int.parse(args[3]);
  final outputName = args[4];

  final masterBytes = File('SS_V1_UI_MASTER.png').readAsBytesSync();
  final master = img.decodePng(masterBytes);
  if (master == null) {
    stderr.writeln('failed to decode SS_V1_UI_MASTER.png');
    exit(1);
  }

  stdout.writeln('master size: ${master.width}x${master.height}');

  final cropped = img.copyCrop(master, x: x, y: y, width: w, height: h);
  final outPath = 'assets/images/$outputName';
  File(outPath).writeAsBytesSync(img.encodePng(cropped));
  stdout.writeln('wrote $outPath (${cropped.width}x${cropped.height})');
}
