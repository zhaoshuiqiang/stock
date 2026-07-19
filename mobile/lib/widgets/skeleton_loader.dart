import 'package:flutter/material.dart';

/// P4.3: lightweight animated skeleton placeholder for loading states.
///
/// Use [SkeletonLoader] for a single shimmering block, or [SkeletonList] for a
/// stack of lines approximating a card/list while data loads. Pure UI, no deps.
class SkeletonLoader extends StatefulWidget {
  final double height;
  final double width;
  final double radius;

  const SkeletonLoader({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius = 4,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
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
      builder: (context, _) {
        final t = _controller.value;
        final base = const Color(0xFF21262D);
        final highlight = const Color(0xFF30363D);
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, t),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// A vertical stack of skeleton lines approximating a loading card.
class SkeletonList extends StatelessWidget {
  final int lines;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.lines = 5,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines; i++) ...[
            SkeletonLoader(width: i.isEven ? double.infinity : 200),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
