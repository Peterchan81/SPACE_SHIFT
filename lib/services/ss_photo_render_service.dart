/// SS007 — MASTER UI 4-2-1 실제 AI 픽셀 재생성 호출 지점.
///
/// 지금은 외부 이미지 생성 AI를 호출하지 않는다(pubspec에 그런 패키지가 없고, 새 package를 추가하지
/// 않는 규칙을 따른다 — 기존 AiGenerationService의 "Mock이지만 실제처럼 보이는 결과" 원칙과 같다).
/// SS006에서 쌓인 편집 지시([SsPhotoScene])를 image 패키지만으로 원본 사진 위에 합성해 최종 이미지를
/// 만들어 돌려준다. 실제 AI 연동 시에는 이 클래스 내부(주로 [_compose])만 바꾸면 되고, 화면/컨트롤러
/// ([SsImageRenderController], ImageRenderingScreen)는 바뀌지 않는다.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

import '../core/ss_render_step.dart';
import '../models/ss_photo_scene.dart';

class SsPhotoRenderService {
  const SsPhotoRenderService({this.stepDelay = const Duration(milliseconds: 450)});

  /// 각 단계 사이에 기다리는 시간(§ 렌더링 단계 예시를 실제로 체감할 수 있게). 테스트에서는 Duration.zero로
  /// 줄여 쓴다.
  final Duration stepDelay;

  /// [onStep]은 각 단계가 시작될 때 한 번씩, 순서대로 불린다.
  Future<Uint8List> render(SsPhotoScene scene, {void Function(SsRenderStep step)? onStep}) async {
    for (final step in SsRenderStep.values) {
      onStep?.call(step);
      if (stepDelay > Duration.zero) await Future<void>.delayed(stepDelay);
    }
    try {
      return _compose(scene);
    } catch (e, st) {
      // 합성 실패를 "네트워크 오류"처럼 다른 원인으로 감추지 않는다 — 실제 원인은 로그로 남기고,
      // 다시 예외를 던져 호출한 쪽([SsAiTask])이 일반 재시도 안내를 보여주게 한다.
      debugPrint('SsPhotoRenderService 합성 실패 (${e.runtimeType}): $e\n$st');
      rethrow;
    }
  }

  Uint8List _compose(SsPhotoScene scene) {
    final decoded = img.decodeImage(scene.imageBytes);
    if (decoded == null) throw const FormatException('이미지를 해석할 수 없습니다');
    var out = decoded.clone();

    for (final o in scene.removedObjects) {
      _fillNormalized(out, o.x, o.y, o.width, o.height, img.ColorRgba8(120, 128, 140, 180));
    }

    for (final finish in scene.finishes.values) {
      final rect = _surfaceRect(finish.surface);
      final c = finish.colorValue;
      _fillNormalized(out, rect.$1, rect.$2, rect.$3, rect.$4, img.ColorRgba8((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, 90));
    }

    for (final o in scene.visibleObjects) {
      _outlineNormalized(out, o.x, o.y, o.width, o.height, img.ColorRgba8(59, 130, 246, 255));
    }

    for (final o in scene.openings) {
      _outlineNormalized(out, o.x, o.y, o.width, o.height, img.ColorRgba8(34, 211, 238, 255));
    }

    final lighting = scene.lighting;
    if (lighting != null) {
      out = img.adjustColor(out, brightness: 0.85 + lighting.brightness * 0.3, saturation: 0.9 + lighting.warmth * 0.25);
    }

    return img.encodePng(out);
  }

  (double, double, double, double) _surfaceRect(SsPhotoSurface surface) => switch (surface) {
    SsPhotoSurface.ceiling => (0.0, 0.0, 1.0, 0.2),
    SsPhotoSurface.wall => (0.0, 0.2, 1.0, 0.52),
    SsPhotoSurface.floor => (0.0, 0.72, 1.0, 0.28),
    SsPhotoSurface.molding => (0.0, 0.18, 1.0, 0.04),
    SsPhotoSurface.other => (0.0, 0.0, 1.0, 1.0),
  };

  void _fillNormalized(img.Image image, double nx, double ny, double nw, double nh, img.Color color) {
    final r = _rectPx(image, nx, ny, nw, nh);
    img.fillRect(image, x1: r.$1, y1: r.$2, x2: r.$3, y2: r.$4, color: color);
  }

  void _outlineNormalized(img.Image image, double nx, double ny, double nw, double nh, img.Color color) {
    final r = _rectPx(image, nx, ny, nw, nh);
    img.drawRect(image, x1: r.$1, y1: r.$2, x2: r.$3, y2: r.$4, color: color, thickness: 3);
  }

  (int, int, int, int) _rectPx(img.Image image, double nx, double ny, double nw, double nh) {
    final x1 = (nx * image.width).round().clamp(0, image.width - 1);
    final y1 = (ny * image.height).round().clamp(0, image.height - 1);
    final x2 = ((nx + nw) * image.width).round().clamp(0, image.width - 1);
    final y2 = ((ny + nh) * image.height).round().clamp(0, image.height - 1);
    return (x1, y1, x2, y2);
  }
}
