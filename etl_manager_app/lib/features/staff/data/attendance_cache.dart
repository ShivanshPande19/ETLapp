// lib/features/staff/data/attendance_cache.dart
//
// The last OPEN shift the server confirmed, kept on the phone per person.
//
// ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// Budget Android phones kill a backgrounded app within minutes, so a staff
// member reopening the app mid-shift is almost always a cold start. The home
// screen then asks the server "am I checked in?" — and on a weak signal at the
// court that call fails. With nothing saved locally, the app had no way to know
// the shift was running and showed the "Check In" card, which to staff looks
// exactly like their shift being logged out. Many then never checked out, and
// the hourly sweep auto-closed the shift the next morning.
//
// Saving the open shift lets the app keep showing it until the server answers.
//
// ─── SHARED PHONES ───────────────────────────────────────────────────────────
// Staff without a phone log in on a colleague's, take their selfie, and log out
// again. So every entry is keyed by the signed-in person's email, and a read
// only ever returns that person's own shift. Nothing here can surface one
// person's shift to another.
//
// Only what the shift card shows is stored — no selfie URL.
//
// ─── NEVER LOAD-BEARING ──────────────────────────────────────────────────────
// Every call swallows its own errors. A broken cache must degrade to "no
// cache", never break a check-in or check-out.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/attendance_notifier.dart';

class AttendanceCache {
  AttendanceCache._();

  static const _prefix = 'attendance_open_shift_v1:';

  /// A saved shift older than this is assumed to have ended (and been closed
  /// by the server's sweep) and is never shown.
  ///
  /// The longest shifts here run 11:00 to 02:00 — 15 hours, or 16 with the
  /// hour-early check-in the server allows. 20 hours leaves room for a late
  /// check-out without ever resurrecting yesterday's shift.
  static const maxAge = Duration(hours: 20);

  static String _key(String owner) => '$_prefix${owner.trim().toLowerCase()}';

  /// Save [today] for [owner] if it is an open shift, otherwise forget it.
  ///
  /// Only an OPEN shift is worth keeping: it is the one state where showing
  /// "Check In" by mistake does harm.
  static Future<void> write(String owner, AttendanceToday today, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final checkIn = today.checkInTime;
      if (!today.checkedIn || today.checkedOut || checkIn == null) {
        await prefs.remove(_key(owner));
        return;
      }
      await prefs.setString(
        _key(owner),
        jsonEncode({
          'attendance_id': today.attendanceId,
          'check_in_time': checkIn.toUtc().toIso8601String(),
          'check_in_address': today.checkInAddress,
        }),
      );
      await _pruneStale(prefs, now ?? DateTime.now());
    } catch (_) {
      // Never let caching break a punch.
    }
  }

  /// [owner]'s saved open shift, or null if there is none or it is too old.
  static Future<AttendanceToday?> read(String owner, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(owner));
      if (raw == null) return null;
      final today = _decode(raw);
      if (today == null || _isStale(today, now ?? DateTime.now())) {
        await prefs.remove(_key(owner));
        return null;
      }
      return today;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String owner) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(owner));
    } catch (_) {}
  }

  static AttendanceToday? _decode(String raw) {
    final map = jsonDecode(raw);
    if (map is! Map) return null;
    final checkIn = DateTime.tryParse('${map['check_in_time']}');
    if (checkIn == null) return null;
    return AttendanceToday(
      attendanceId: map['attendance_id'] as int?,
      checkedIn: true,
      checkInTime: checkIn.toLocal(),
      checkInAddress: map['check_in_address'] as String?,
    );
  }

  static bool _isStale(AttendanceToday t, DateTime now) {
    final checkIn = t.checkInTime;
    return checkIn == null || now.difference(checkIn) > maxAge;
  }

  /// Drop anyone's entry that has aged out. A shared phone collects one entry
  /// per person who has used it; this keeps that from growing without bound.
  static Future<void> _pruneStale(SharedPreferences prefs, DateTime now) async {
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      final raw = prefs.getString(key);
      final t = raw == null ? null : _decode(raw);
      if (t == null || _isStale(t, now)) await prefs.remove(key);
    }
  }
}
