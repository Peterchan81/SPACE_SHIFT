import 'package:flutter/material.dart';

class ProjectCreationScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('프로젝트 생성'),
      ),
      body: Center(
        child: Text('프로젝트 생성을 위한 입력폼이 여기에 표시됩니다.'),
      ),
    );
  }
}
