import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A simple pulse skeleton that approximates the home-card shape.
class SkeletonCard extends StatefulWidget {
  final double height;
  final EdgeInsetsGeometry? margin;

  const SkeletonCard({
    super.key,
    this.height = 96,
    this.margin,
  });

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          height: widget.height,
          margin: widget.margin ?? const EdgeInsets.only(bottom: kHomeSectionGap),
          decoration: BoxDecoration(
            color: Color.lerp(
              Theme.of(context).colorScheme.surfaceContainerHighest,
              Theme.of(context).colorScheme.surface,
              _controller.value,
            ),
            borderRadius: BorderRadius.circular(kHomeCardRadius),
          ),
        );
      },
    );
  }
}

/// A list of skeleton cards with consistent gaps.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const SkeletonList({
    super.key,
    this.itemCount = 3,
    this.itemHeight = 96,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        itemCount,
        (index) => SkeletonCard(height: itemHeight),
      ),
    );
  }
}
