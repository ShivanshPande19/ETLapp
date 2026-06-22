// lib/features/settings/domain/staff_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import 'staff_model.dart';

// ── State ─────────────────────────────────────────────────────────────────────
class StaffState {
  final List<StaffModel> staffList;
  final bool isLoading;
  final String? error;

  const StaffState({
    this.staffList = const [],
    this.isLoading = false,
    this.error,
  });

  StaffState copyWith({
    List<StaffModel>? staffList,
    bool? isLoading,
    String? error,
  }) => StaffState(
    staffList: staffList ?? this.staffList,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

// ── Notifier ── ✅ Riverpod v2 style ──────────────────────────────────────────
class StaffNotifier extends Notifier<StaffState> {
  @override
  StaffState build() => const StaffState();

  Dio get _dio => ref.read(dioProvider);

  Future<void> fetchByCourtId(int courtId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _dio.get('/staff/court/$courtId');
      final list = (res.data['staff'] as List)
          .map((e) => StaffModel.fromJson(e))
          .toList();
      state = state.copyWith(staffList: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load staff');
    }
  }

  Future<bool> addStaff({
    required String name,
    required String email,
    required String password,
    required int courtId,
    String? phone,
    String? photoPath,
  }) async {
    try {
      final formData = FormData.fromMap({
        'name': name,
        'email': email,
        'password': password,
        'court_id': courtId,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (photoPath != null && photoPath.isNotEmpty)
          'photo': await MultipartFile.fromFile(
            photoPath,
            filename: photoPath.split('/').last,
          ),
      });
      await _dio.post('/staff/', data: formData);
      await fetchByCourtId(courtId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeStaff(int staffId, int courtId) async {
    try {
      await _dio.patch('/staff/$staffId/deactivate');
      await fetchByCourtId(courtId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> reassignStaff(
    int staffId,
    int newCourtId,
    int currentCourtId,
  ) async {
    try {
      await _dio.patch('/staff/$staffId/court', data: {'court_id': newCourtId});
      await fetchByCourtId(currentCourtId);
      return true;
    } catch (e) {
      return false;
    }
  }
}

// ── Provider ✅ ───────────────────────────────────────────────────────────────
final staffNotifierProvider = NotifierProvider<StaffNotifier, StaffState>(
  StaffNotifier.new,
);
