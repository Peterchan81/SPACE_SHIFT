import 'package:flutter/material.dart';

class ProjectManagementScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('프로젝트 관리'),
      ),
      body: Center(
        child: Text('프로젝트 목록이 여기에 표시됩니다.'),
      ),
    );
  }
}
