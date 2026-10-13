// lib/core/ui/motion.dart
//
// The app's motion vocabulary: one set of durations, curves and primitives so
// every screen moves the same way.
//
// ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// Each screen used to roll its own animation code. The outlet side ended up
// with three private copies of the same stagger widget, a private
// `_PressableScale`, and its own timings — so the same gesture felt different
// depending on which screen you were on, and the outlet home screen's entrance
// ran for ~900 ms (a 400 ms full-screen fade with a 900 ms staggered reveal on
// top of it) and replayed in full on every bottom-nav tap. Slow, and
// inconsistent with the rest of the app.
//
// The numbers below are deliberately short. Entrance motion exists to show
// where content came from, not to make people wait: a whole screen's reveal
// should land in roughly half a second. Interaction feedback is faster still,
// because it has to feel like a response rather than an animation.
//
// ─── ACCESSIBILITY ───────────────────────────────────────────────────────────
// Every primitive here honours the platform "reduce motion" setting. When it
// is on, content appears immediately instead of sliding or scaling — the
// information is identical, only the movement is dropped.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Durations and curves. Use these instead of inline millisecond values.
abstract final class Motion {
  /// Touch feedback — must read as a response, not an animation.
  static const Duration fast = Duration(milliseconds: 140);

  /// Small state flips: a chip selecting, a value swapping.
  static const Duration quick = Duration(milliseconds: 220);

  /// One element entering, or a crossfade between two states.
  static const Duration base = Duration(milliseconds: 300);

  /// A number counting to its new value.
  static const Duration count = Duration(milliseconds: 560);

  /// Gap between consecutive staggered items. Small on purpose: a 6-item list
  /// is fully revealed in 6 * 55 ms + 300 ms, just over half a second.
  static const Duration stagger = Duration(milliseconds: 55);

  /// Decelerating — the default for anything entering or settling.
  static const Curve enter = Curves.easeOutCubic;

  /// Sharper deceleration, for motion that should feel immediate.
  static const Curve snap = Curves.easeOutQuart;

  /// Symmetric — for something moving between two states it will return from.
  static const Curve inOut = Curves.easeInOutCubic;

  /// True when the platform asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// Fade + rise, delayed by `index * Motion.stagger`.
///
/// Self-contained on purpose: no parent controller to wire up, so adopting it
/// is a one-line change at each call site. Wrap each section or list item and
/// pass its position.
///
/// ```dart
/// StaggerIn(index: 0, child: _header()),
/// StaggerIn(index: 1, child: _salesCard()),
/// ```
class StaggerIn extends StatefulWidget {
  const StaggerIn({
    super.key,
    required this.index,
    required this.child,
    this.offset = 14,
    this.duration = Motion.base,
    this.enabled = true,
    this.maxSteps = 8,
  });

  final int index;
  final Widget child;

  /// Ceiling on the staggered delay, in steps.
  ///
  /// Without this a 30-row roster would make the last row wait
  /// 30 * 55 ms = 1.65 s — worse than no animation at all. Only the first
  /// screenful is visible while the cascade runs, so everything past this
  /// enters together.
  final int maxSteps;

  /// How far the child rises, in logical pixels.
  final double offset;

  final Duration duration;

  /// Set false to render immediately — e.g. for items that stream in later and
  /// shouldn't re-animate the whole list.
  final bool enabled;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// Owned so it can be cancelled. A bare `Future.delayed` keeps running after
  /// the widget is gone — harmless in itself, but it leaves a timer per item
  /// outliving a scrolled-away list, and it fails widget tests with "pending
  /// timers".
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _c.value = 1;
      return;
    }
    // A per-item delay rather than an Interval on a shared parent controller:
    // items added later (a new page of results) still enter properly instead of
    // snapping to whatever progress the shared controller had already reached.
    final steps = widget.index.clamp(0, widget.maxSteps);
    if (steps <= 0) {
      _c.forward();
      return;
    }
    _delay = Timer(Motion.stagger * steps, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || Motion.reduced(context)) return widget.child;

    final curved = CurvedAnimation(parent: _c, curve: Motion.enter);
    return FadeTransition(
      opacity: curved,
      // Pixel offset, not a fraction of the child's own size, so a tall card
      // and a short chip travel the same distance and read as one movement.
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// A tappable surface that dips under the finger.
///
/// Replaces the per-screen `_PressableScale` copies. Adds the haptic on press
/// (so the feedback starts the instant the finger lands rather than when the
/// action completes) and keeps the release animation even though `onTap` fires
/// on lift.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far it dips. Keep subtle; large cards need less than small ones.
  final double scale;

  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  void _setDown(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!_interactive) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (widget.haptic) HapticFeedback.selectionClick();
        _setDown(true);
      },
      onTapUp: (_) {
        _setDown(false);
        widget.onTap?.call();
      },
      onTapCancel: () => _setDown(false),
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.mediumImpact();
              _setDown(false);
              widget.onLongPress!.call();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: Motion.fast,
        curve: Motion.snap,
        child: widget.child,
      ),
    );
  }
}

/// Counts from the previous value to the new one whenever `value` changes.
///
/// Sales and attendance figures used to snap from a skeleton straight to the
/// final number, which made a freshly loaded screen look static. Counting makes
/// the update legible and tells the user the figure is live.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.builder,
    this.duration = Motion.count,
  });

  final double value;

  /// Formats the in-flight value — e.g. `(v) => Text('₹${v.round()}')`.
  final Widget Function(BuildContext context, double value) builder;

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return builder(context, value);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Motion.enter,
      // Adapt the 3-arg ValueWidgetBuilder to the 2-arg public API — callers
      // never need a `child` here, and asking for one is just noise.
      builder: (context, v, _) => builder(context, v),
    );
  }
}

/// Crossfade between states (loading → data → error) without a layout jump.
///
/// Use for the body of an `AsyncValue.when(...)`: the skeleton dissolves into
/// the real content instead of being replaced in a single frame.
///
/// NOTE: like `AnimatedSwitcher`, this only transitions when the incoming child
/// is a *different* widget (by runtime type or key). Two `Text` widgets with no
/// keys count as the same child and will swap instantly — give them keys if the
/// states share a type.
class MotionSwitcher extends StatelessWidget {
  const MotionSwitcher({
    super.key,
    required this.child,
    this.duration = Motion.base,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.enter,
      // Size the switcher to the incoming child and align to the top, so a
      // short skeleton growing into a tall card doesn't shove the page around.
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [
          ...previous,
          if (current != null) current,
        ],
      ),
      child: child,
    );
  }
}

/// A fade + rise page transition, matching `StaggerIn` so a pushed screen
/// enters the way content does.
Route<T> motionRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, animation, _, child) {
      if (Motion.reduced(context)) return child;
      final curved = CurvedAnimation(parent: animation, curve: Motion.enter);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
