// Regression test for the notices date-picker crash:
//   'text_scaler.dart': 'maxScale > minScale': is not true.
//
// Root cause: the app-level text-scale clamp used TextScaler.clamp(), which on
// a non-linear system scaler yields a _ClampedTextScaler. When a Material
// date/time picker re-clamps text scaling internally and the composed bounds
// collapse, the _ClampedTextScaler constructor asserts maxScale > minScale and
// crashes. clampedAppTextScaler() returns a LINEAR scaler, which re-clamps
// safely on every Flutter version.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:etl_manager_app/app/app.dart';

/// A non-linear scaler (does NOT override clamp -> uses the base clamp that
/// builds a _ClampedTextScaler), i.e. what an accessibility font setting yields.
class _NonLinearScaler extends TextScaler {
  const _NonLinearScaler(this._factor);
  final double _factor;
  @override
  double scale(double fontSize) => fontSize * _factor;
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => _factor;
}

void main() {
  test('clamps a large scale down to a LINEAR 1.3x', () {
    final result = clampedAppTextScaler(const _NonLinearScaler(1.8));
    expect(result, equals(TextScaler.linear(1.3)));
  });

  test('raises a tiny scale up to a LINEAR 1.0x', () {
    final result = clampedAppTextScaler(const _NonLinearScaler(0.7));
    expect(result, equals(TextScaler.linear(1.0)));
  });

  test('passes a normal 1.0 scale through as linear', () {
    final result = clampedAppTextScaler(TextScaler.linear(1.0));
    expect(result, equals(TextScaler.linear(1.0)));
  });

  test('the result re-clamps safely (what Material pickers do internally)', () {
    final result = clampedAppTextScaler(const _NonLinearScaler(1.8));
    // Collapsed bounds — this is the composition that used to crash.
    expect(
      () => result.clamp(minScaleFactor: 1.3, maxScaleFactor: 1.3).scale(14),
      returnsNormally,
    );
    expect(
      () => result.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3).scale(14),
      returnsNormally,
    );
  });

  test('regression guard: result is linear, never a composable clamped scaler',
      () {
    // If someone reverts to base.clamp(...), this scaler would be a
    // _ClampedTextScaler and NOT equal to a plain linear scaler.
    final result = clampedAppTextScaler(const _NonLinearScaler(1.8));
    expect(result, equals(TextScaler.linear(1.3)));
  });
}
