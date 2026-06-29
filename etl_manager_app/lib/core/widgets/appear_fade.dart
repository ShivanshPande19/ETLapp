// lib/core/widgets/appear_fade.dart
//
// Mount-triggered entrance animation. Wrap any widget (typically the content
// shown after a skeleton loader) and it fades + gently slides up when it first
// appears — so content doesn't pop in abruptly after loading.
//
// Because it animates on mount, the timing is always correct: it plays exactly
// when the widget is inserted into the tree (i.e. when the data arrives), with
// no external controller to get out of sync.

import 'package:flutter/material.dart';

class AppearFade extends StatefulWidget {
  final Widget child;
  final Duration duration;

  /// Optional start delay — use index * step for a staggered list.
  final int delayMs;

  /// Initial downward offset as a fraction of the child's height.
  final double slide;

  const AppearFade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 460),
    this.delayMs = 0,
    this.slide = 0.04,
  });

  @override
  State<AppearFade> createState() => _AppearFadeState();
}

class _AppearFadeState extends State<AppearFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _pos;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    final curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _fade = curve;
    _pos = Tween<Offset>(
      begin: Offset(0, widget.slide),
      end: Offset.zero,
    ).animate(curve);

    if (widget.delayMs > 0) {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _ctrl.forward();
      });
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _pos, child: widget.child),
    );
  }
}
