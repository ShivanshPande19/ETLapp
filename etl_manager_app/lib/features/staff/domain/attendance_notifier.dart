import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/dio_provider.dart';

enum AttendanceStatus { idle, loading, success, error }

class AttendanceState {
  final AttendanceStatus status;
  final String? address;
  final String? errorMessage;

  const AttendanceState({
    this.status = AttendanceStatus.idle,
    this.address,
    this.errorMessage,
  });

  AttendanceState copyWith({
    AttendanceStatus? status,
    String? address,
    String? errorMessage,
  }) {
    return AttendanceState(
      status: status ?? this.status,
      address: address ?? this.address,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AttendanceNotifier extends Notifier<AttendanceState> {
  @override
  AttendanceState build() => const AttendanceState();

  Future<void> markAttendance({
    required String email, // ✅ Id nahi, email le rahe hain
    required double lat,
    required double lng,
    required String imagePath,
  }) async {
    state = state.copyWith(status: AttendanceStatus.loading);

    try {
      final dio = ref.read(dioProvider);

      final formData = FormData.fromMap({
        'email': email,
        'lat': lat,
        'lng': lng,
        'photo': await MultipartFile.fromFile(
          imagePath,
          filename: 'selfie.jpg',
        ),
      });

      final response = await dio.post('/attendance/check-in', data: formData);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final address = response.data['address'];
        state = state.copyWith(
          status: AttendanceStatus.success,
          address: address,
        );
      } else {
        state = state.copyWith(
          status: AttendanceStatus.error,
          errorMessage: 'Failed to save attendance.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AttendanceStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

final attendanceNotifierProvider =
    NotifierProvider<AttendanceNotifier, AttendanceState>(() {
      return AttendanceNotifier();
    });
