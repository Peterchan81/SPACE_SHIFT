import 'package:flutter/material.dart';

import '../theme/space_shift_colors.dart';
import '../widgets/navigation_drawer.dart';
import '../widgets/project_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        title: const Text('SPACE SHIFT'),
        backgroundColor: SpaceShiftColors.primary,
      ),
      drawer: const NavigationDrawer(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                '최근 프로젝트',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    ProjectCard(projectName: '우리집 리모델링'),
                    ProjectCard(projectName: '상가 인테리어'),
                    ProjectCard(projectName: '사무실 디자인'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}