import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const quick = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const emphasized = Duration(milliseconds: 240);
  static const ambient = Duration(milliseconds: 1000);

  static const enterCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;

  static Duration resolveDuration(
    MediaQueryData? mediaQuery,
    Duration preferred,
  ) {
    if (mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true) {
      return Duration.zero;
    }
    return preferred;
  }

  static Duration durationOf(BuildContext context, Duration preferred) {
    return resolveDuration(MediaQuery.maybeOf(context), preferred);
  }
}

class AppMotionSwitcher extends StatelessWidget {
  const AppMotionSwitcher({
    required this.motionKey,
    required this.child,
    this.duration = AppMotion.standard,
    this.alignment = Alignment.center,
    super.key,
  });

  final Key motionKey;
  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = AppMotion.durationOf(context, duration);
    return AnimatedSwitcher(
      duration: effectiveDuration,
      reverseDuration: effectiveDuration,
      switchInCurve: AppMotion.enterCurve,
      switchOutCurve: AppMotion.exitCurve,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: alignment,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: motionKey, child: child),
    );
  }
}
