import 'package:flexpos/app/theme/app_motion.dart';
import 'package:flexpos/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

class LoadingSkeletonBox extends StatefulWidget {
  const LoadingSkeletonBox({
    required this.height,
    this.width,
    this.borderRadius = AppRadii.md,
    super.key,
  });

  final double height;
  final double? width;
  final double borderRadius;

  @override
  State<LoadingSkeletonBox> createState() => _LoadingSkeletonBoxState();
}

class _LoadingSkeletonBoxState extends State<LoadingSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.ambient,
      value: 0.35,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.maybeOf(context);
    final reduceMotion =
        mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0.35;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            scheme.surfaceContainerHighest,
            _controller.value,
          ),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

class DataPageSkeleton extends StatelessWidget {
  const DataPageSkeleton({
    required this.sectionLabel,
    this.itemCount = 6,
    this.showFilter = true,
    super.key,
  });

  final String sectionLabel;
  final int itemCount;
  final bool showFilter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading $sectionLabel',
      child: ExcludeSemantics(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxl,
            AppSpacing.xl,
            AppSpacing.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LoadingSkeletonBox(width: 210, height: 32),
              const SizedBox(height: AppSpacing.sm),
              const LoadingSkeletonBox(width: 330, height: 16),
              if (showFilter) ...[
                const SizedBox(height: AppSpacing.xl),
                const LoadingSkeletonBox(height: 52),
              ],
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1080
                      ? 3
                      : constraints.maxWidth >= 680
                      ? 2
                      : 1;
                  const spacing = AppSpacing.sm;
                  final width =
                      (constraints.maxWidth - (columns - 1) * spacing) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (var index = 0; index < itemCount; index++)
                        SizedBox(width: width, child: const _SkeletonCard()),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DataListSkeleton extends StatelessWidget {
  const DataListSkeleton({
    required this.sectionLabel,
    this.itemCount = 5,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    super.key,
  });

  final String sectionLabel;
  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading $sectionLabel',
      child: ExcludeSemantics(
        child: ListView.separated(
          padding: padding,
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, _) => const _SkeletonCard(compact: true),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LoadingSkeletonBox(height: 18, width: compact ? 180 : 150),
            const SizedBox(height: AppSpacing.sm),
            const LoadingSkeletonBox(height: 13),
            const SizedBox(height: AppSpacing.xs),
            const LoadingSkeletonBox(width: 120, height: 13),
            if (!compact) ...[
              const SizedBox(height: AppSpacing.lg),
              const LoadingSkeletonBox(width: 86, height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
