import 'dart:async';

import 'package:flutter/material.dart';

/// Holds the app behind a short, branded startup screen.
///
/// The controller and timer share the same three-second duration so the
/// progress indicator reaches 100% exactly when the app is revealed.
class StartupGate extends StatefulWidget {
  const StartupGate({required this.child, super.key});

  final Widget child;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(seconds: 3);

  late final AnimationController _progressController;
  Timer? _completionTimer;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this, duration: _duration)
      ..forward();
    _completionTimer = Timer(_duration, () {
      if (mounted) {
        setState(() => _isComplete = true);
      }
    });
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isComplete) {
      return widget.child;
    }

    return FlexPosSplashScreen(progress: _progressController);
  }
}

class FlexPosSplashScreen extends StatelessWidget {
  const FlexPosSplashScreen({required this.progress, super.key});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF07152B),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: AnimatedBuilder(
                  animation: progress,
                  builder: (context, _) {
                    final value = progress.value.clamp(0.0, 1.0).toDouble();
                    final percent = (value * 100).round();

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/branding/flexpos_logo.png',
                          width: 320,
                          height: 220,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                        const SizedBox(height: 30),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 8,
                            backgroundColor: const Color(0x334F83D1),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF4F9BFF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Loading $percent%',
                          style: const TextStyle(
                            color: Color(0xFFE5EEFF),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
