// lib/features/staff/data/attendance_location.dart
//
// Bounded, accuracy-aware location acquisition for attendance.
//
// ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// The capture screen used to call
//     Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
// exactly once, with NO time limit, and then treated whatever came back as the
// truth. That single line caused both attendance bugs we hit every day:
//
//  1. THE INFINITE BLACK SCREEN (worst on CHECK-OUT).
//     `timeLimit: null` makes the Android fused provider wait FOREVER when it
//     cannot produce a high-accuracy fix — indoors, in the evening, with
//     battery-saver/doze active, or when the user granted only "Approximate
//     location" (Android 12+). The screen sat on a black Scaffold with a
//     spinner, no back button and no error, so the shift could never be
//     closed. It bit check-OUT far more than check-IN because at the end of a
//     shift the person is deep inside the court, while at check-in they are
//     usually walking in from outside with a warm GPS fix.
//
//  2. THE FALSE "YOU ARE OUTSIDE YOUR ZONE".
//     The first fix Android hands back is routinely a coarse network/fused fix
//     with an accuracy of 100–3000 m. The old code consumed it as if it were
//     exact — it only clamped the geofence *buffer* to 75 m — so a fix with a
//     1.5 km error bar read as "you are 800 m from your zone" while the person
//     was standing inside it.
//
// The cure for both is the same: treat a position as a MEASUREMENT WITH AN
// ERROR BAR. Keep listening until the error bar is small enough to decide a
// ~150 m geofence, stop at a hard deadline, and then report honestly instead
// of hanging or guessing.
//
// This service is shared by every attendance capture (ETL staff, outlet staff,
// Crownest Maintenance Head and Crownest Zone Manager) so the behaviour can
// never drift between roles again.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Why we could not produce a position we're willing to act on.
enum LocationFailure {
  /// Device location (GPS) is switched off system-wide.
  serviceDisabled,

  /// The user declined the permission prompt this time.
  permissionDenied,

  /// The user declined permanently — only the OS settings screen can fix it.
  permissionDeniedForever,

  /// iOS 14+ "Precise Location: Off". An approximate location is deliberately
  /// fuzzed by kilometres and can never satisfy a geofence.
  reducedAccuracy,

  /// We listened until the deadline and got no fix at all.
  noFix,
}

/// A position plus a verdict on whether its error bar is small enough to make
/// a geofence decision with.
@immutable
class LocationFix {
  const LocationFix(this.position);

  final Position position;

  double get latitude => position.latitude;
  double get longitude => position.longitude;
  double get accuracy => position.accuracy;
  bool get isMocked => position.isMocked;

  /// Tight enough to decide "inside / outside a ~150 m circle".
  bool get isPrecise => accuracy > 0 && accuracy <= AttendanceLocation.targetAccuracyM;

  /// So coarse that any inside/outside verdict would be a coin flip. This is
  /// what an Android "Approximate location" grant looks like.
  bool get isUnusable => accuracy <= 0 || accuracy > AttendanceLocation.usableAccuracyM;

  String get accuracyLabel => '±${accuracy.round()} m';
}

/// Either a fix we're willing to use, or the reason we have none.
@immutable
class LocationOutcome {
  const LocationOutcome.success(LocationFix this.fix) : failure = null;
  const LocationOutcome.failed(LocationFailure this.failure) : fix = null;

  final LocationFix? fix;
  final LocationFailure? failure;

  bool get ok => fix != null;
}

class AttendanceLocation {
  AttendanceLocation._();

  /// Stop as soon as the fix is this good — plenty for a 150 m geofence, and
  /// quick to reach outdoors (usually 1–3 s).
  static const double targetAccuracyM = 40;

  /// Past this the fix cannot place someone inside a ~150 m circle, so we
  /// refuse to let it decide a check-in (the server applies the same rule).
  static const double usableAccuracyM = 200;

  /// Hard ceiling on how long we ever make the user wait. The old code had no
  /// ceiling at all — this is the line that kills the infinite spinner.
  static const Duration deadline = Duration(seconds: 15);

  /// A cached fix older than this is shown as a preview but never trusted.
  static const Duration _lastKnownMaxAge = Duration(minutes: 2);

  /// Acquire the best position we can within [deadline].
  ///
  /// [onProgress] fires every time the best-known fix improves, so the UI can
  /// show the error bar shrinking ("±120 m" → "±8 m") instead of a dead
  /// spinner. It always completes — by a fix or by a [LocationFailure].
  static Future<LocationOutcome> acquire({
    ValueChanged<LocationFix>? onProgress,
  }) async {
    try {
      return await _acquire(onProgress);
    } catch (_) {
      // A plugin/platform exception must never escape into the UI as an
      // unhandled error — the caller gets an actionable failure instead.
      return const LocationOutcome.failed(LocationFailure.noFix);
    }
  }

