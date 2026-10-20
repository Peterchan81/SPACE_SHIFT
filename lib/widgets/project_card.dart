import 'package:flutter/material.dart';

class ProjectCard extends StatelessWidget {
  final String projectName;

  const ProjectCard({super.key, required this.projectName});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(projectName),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          // Navigate to project detail screen
        },
      ),
    );
  }
}