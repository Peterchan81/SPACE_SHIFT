/// SS-BUG-011 — 가이드·추천·팁 안내 화면이 함께 쓰는 MASTER(Dark Navy) 정보 화면 틀.
/// 스크롤되는 목록이라 작은 창(640×480)에서도 잘리지 않는다.
library;

import 'package:flutter/material.dart';

import 'package:ason_space/theme/ss_master_theme.dart';

class SsInfoPage extends StatelessWidget {
  const SsInfoPage({super.key, required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SsMasterTheme.background,
      appBar: AppBar(
        backgroundColor: SsMasterTheme.panel,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          title,
          key: const Key('ssInfoPageTitle'),
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(subtitle, key: const Key('ssInfoPageSubtitle'), style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 14, height: 1.4)),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}
