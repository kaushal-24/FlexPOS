import 'package:flexpos/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Card(
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
