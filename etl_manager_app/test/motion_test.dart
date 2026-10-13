// Contract tests for the shared motion vocabulary (core/ui/motion.dart).
//
// These are cheap guards on the properties that actually matter to a user:
//
//   • content ALWAYS ends up visible — an entrance animation must never be
//     able to leave something stuck at zero opacity
//   • the staggered delay is CAPPED, so a long list cannot crawl in (the whole
//     point of `maxSteps`; without it a 30-row roster made the last row wait
//     over 1.5 s)
//   • "reduce motion" is honoured — content appears immediately, with the same
//     information
//   • a tap still reaches its callback through the press-scale wrapper
//
// Animation *aesthetics* can't be asserted, but these regressions all can.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:etl_manager_app/core/ui/motion.dart';

/// Wraps [child] in the minimum needed to pump it, optionally with the
/// platform "reduce motion" flag on.
Widget _host(Widget child, {bool reduceMotion = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    ),
  );
}

double _opacityOf(WidgetTester tester, Finder child) {
  final fade = tester.widgetList<FadeTransition>(
    find.ancestor(of: child, matching: find.byType(FadeTransition)),
  );
  // No FadeTransition at all means the child is rendered plainly (reduced
  // motion), which counts as fully visible.
  if (fade.isEmpty) return 1.0;
  return fade.first.opacity.value;
}

void main() {
  group('StaggerIn', () {
    testWidgets('settles fully visible', (tester) async {
      await tester.pumpWidget(
        _host(const StaggerIn(index: 0, child: Text('hello'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('hello'), findsOneWidget);
      expect(_opacityOf(tester, find.text('hello')), 1.0);
    });

    testWidgets('a later item starts hidden, then arrives', (tester) async {
      await tester.pumpWidget(
        _host(const StaggerIn(index: 4, child: Text('late'))),
      );
      // Still inside its delay: present in the tree but not yet shown.
      await tester.pump();
      expect(find.text('late'), findsOneWidget);
      expect(_opacityOf(tester, find.text('late')), 0.0);

      // `pumpAndSettle` alone won't get there: with no frame scheduled yet it
      // returns before the delay timer fires, so pump past it explicitly.
      await tester.pump(Motion.stagger * 4);
      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.text('late')), 1.0);
    });

    testWidgets('caps the delay so long lists do not crawl', (tester) async {
      // index 400 must behave like index `maxSteps`, not wait 22 seconds.
      await tester.pumpWidget(
        _host(const StaggerIn(index: 400, child: Text('far'))),
      );
      // Capped at maxSteps (8), so pumping that delay is enough — an uncapped
      // index 400 would need 22 seconds and this would fail.
      await tester.pump(Motion.stagger * 8);
      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.text('far')), 1.0);

      // Pin the arithmetic the cap guarantees: worst case is
      // maxSteps * stagger + duration, comfortably under a second.
      final worstCase = Motion.stagger * 8 + Motion.base;
      expect(worstCase.inMilliseconds, lessThan(1000));
    });

    testWidgets('reduced motion renders immediately, un-animated', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const StaggerIn(index: 6, child: Text('a11y')),
          reduceMotion: true,
        ),
      );
      // One pump only — no settling, no delay.
      await tester.pump();
      expect(find.text('a11y'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('a11y'),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });

    testWidgets('enabled: false skips the animation entirely', (tester) async {
      await tester.pumpWidget(
        _host(const StaggerIn(index: 9, child: Text('plain'), enabled: false)),
      );
      await tester.pump();
      expect(_opacityOf(tester, find.text('plain')), 1.0);
    });
  });

  group('AnimatedCount', () {
    testWidgets('finishes on the exact target value', (tester) async {
      await tester.pumpWidget(
        _host(
          AnimatedCount(
            value: 1234,
            builder: (_, v) => Text(v.round().toString()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1234'), findsOneWidget);
    });

    testWidgets('passes through intermediate values while counting', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AnimatedCount(
            value: 1000,
            builder: (_, v) => Text(v.round().toString()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      // Mid-flight: something other than the final figure is on screen.
      expect(find.text('1000'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('reduced motion shows the final value at once', (tester) async {
      await tester.pumpWidget(
        _host(
          AnimatedCount(
            value: 99,
            builder: (_, v) => Text(v.round().toString()),
          ),
          reduceMotion: true,
        ),
      );
      await tester.pump();
      expect(find.text('99'), findsOneWidget);
    });
  });

  group('Pressable', () {
    testWidgets('forwards the tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          Pressable(
            onTap: () => taps++,
            haptic: false,
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      );
      await tester.tap(find.byType(SizedBox));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('scales back to rest after the press', (tester) async {
      await tester.pumpWidget(
        _host(
          Pressable(
            onTap: () {},
            haptic: false,
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SizedBox)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1.0),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        1.0,
      );
    });

    testWidgets('without a callback it adds no gesture layer', (tester) async {
      await tester.pumpWidget(
        _host(const Pressable(child: Text('inert'))),
      );
      await tester.pump();
      expect(find.text('inert'), findsOneWidget);
      expect(find.byType(AnimatedScale), findsNothing);
    });
  });

  group('MotionSwitcher', () {
    testWidgets('shows the current child', (tester) async {
      await tester.pumpWidget(
        _host(const MotionSwitcher(child: Text('loaded'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('loaded'), findsOneWidget);
    });

    testWidgets('crossfades to a replacement and drops the old one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const MotionSwitcher(
            child: Text('skeleton', key: ValueKey('skeleton')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _host(
          const MotionSwitcher(
            child: Text('content', key: ValueKey('content')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      // Both on screen mid-crossfade — that is the point of the switcher.
      expect(find.text('skeleton'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('skeleton'), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });
  });

  group('Motion scale', () {
    test('durations are ordered from feedback to entrance', () {
      expect(Motion.fast, lessThan(Motion.quick));
      expect(Motion.quick, lessThan(Motion.base));
      expect(Motion.base, lessThan(Motion.count));
    });

    test('touch feedback is fast enough to read as a response', () {
      // Beyond ~150 ms a press stops feeling like direct manipulation.
      expect(Motion.fast.inMilliseconds, lessThanOrEqualTo(150));
    });

    test('a full screen of staggered sections lands within ~0.6s', () {
      const sections = 4;
      final total = Motion.stagger * sections + Motion.base;
      expect(total.inMilliseconds, lessThanOrEqualTo(600));
    });
  });
}
