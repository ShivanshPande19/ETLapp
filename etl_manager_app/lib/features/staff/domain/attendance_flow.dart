// lib/features/staff/domain/attendance_flow.dart
//
// THE single capture→submit path for attendance.
//
// ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// `MarkAttendanceScreen` only CAPTURES a selfie + location and pops them back;
// the caller has to SUBMIT them. That submit step was copy-pasted into four
// separate screens:
//
//   • staff_home_screen.dart         (ETL staff)
//   • outlet_staff_home_screen.dart  (outlet staff)
//   • maintenance_home_screen.dart   (Crownest Maintenance Head)
//   • home_screen.dart               (Crownest Zone Manager)
//
// Four copies meant four chances to get it wrong, and the Zone Manager's copy
// was wrong: it opened the camera and threw the result away, so the photo was
// captured but never uploaded. Fixing that in one screen fixed nothing in the
// other three.
//
// Every one of those screens now calls `AttendanceFlow.run(...)`, so a fix
// lands everywhere at once. Add a role, and it inherits the correct behaviour
// for free.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'attendance_notifier.dart';

/// Which half of the shift we're recording. The capture screen needs to know:
/// the geofence is enforced on check-IN only (a person who has already left
/// the court must still be able to clock out), and a check-OUT photo is
/// optional server-side.
enum AttendanceAction { checkIn, checkOut }

/// Lets each screen keep its own snackbar styling while sharing the logic.
typedef AttendanceMessenger = void Function(String message, {bool isError});

class AttendanceFlow {
  AttendanceFlow._();

  static const String routePath = '/staff/mark-attendance';

  /// The capture screen's location, carrying the action in the query string.
  /// `state.matchedLocation` ignores the query, so the router's per-role
  /// redirect guards keep matching on the bare path.
  static String routeFor(AttendanceAction action) =>
      '$routePath?mode=${action == AttendanceAction.checkOut ? 'out' : 'in'}';

  static AttendanceAction actionFromQuery(String? mode) =>
      mode == 'out' ? AttendanceAction.checkOut : AttendanceAction.checkIn;

  /// What tapping the attendance card should do right now, or null when the
  /// shift is already complete for the day.
  static AttendanceAction? nextAction(AttendanceState state) {
    if (state.isCheckedOut) return null;
    return state.isCheckedIn ? AttendanceAction.checkOut : AttendanceAction.checkIn;
  }

  /// Open the capture screen, then submit whatever it returns.
  ///
  /// Reports progress/outcome through [notify] and returns true only when the
  /// server accepted the punch. A plain back-out (no capture) is silent.
  static Future<bool> run(
    BuildContext context,
    WidgetRef ref,
    AttendanceAction action, {
    required AttendanceMessenger notify,
  }) async {
    HapticFeedback.selectionClick();

    final result = await context.push<Object?>(routeFor(action));
    if (!context.mounted) return false;
    // User pressed back without capturing — not an error, say nothing.
    if (result is! Map) return false;

    final lat = (result['latitude'] as num?)?.toDouble();
    final lng = (result['longitude'] as num?)?.toDouble();
    final imagePath = result['image_path'] as String?;
    final accuracy = (result['accuracy'] as num?)?.toDouble();
    final isMocked = result['is_mocked'] == true;

    if (lat == null || lng == null || (lat == 0 && lng == 0)) {
      notify('Could not capture your location. Please try again.', isError: true);
      return false;
    }

    final notifier = ref.read(attendanceNotifierProvider.notifier);

    if (action == AttendanceAction.checkOut) {
      // Photo is OPTIONAL on check-out (the backend accepts a photo-less one),
      // so a camera that refuses to start can never strand someone mid-shift.
      await notifier.checkOut(
        lat: lat,
        lng: lng,
        imagePath: imagePath,
        accuracy: accuracy,
        isMocked: isMocked,
      );
    } else {
      if (imagePath == null) {
        notify('Could not capture your photo. Please try again.', isError: true);
        return false;
      }
      await notifier.markAttendance(
        lat: lat,
        lng: lng,
        imagePath: imagePath,
        accuracy: accuracy,
        isMocked: isMocked,
      );
    }

    final state = ref.read(attendanceNotifierProvider);
    if (state.status == AttendanceStatus.error) {
      notify(state.errorMessage ?? 'Something went wrong.', isError: true);
      // Re-sync so the card shows the server's truth, not our optimistic guess
      // (e.g. a 409 "already checked in" means we were out of date).
      await notifier.loadToday();
      return false;
    }

    HapticFeedback.mediumImpact();
    notify(
      action == AttendanceAction.checkOut
          ? 'Checked out. Shift complete!'
          : 'Checked in successfully!',
    );
    return true;
  }
}
