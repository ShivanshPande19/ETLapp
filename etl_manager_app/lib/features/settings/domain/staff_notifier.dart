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

  /// ETL manager: set (or clear) a staff member's shift timings.
  /// Pass null for both to clear. Refreshes the court list on success.
  Future<bool> setShift({
    required int staffId,
    required int courtId,
    String? shiftStart,
    String? shiftEnd,
  }) async {
    try {
      await _dio.patch(
        '/staff/$staffId/shift',
        data: {'shift_start': shiftStart, 'shift_end': shiftEnd},
      );
      await fetchByCourtId(courtId);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ── Outlet staff (managed by the outlet manager for their own outlet) ───────

  Future<void> fetchByOutletId(int outletId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _dio.get('/staff/outlet/$outletId');
      final list = (res.data['staff'] as List)
          .map((e) => StaffModel.fromJson(e))
          .toList();
      state = state.copyWith(staffList: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load staff');
    }
  }

  Future<bool> addOutletStaff({
    required String name,
    required String email,
    required String password,
    required int outletId,
    String? phone,
    String? photoPath,
  }) async {
    try {
      final formData = FormData.fromMap({
        'name': name,
        'email': email,
        'password': password,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (photoPath != null && photoPath.isNotEmpty)
          'photo': await MultipartFile.fromFile(
            photoPath,
            filename: photoPath.split('/').last,
          ),
      });
      await _dio.post('/staff/outlet', data: formData);
      await fetchByOutletId(outletId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeOutletStaff(int staffId, int outletId) async {
    try {
      await _dio.patch('/staff/$staffId/deactivate');
      await fetchByOutletId(outletId);
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



// ── Outlet staff (for the outlet detail sheet) ────────────────────────────────
final outletStaffProvider = FutureProvider.autoDispose
    .family<List<StaffModel>, int>((ref, outletId) async {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/staff/outlet/$outletId');
      return (res.data['staff'] as List? ?? [])
          .map((e) => StaffModel.fromJson(e as Map<String, dynamic>))
          .toList();
    });
