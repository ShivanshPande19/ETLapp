import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
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

  /// Outlet manager: their own outlet's staff calendars.
  Future<List<StaffCalendar>> outletCalendar(String month) async {
    final res = await _dio.get('/attendance/calendar/outlet',
        queryParameters: {'month': month});
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

/// Outlet-manager's own outlet staff calendars for a given "YYYY-MM".
final outletCalendarProvider = FutureProvider.autoDispose
    .family<List<StaffCalendar>, String>((ref, month) async {
  return ref.watch(calendarRepositoryProvider).outletCalendar(month);
});
