import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flexpos/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthSurface extends ConsumerWidget {
  const AuthSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appName = ref.watch(coreAppNameProvider);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Row(
              children: [
                if (wide)
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFFF5F3EE),
                      child: Padding(
                        padding: const EdgeInsets.all(56),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const FlexPosLogo(width: 320, height: 180),
                            const SizedBox(height: 28),
                            Text(
                              appName,
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(color: const Color(0xFF14213D)),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Fast checkout. Accurate inventory. '
                              'One secure workspace for every branch.',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: const Color(0xFF3F4A5A),
                                    height: 1.4,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Theme(
                    data: AppTheme.dark(),
                    child: ColoredBox(
                      color: const Color(0xFF0D1422),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Align(
                                  alignment: Alignment.center,
                                  child: FlexPosLogo(
                                    width: 220,
                                    height: 124,
                                    light: true,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                child,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class FlexPosLogo extends StatelessWidget {
  const FlexPosLogo({
    this.width = 220,
    this.height = 124,
    this.light = false,
    super.key,
  });

  final double width;
  final double height;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: light
          ? ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
              child: Image.asset(
                'assets/branding/flexpos_logo.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                semanticLabel: 'FlexPOS logo',
              ),
            )
          : Image.asset(
              'assets/branding/flexpos_logo.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: 'FlexPOS logo',
            ),
    );
  }
}

final coreAppNameProvider = Provider<String>(
  (ref) => ref.watch(appConfigProvider).appName,
);
