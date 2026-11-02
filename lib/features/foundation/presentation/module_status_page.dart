import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class ModuleStatusPage extends StatelessWidget {
  const ModuleStatusPage({
    required this.icon,
    required this.title,
    required this.phase,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String phase;
  final String description;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon,
      title: title,
      message: description,
      action: StatusBadge(label: '$phase · Pending', tone: StatusTone.info),
    );
  }
}
