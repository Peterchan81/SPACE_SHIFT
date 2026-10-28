/// SS004 — 시작 방식(sourceType)별 아이콘·색·설명(MASTER UI 4 카드 문구).
library;

import 'package:flutter/material.dart';

import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/theme/ss_master_theme.dart';

abstract final class SsSourceTypeVisual {
  static const Color imageGreen = Color(0xFF10B981);

  static IconData icon(SsSourceType t) => switch (t) {
    SsSourceType.floorPlanUpload => Icons.cloud_upload_outlined,
    SsSourceType.directDraw => Icons.edit_outlined,
    SsSourceType.imageTransform => Icons.image_outlined,
  };

  static IconData previewIcon(SsSourceType t) => switch (t) {
    SsSourceType.floorPlanUpload => Icons.architecture,
    SsSourceType.directDraw => Icons.draw_outlined,
    SsSourceType.imageTransform => Icons.compare_outlined,
  };

  static Color color(SsSourceType t) => switch (t) {
    SsSourceType.floorPlanUpload => SsMasterTheme.neonBlue,
    SsSourceType.directDraw => SsMasterTheme.neonPurple,
    SsSourceType.imageTransform => imageGreen,
  };

  static String description(SsSourceType t) => switch (t) {
    SsSourceType.floorPlanUpload => '도면 이미지를 업로드하여\n공간을 분석하고 시작합니다.',
    SsSourceType.directDraw => '간단한 도구로 직접 평면도를\n그리고 공간을 구성해보세요.',
    SsSourceType.imageTransform => '공간 사진을 업로드하여\n새로운 디자인을 만들어보세요.',
  };

  static String footer(SsSourceType t) => switch (t) {
    SsSourceType.floorPlanUpload => '지원 형식  JPG, PNG, PDF\n권장 해상도  1024 x 768 이상',
    SsSourceType.directDraw => '직관적인 편집 도구로\n쉽고 빠르게 공간을 그릴 수 있습니다.',
    SsSourceType.imageTransform => '사진을 업로드하면\nAI가 새로운 공간으로 변환해줍니다.',
  };
}