  static Future<LocationOutcome> _acquire(
    ValueChanged<LocationFix>? onProgress,
  ) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationOutcome.failed(LocationFailure.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationOutcome.failed(
        LocationFailure.permissionDeniedForever,
      );
    }
    if (permission == LocationPermission.denied) {
      return const LocationOutcome.failed(LocationFailure.permissionDenied);
    }

    // iOS 14+ reports "Precise: Off" here, which we can name exactly. Android
    // always answers `unknown` (the plugin doesn't surface its Approximate
    // grant), so on Android a coarse grant is caught by the accuracy
    // convergence below instead — same outcome, different route.
    try {
      final status = await Geolocator.getLocationAccuracy();
      if (status == LocationAccuracyStatus.reduced) {
        return const LocationOutcome.failed(LocationFailure.reducedAccuracy);
      }
    } catch (_) {
      // Not supported on this platform/version — fall through.
    }

    Position? best;
    void consider(Position p) {
      // `accuracy == 0` means "unknown" on some devices; never let it win.
      final better = best == null ||
          (p.accuracy > 0 && (best!.accuracy <= 0 || p.accuracy <= best!.accuracy));
      if (!better) return;
      best = p;
      onProgress?.call(LocationFix(p));
    }

    // Warm start: show something immediately rather than an empty screen.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          DateTime.now().difference(last.timestamp).abs() <= _lastKnownMaxAge) {
        consider(last);
      }
    } catch (_) {
      // Non-fatal — the stream below is the real source.
    }

    final settled = Completer<void>();
    StreamSubscription<Position>? sub;
    // Owned explicitly (rather than Future.timeout) so it is always cancelled
    // and can't outlive this call as a dangling timer.
    final deadlineTimer = Timer(deadline, () {
      if (!settled.isCompleted) settled.complete();
    });
    try {
      sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
        (p) {
          consider(p);
          // Good enough — don't keep the user (or the GPS radio) waiting.
          if (p.accuracy > 0 &&
              p.accuracy <= targetAccuracyM &&
              !settled.isCompleted) {
            settled.complete();
          }
        },
        onError: (Object _) {
          // The stream is done for; fall back to whatever we already have.
          if (!settled.isCompleted) settled.complete();
        },
        cancelOnError: false,
      );

      await settled.future;
    } finally {
      deadlineTimer.cancel();
      await sub?.cancel();
    }

    final fix = best;
    if (fix == null) {
      return const LocationOutcome.failed(LocationFailure.noFix);
    }
    return LocationOutcome.success(LocationFix(fix));
  }

  static LocationSettings _settings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          // Ask the fused provider for a fresh fix roughly every 800 ms so the
          // accuracy converges visibly instead of arriving once and sticking.
          intervalDuration: const Duration(milliseconds: 800),
          forceLocationManager: false,
          // Deliberately null: WE own the deadline (see `deadline`). Letting
          // the plugin time out throws instead of handing back the best fix
          // we had, which is exactly what we want to avoid.
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );
    }
  }

  /// One place for the user-facing copy, so every caller says the same thing.
  static String messageFor(LocationFailure failure) {
    switch (failure) {
      case LocationFailure.serviceDisabled:
        return 'Location is turned off on this phone. Switch on GPS / Location '
            'and try again.';
      case LocationFailure.permissionDenied:
        return 'This app needs location access to mark attendance. Please allow '
            'it and try again.';
      case LocationFailure.permissionDeniedForever:
        return 'Location access is blocked for this app. Open Settings → '
            'Permissions → Location and allow it, then come back.';
      case LocationFailure.reducedAccuracy:
        return 'Precise Location is off, so your position can be wrong by '
            'kilometres. Turn on Precise Location for this app and try again.';
      case LocationFailure.noFix:
        return 'Could not get a GPS fix. Step near a window or outside, make '
            'sure battery saver is off, then try again.';
    }
  }

  /// True when the fix is the user's to repair in the OS settings screen.
  static bool needsAppSettings(LocationFailure failure) =>
      failure == LocationFailure.permissionDeniedForever ||
      failure == LocationFailure.reducedAccuracy;

  static Future<void> openSettingsFor(LocationFailure failure) {
    if (failure == LocationFailure.serviceDisabled) {
      return Geolocator.openLocationSettings();
    }
    return Geolocator.openAppSettings();
  }
}
