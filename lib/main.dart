import 'package:flutter/material.dart';
import 'package:ason_space/screens/login_screen.dart';
import 'package:ason_space/screens/home_screen.dart';
import 'package:ason_space/screens/project_management_screen.dart';

void main() {
  runApp(SpaceShiftApp());
}

class SpaceShiftApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPACE SHIFT',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => LoginScreen(),
        '/home': (context) => HomeScreen(),
        '/project_management': (context) => ProjectManagementScreen(),
      },
    );
  }
}