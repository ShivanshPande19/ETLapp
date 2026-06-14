// lib/features/auth/domain/auth_notifier.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';

enum AuthStatus { idle, loading, success, error }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final String? managerName;
  final String? managerEmail;
  final String? role;
  final String? zone;
  final String? staffName;
  final int courtId;
  final int? outletId;

  const AuthState({
    this.status = AuthStatus.idle,
    this.errorMessage,
    this.managerName,
    this.managerEmail,
    this.role,
    this.zone,
    this.staffName,
    this.courtId = 1,
    this.outletId,
  });

  // ✅ Naye Roles ke helpers
  bool get isEtlManager => role == 'etl_manager';
  bool get isOutletManager => role == 'outlet_manager';
  bool get isEtlStaff => role == 'etl_staff';
  bool get isOutletStaff => role == 'outlet_staff';

  // ✅ CORRECTION: isStaff sirf ETL/Housekeeping staff ke liye true hoga, outlet_staff ke liye nahi!
  bool get isManager =>
      role == 'etl_manager' || role == 'outlet_manager' || role == 'manager';
  bool get isStaff => role == 'etl_staff' || role == 'staff';

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    String? managerName,
    String? managerEmail,
    String? role,
    String? zone,
    String? staffName,
    int? courtId,
    int? outletId,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      managerName: managerName ?? this.managerName,
      managerEmail: managerEmail ?? this.managerEmail,
      role: role ?? this.role,
      zone: zone ?? this.zone,
      staffName: staffName ?? this.staffName,
      courtId: courtId ?? this.courtId,
      outletId: outletId ?? this.outletId,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final data = await ref
          .read(authRepositoryProvider)
          .login(email, password);

      final zoneRaw = data['zone'];
      final courtId = zoneRaw is int
          ? zoneRaw
          : int.tryParse(zoneRaw?.toString() ?? '') ?? 1;

      final outletRaw = data['outlet_id'];
      final parsedOutletId = outletRaw is int
          ? outletRaw
          : int.tryParse(outletRaw?.toString() ?? '');

      state = state.copyWith(
        status: AuthStatus.success,
        managerName: data['manager_name'] as String?,
        managerEmail: data['manager_email'] as String?,
        role: data['role'] as String?,
        zone: zoneRaw?.toString(),
        staffName: data['manager_name'] as String?,
        courtId: courtId,
        outletId: parsedOutletId,
      );
    } on DioException catch (e) {
      String message;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        message = 'Connection timeout — check internet';
      } else if (e.type == DioExceptionType.connectionError) {
        message = 'Cannot connect to server: ${e.message}';
      } else if (e.response?.statusCode == 401) {
        message = 'Invalid email or password';
      } else {
        message =
            'Error ${e.response?.statusCode}: ${e.response?.data ?? e.message}';
      }
      state = state.copyWith(status: AuthStatus.error, errorMessage: message);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Unexpected error: $e',
      );
    }
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState();
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
