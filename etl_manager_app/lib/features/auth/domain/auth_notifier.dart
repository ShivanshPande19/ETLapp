// lib/features/auth/domain/auth_notifier.dart

import 'dart:async';

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

  // ── ROLE SPLIT ───────────────────────────────────────────────────────────
  // The single old `etl_manager` is split into full-access MANAGEMENT roles
  // (Azimuth Management, Crownest Ops Head, Crownest Head) + narrow MAINTENANCE
  // worker roles (Azimuth Maintenance, Crownest Maintenance Head). This mirrors
  // deps.MANAGEMENT_ROLES / MAINTENANCE_ROLES on the backend.

  bool get isAzimuthManagement => role == 'azimuth_management';
  bool get isCrownestOpsHead => role == 'crownest_ops_head';
  bool get isCrownestHead => role == 'crownest_head';
  bool get isAzimuthMaintenance => role == 'azimuth_maintenance';
  bool get isCrownestMaintenanceHead => role == 'crownest_maintenance_head';

  /// Full company-wide access (drives every ETL-manager-only screen). Legacy
  /// etl_manager/manager + the three new management roles all qualify — exactly
  /// like the backend's `is_management`.
  bool get isManagement =>
      role == 'etl_manager' ||
      role == 'manager' ||
      role == 'azimuth_management' ||
      role == 'crownest_ops_head' ||
      role == 'crownest_head';

  /// Only Crownest Ops Head may RAISE / route maintenance tickets.
  bool get isOpsHead => role == 'crownest_ops_head';

  /// Narrow maintenance worker (tickets-only home).
  bool get isMaintenanceWorker =>
      role == 'azimuth_maintenance' || role == 'crownest_maintenance_head';

  // NOTE: legacy accounts may still carry role == 'manager' / 'staff'. The
  // backend treats {etl_manager, manager} and {etl_staff, staff} as the same
  // ETL identities, so we MUST mirror that here — otherwise a legacy 'manager'
  // logs in fine but every ETL-only screen hides itself client-side.
  //
  // is_management now folds in the 3 new management roles, so every existing
  // `isEtlManager` check in the UI grants them the full app automatically.
  bool get isEtlManager => isManagement;
  bool get isOutletManager => role == 'outlet_manager';
  bool get isEtlStaff => role == 'etl_staff' || role == 'staff';
  bool get isOutletStaff => role == 'outlet_staff';

  // ✅ CORRECTION: isStaff sirf ETL/Housekeeping staff ke liye true hoga, outlet_staff ke liye nahi!
  bool get isManager => isManagement || role == 'outlet_manager';
  bool get isStaff => role == 'etl_staff' || role == 'staff';

  /// Where this identity should land after login / biometric unlock. The router
  /// still enforces per-role access, so this is just the first destination.
  String get landingRoute {
    if (isMaintenanceWorker) return '/maintenance-home';
    if (isStaff) return '/staff/home';
    return '/home';
  }

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
      // Give the user a clear idea of WHERE the problem is, so a network issue
      // (their connection / server unreachable) is never mistaken for a wrong
      // password — and so they don't blame the app for something outside it.
      final status = e.response?.statusCode;
      String message;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        // We reached out but the server was too slow to answer.
        message =
            'Network is slow — the server didn\'t respond in time. Please check '
            'your internet and try again.';
      } else if (e.type == DioExceptionType.connectionError ||
          e.response == null) {
        // No response at all = we never reached the server (offline, no signal,
        // blocked/unreachable host, server down). This is NOT a wrong password.
        message =
            'Can\'t reach the server. Please check your internet connection and '
            'try again.';
      } else if (status == 401) {
        // The server answered and rejected the credentials.
        message = 'Incorrect email or password. Please try again.';
      } else if (status != null && status >= 500) {
        // The server was reached but errored on its side — not the user's fault.
        message =
            'The server is having trouble right now. Please try again in a moment.';
      } else {
        // Any other 4xx — show the server's own message if it sent one.
        final data = e.response?.data;
        final detail = (data is Map && data['detail'] is String)
            ? data['detail'] as String
            : null;
        message = detail ?? 'Login failed. Please try again.';
      }
      state = state.copyWith(status: AuthStatus.error, errorMessage: message);
    } catch (_) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> logout() async {
    // Sign out INSTANTLY. Flip the auth state (and drop user-scoped caches)
    // right away so the router redirects to the login screen with zero wait.
    //
    // Previously we AWAITED an authenticated push-unregister network call FIRST
    // and only flipped the state afterwards — so on a slow connection the user
    // sat on the current/home screen for several seconds before the logout
    // actually took effect. That teardown doesn't need to block the user.
    _clearUserScopedProviders();
    state = const AuthState(status: AuthStatus.idle);

    // Finish the teardown in the BACKGROUND (best-effort). Ordering still
    // matters: the push unregister is an authenticated call, so it must run
    // BEFORE authRepository.logout() wipes the JWT it needs (see below).
    unawaited(_finishLogoutCleanup());
  }

  /// Background, best-effort logout teardown. Unregisters this device's push
  /// token (so the next person on a SHARED DEVICE never inherits this user's
  /// notifications) and THEN wipes the stored credentials. The unregister is
  /// capped so a slow/offline network can't keep the stored token alive for
  /// long, and the local token wipe always runs regardless. Never throws.
  Future<void> _finishLogoutCleanup() async {
    try {
      await _unregisterPushDevice().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timed out or failed — fall through and wipe the token anyway.
    }
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {
      // Local token wipe should never realistically fail; ignore if it does.
    }
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
    // NOTE: the maintenance ticket list is refreshed on account switch by
    // MaintenanceNotifier itself (it listens to the auth identity). Invalidating
    // it from here would create a provider dependency cycle (maintenance → dio
    // → auth), so it must NOT be invalidated here.
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
