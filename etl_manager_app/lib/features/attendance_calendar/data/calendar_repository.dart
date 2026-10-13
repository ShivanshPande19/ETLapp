import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../outlets/domain/outlet_providers.dart';
import 'calendar_models.dart';

class CalendarRepository {
  final Dio _dio;
  CalendarRepository(this._dio);

  Future<AttendanceCalendar> myCalendar(String month) async {
    final res = await _dio.get('/attendance/calendar',
        queryParameters: {'month': month});
    return AttendanceCalendar.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<CourtCalendar>> courtCalendar(String month, {int? courtId}) async {
    final res = await _dio.get('/attendance/calendar/court', queryParameters: {
      'month': month,
      if (courtId != null) 'court_id': courtId,
    });
    final data = res.data as Map<String, dynamic>;
    return (data['courts'] as List? ?? [])
        .map((e) => CourtCalendar.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Outlet manager: one of their outlets' staff calendars.
  ///
  /// `outletId` MUST be sent by a multi-outlet owner: the endpoint only infers
  /// the outlet when the caller manages exactly one, and otherwise answers
  /// 400 "outlet_id is required — you manage multiple outlets." It used to be
  /// omitted unconditionally, so Settings → Staff Attendance simply failed for
  /// every multi-outlet owner (and single-outlet owners never saw it).
  Future<List<StaffCalendar>> outletCalendar(String month, {int? outletId}) async {
    final res = await _dio.get('/attendance/calendar/outlet', queryParameters: {
      'month': month,
      if (outletId != null) 'outlet_id': outletId,
    });
    final data = res.data as Map<String, dynamic>;
    return (data['staff'] as List? ?? [])
        .map((e) => StaffCalendar.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return CalendarRepository(ref.watch(dioProvider));
});

/// Staff's own calendar for a given "YYYY-MM".
final myCalendarProvider = FutureProvider.autoDispose
    .family<AttendanceCalendar, String>((ref, month) async {
  return ref.watch(calendarRepositoryProvider).myCalendar(month);
});

/// Manager court-wise calendars for a given "YYYY-MM".
final courtCalendarProvider = FutureProvider.autoDispose
    .family<List<CourtCalendar>, String>((ref, month) async {
  return ref.watch(calendarRepositoryProvider).courtCalendar(month);
});

/// Outlet-manager's staff calendars for the SELECTED outlet, for a "YYYY-MM".
///
/// Watches `selectedOutletIdProvider` (same pattern as `dailyRosterProvider`),
/// so a multi-outlet owner both gets a valid request and sees the calendar
/// refetch when they switch outlets — previously the header named the selected
/// outlet while the request carried no outlet at all.
final outletCalendarProvider = FutureProvider.autoDispose
    .family<List<StaffCalendar>, String>((ref, month) async {
  final outletId = ref.watch(selectedOutletIdProvider);
  return ref
      .watch(calendarRepositoryProvider)
      .outletCalendar(month, outletId: outletId);
});
