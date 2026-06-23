// lib/core/widgets/skeleton.dart
//
// Lightweight, dependency-free shimmer skeleton system used as a premium
// loading placeholder across the app (instead of bare CircularProgressIndicators).
//
// Usage:
//   Shimmer(child: Column(children: [SkeletonBox(height: 60), ...]))        // dark screens
//   Shimmer.light(child: ...)                                              // light screens
//   SkeletonLine(width: 120)   SkeletonBox(width: 48, height: 48, radius: 12)
//
// How it works: skeleton shapes are opaque white boxes; a `ShaderMask` paints a
// sweeping 3-stop gradient (base -> highlight -> base) over them, animated with
// a single repeating controller. Cheap and smooth on both iOS and Android.

import 'package:flutter/material.dart';

class Shimmer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  /// Dark-screen defaults (app bg ~ #080808).
  const Shimmer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF1C1C1C),
    this.highlightColor = const Color(0xFF333333),
  });

  /// Light-screen variant (white backgrounds — manager screens).
  const Shimmer.light({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFE6E6E6),
    this.highlightColor = const Color(0xFFF7F7F7),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = (_ctrl.value * 2 - 1) * bounds.width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.32, 0.5, 0.68],
              transform: _ShimmerTranslate(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _ShimmerTranslate extends GradientTransform {
  final double dx;
  const _ShimmerTranslate(this.dx);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0.0, 0.0);
}

/// A single rounded placeholder block. Color is irrelevant (the Shimmer's
/// ShaderMask paints over it) — it just needs to be opaque.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 10,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A thin text-line placeholder.
class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  const SkeletonLine({super.key, this.width, this.height = 12});

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: width, height: height, radius: height / 2);
}

/// A generic card/list-row skeleton: leading square + two text lines + trailing.
class SkeletonTile extends StatelessWidget {
  final double height;
  final bool showLeading;
  final bool showTrailing;
  const SkeletonTile({
    super.key,
    this.height = 74,
    this.showLeading = true,
    this.showTrailing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (showLeading) ...[
            const SkeletonBox(width: 42, height: 42, radius: 12),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 140, height: 13),
                const SizedBox(height: 8),
                SkeletonLine(width: 90, height: 11),
              ],
            ),
          ),
          if (showTrailing) ...[
            const SizedBox(width: 12),
            const SkeletonBox(width: 44, height: 22, radius: 999),
          ],
        ],
      ),
    );
  }
}

/// Convenience: a vertical list of [count] tile skeletons wrapped in a Shimmer.
/// Use [dark]=false on light/manager screens.
class SkeletonList extends StatelessWidget {
  final int count;
  final bool dark;
  final double tileHeight;
  final bool showTrailing;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.count = 6,
    this.dark = true,
    this.tileHeight = 74,
    this.showTrailing = false,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: padding,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        count,
        (_) => SkeletonTile(height: tileHeight, showTrailing: showTrailing),
      ),
    );
    return dark ? Shimmer(child: list) : Shimmer.light(child: list);
  }
}
