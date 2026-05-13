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

  const AuthState({
    this.status = AuthStatus.idle,
    this.errorMessage,
    this.managerName,
    this.managerEmail,
    this.role,
    this.zone,
    this.staffName,
    this.courtId = 1,
  });

  bool get isManager => role == 'manager';
  bool get isStaff => role == 'staff';

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    String? managerName,
    String? managerEmail,
    String? role,
    String? zone,
    String? staffName,
    int? courtId,
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

      state = state.copyWith(
        status: AuthStatus.success,
        managerName: data['manager_name'] as String?,
        managerEmail: data['manager_email'] as String?,
        role: data['role'] as String?,
        zone: zoneRaw?.toString(),
        staffName: data['manager_name'] as String?,
        courtId: courtId,
      );
    } on DioException catch (e) {
      // Network / HTTP errors
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
        message = 'Error ${e.response?.statusCode}: ${e.response?.data ?? e.message}';
      }
      print('[AUTH ERROR] DioException: $message | type: ${e.type} | msg: ${e.message}');
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: message,
      );
    } catch (e) {
      print('[AUTH ERROR] Unknown: $e');
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
