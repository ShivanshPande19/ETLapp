import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ✅ JWT wala dio (pehle app/dio_provider.dart tha jo token nahi bhejta)
import '../../../core/network/api_client.dart';

enum AttendanceStatus { idle, loading, success, error }

// ─── Today's attendance snapshot (from backend) ──────────────────────────────

class AttendanceToday {
  final int? attendanceId;
  final bool checkedIn;
  final DateTime? checkInTime;
  final String? checkInAddress;
  final String? checkInPhotoUrl;
  final bool checkedOut;
  final DateTime? checkOutTime;
  final String? checkOutAddress;
  final int? workDurationMinutes;

  const AttendanceToday({
    this.attendanceId,
    this.checkedIn = false,
    this.checkInTime,
    this.checkInAddress,
    this.checkInPhotoUrl,
    this.checkedOut = false,
    this.checkOutTime,
    this.checkOutAddress,
    this.workDurationMinutes,
  });

  const AttendanceToday.empty()
    : attendanceId = null,
      checkedIn = false,
      checkInTime = null,
      checkInAddress = null,
      checkInPhotoUrl = null,
      checkedOut = false,
      checkOutTime = null,
      checkOutAddress = null,
      workDurationMinutes = null;

  factory AttendanceToday.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? s) {
      if (s == null || s.isEmpty) return null;
      try {
        return DateTime.parse(s).toLocal();
      } catch (_) {
        return null;
      }
    }

    return AttendanceToday(
      attendanceId: json['attendance_id'],
      checkedIn: json['checked_in'] ?? false,
      checkInTime: parse(json['check_in_time']?.toString()),
      checkInAddress: json['check_in_address'],
      checkInPhotoUrl: json['check_in_photo_url'],
      checkedOut: json['checked_out'] ?? false,
      checkOutTime: parse(json['check_out_time']?.toString()),
      checkOutAddress: json['check_out_address'],
      workDurationMinutes: json['work_duration_minutes'],
    );
  }
}

// ─── State ───────────────────────────────────────────────────────────────────

class AttendanceState {
  final AttendanceStatus status; // tracks the latest check-in/out action
  final String? errorMessage;
  final bool loadingToday; // initial "am I checked in?" fetch
  final AttendanceToday today;

  const AttendanceState({
    this.status = AttendanceStatus.idle,
    this.errorMessage,
    this.loadingToday = false,
    this.today = const AttendanceToday.empty(),
  });

  // Convenience getters for the UI.
  bool get isCheckedIn => today.checkedIn;
  bool get isCheckedOut => today.checkedOut;
  bool get isShiftActive => today.checkedIn && !today.checkedOut;

  AttendanceState copyWith({
    AttendanceStatus? status,
    String? errorMessage,
    bool? loadingToday,
    AttendanceToday? today,
  }) {
    return AttendanceState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      loadingToday: loadingToday ?? this.loadingToday,
      today: today ?? this.today,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class AttendanceNotifier extends Notifier<AttendanceState> {
  @override
  AttendanceState build() => const AttendanceState();

  // Fetch today's status so the home screen survives app restarts.
  Future<void> loadToday() async {
    state = state.copyWith(loadingToday: true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/attendance/today');
      state = state.copyWith(
        loadingToday: false,
        today: AttendanceToday.fromJson(res.data as Map<String, dynamic>),
      );
    } catch (_) {
      // Silent fail on load — keep whatever we had, just stop the spinner.
      state = state.copyWith(loadingToday: false);
    }
  }

  Future<void> markAttendance({
    required double lat,
    required double lng,
    required String imagePath,
    double? accuracy,
  }) async {
    state = state.copyWith(status: AttendanceStatus.loading);
    try {
      final dio = ref.read(dioProvider);
      final formData = FormData.fromMap({
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        'photo': await MultipartFile.fromFile(imagePath, filename: 'checkin.jpg'),
      });

      final res = await dio.post('/attendance/check-in', data: formData);
      state = state.copyWith(
        status: AttendanceStatus.success,
        today: AttendanceToday.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      state = state.copyWith(
        status: AttendanceStatus.error,
        errorMessage: _friendlyError(e, fallback: 'Failed to check in.'),
      );
    } catch (_) {
      state = state.copyWith(
        status: AttendanceStatus.error,
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> checkOut({
    required double lat,
    required double lng,
    String? imagePath,
  }) async {
    state = state.copyWith(status: AttendanceStatus.loading);
    try {
      final dio = ref.read(dioProvider);
      final map = <String, dynamic>{'lat': lat, 'lng': lng};
      if (imagePath != null) {
        map['photo'] = await MultipartFile.fromFile(
          imagePath,
          filename: 'checkout.jpg',
        );
      }
      final res = await dio.post(
        '/attendance/check-out',
        data: FormData.fromMap(map),
      );
      state = state.copyWith(
        status: AttendanceStatus.success,
        today: AttendanceToday.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      state = state.copyWith(
        status: AttendanceStatus.error,
        errorMessage: _friendlyError(e, fallback: 'Failed to check out.'),
      );
    } catch (_) {
      state = state.copyWith(
        status: AttendanceStatus.error,
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  String _friendlyError(DioException e, {required String fallback}) {
    // Backend sends a clear "detail" message for 409/400/403 — surface it.
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (e.response?.statusCode == 401) {
      return 'Session expired. Please log in again.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot reach server. Check your internet.';
    }
    return fallback;
  }
}

final attendanceNotifierProvider =
    NotifierProvider<AttendanceNotifier, AttendanceState>(() {
      return AttendanceNotifier();
    });
