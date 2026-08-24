// lib/features/auth/domain/auth_notifier.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../../../core/services/push_service.dart';
import '../../../core/utils/token_storage.dart';
import '../../notices/domain/notices_notifier.dart';

enum AuthStatus { unknown, idle, loading, success, error }

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
  // NOTE: legacy accounts may still carry role == 'manager' / 'staff'. The
  // backend treats {etl_manager, manager} and {etl_staff, staff} as the same
  // ETL identities, so we MUST mirror that here — otherwise a legacy 'manager'
  // logs in fine but every ETL-only screen hides itself client-side.
  bool get isEtlManager => role == 'etl_manager' || role == 'manager';
  bool get isOutletManager => role == 'outlet_manager';
  bool get isEtlStaff => role == 'etl_staff' || role == 'staff';
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
  // Guards against multiple concurrent 401s all triggering a logout at once.
  bool _sessionExpiryInFlight = false;

  @override
  AuthState build() {
    // Try to restore a previous session (auth persistence across app kills).
    Future.microtask(_restoreSession);
    return const AuthState(status: AuthStatus.unknown);
  }

  /// Rehydrate auth state from secure storage on cold start so the user stays
  /// logged in after fully closing the app. The Dio interceptor reads the same
  /// token for every request, so API calls keep working.
  ///
  /// A minimum delay is enforced so the branded splash is a deliberate moment
  /// (not a flash). If restore takes longer than the minimum, no extra wait.
  static const _minSplash = Duration(milliseconds: 1800);

  Future<void> _restoreSession() async {
    final startedAt = DateTime.now();
    AuthState next;
    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        next = const AuthState(status: AuthStatus.idle);
      } else {
        final role = await TokenStorage.getRole();
        final name = await TokenStorage.getManagerName();
        final email = await TokenStorage.getManagerEmail();
        final zone = await TokenStorage.getZone();
        final outletStr = await TokenStorage.getOutletId();

        final courtId = int.tryParse(zone ?? '') ?? 1;
        final outletId = int.tryParse(outletStr ?? '');

        next = AuthState(
          status: AuthStatus.success,
          managerName: name,
          managerEmail: email,
          role: role,
          zone: zone,
          staffName: name,
          courtId: courtId,
          outletId: outletId,
        );
      }
    } catch (_) {
      next = const AuthState(status: AuthStatus.idle);
    }

    // Hold the splash for at least _minSplash so the animation is seen.
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < _minSplash) {
      await Future.delayed(_minSplash - elapsed);
    }

    state = next;
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);
    // Drop any previous user's cached, user-scoped data so a freshly logged-in
    // account never sees the prior session's notices.
    _clearUserScopedProviders();
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
    // Unregister the push token FIRST — this is an authenticated call, and
    // authRepository.logout() wipes the JWT it needs.
    //
    // This is what stops the next person who signs in on a SHARED DEVICE from
    // receiving this user's notifications: the FCM token belongs to the app
    // installation, not the person.
    await _unregisterPushDevice();

    await ref.read(authRepositoryProvider).logout();
    _clearUserScopedProviders();
    state = const AuthState(status: AuthStatus.idle);
  }

  /// Best-effort push cleanup. Never throws and never blocks sign-out.
  Future<void> _unregisterPushDevice() async {
    try {
      await ref.read(pushServiceProvider).unregister();
    } catch (_) {
      // Offline, or Firebase not configured. The backend also transfers token
      // ownership on the next /devices/register, so a missed unregister here
      // cannot leak notifications to the next user.
    }
  }

  /// Called by the network layer when an authenticated request returns 401
  /// (the JWT has expired or is no longer valid on the server).
  ///
  /// Previously nothing handled 401s: the token would silently expire, screens
  /// that refetch (housekeeping / feedbacks / maintenance) would fail while
  /// already-cached ones (sales) kept showing stale data, and the user had to
  /// manually log out and back in. Now we clear the session and flip the auth
  /// state so the router redirects straight to the login screen.
  Future<void> sessionExpired() async {
    // De-dupe: many requests can 401 together; only act once, and never when
    // we're already logged out.
    if (_sessionExpiryInFlight) return;
    if (state.status != AuthStatus.success) return;
    _sessionExpiryInFlight = true;
    // Drop the local FCM token so a stale device can't keep receiving pushes.
    // The server-side unregister will 401 (the JWT is what expired), which is
    // fine — /devices/ is exempt from the 401 handler, and the backend re-binds
    // the token to whoever registers it next.
    await _unregisterPushDevice();
    try {
      await ref.read(authRepositoryProvider).logout(); // clears token storage
    } catch (_) {}
    _clearUserScopedProviders();
    state = const AuthState(
      status: AuthStatus.idle,
      errorMessage: 'Session expired — please sign in again.',
    );
    _sessionExpiryInFlight = false;
  }

  /// Reset providers that hold data scoped to the logged-in user, so switching
  /// accounts in the same app session never shows the previous user's data
  /// (these providers are keep-alive and aren't disposed on logout).
  void _clearUserScopedProviders() {
    ref.invalidate(noticesNotifierProvider);
    ref.invalidate(unreadCountProvider);
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
