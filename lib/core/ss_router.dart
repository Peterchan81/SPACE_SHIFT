import 'package:flutter/material.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/login_screen.dart';
import 'package:ason_space/screens/home_screen.dart';
import 'package:ason_space/screens/project_management_screen.dart';

/// SS001 공통 라우터: 각 stage를 route로 연결
class SsRouter {
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final SsStage? stage = SsStage.fromRoute(settings.name);
    switch (stage) {
      case SsStage.login:
        return MaterialPageRoute(builder: (_) => LoginScreen());
      case SsStage.home:
        return MaterialPageRoute(builder: (_) => HomeScreen());
      case SsStage.projectManagement:
        return MaterialPageRoute(builder: (_) => ProjectManagementScreen());
      // 추가 stage별 라우트 구현 필요
      default:
        return null;
    }
  }
}
