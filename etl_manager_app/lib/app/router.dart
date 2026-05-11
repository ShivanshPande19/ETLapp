// lib/app/router.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/domain/auth_notifier.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/sales/presentation/sales_screen.dart';
import '../features/music/presentation/music_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/housekeeping/presentation/manager_housekeeping_screen.dart';
import '../features/complaints/presentation/complaints_screen.dart';
import '../features/maintenance/presentation/maintenance_screen.dart';
import '../features/courts/presentation/court_detail_screen.dart';
import '../features/courts/data/courts_repository.dart';
import '../features/staff/presentation/staff_shell_screen.dart';
import '../features/staff/presentation/staff_home_screen.dart';
import '../features/staff/presentation/staff_checklist_screen.dart';
import '../features/staff/presentation/staff_report_screen.dart';
import 'shell_screen.dart';
import 'biometric_gate.dart'; // ✅ new import

// ─── Transition helper ────────────────────────────────────────────────────────
CustomTransitionPage<T> _buildPage<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
  bool fade = false,
  bool slideFromRight = false,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (fade) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: child,
        );
      }
      if (slideFromRight) {
        final slide =
            Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        final fadeTween = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
          ),
        );
        return FadeTransition(
          opacity: fadeTween,
          child: SlideTransition(position: slide, child: child),
        );
      }
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      final fadeTween = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        ),
      );
      return FadeTransition(
        opacity: fadeTween,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

// ─── Router ───────────────────────────────────────────────────────────────────
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/login',

    // ✅ Redirect — sync only, koi async nahi
    redirect: (context, state) {
      final isLoggedIn = authState.status == AuthStatus.success;
      final onLogin = state.matchedLocation == '/login';
      final onBioGate = state.matchedLocation == '/biometric-gate';

      // Logged out → login
      if (!isLoggedIn && !onLogin) return '/login';

      // Logged in + login page → biometric gate se guzaro
      if (isLoggedIn && onLogin) return '/biometric-gate';

      // Gate pe already hai → kuch mat karo
      if (onBioGate) return null;

      return null;
    },

    routes: [
      // ── Login ──────────────────────────────────────────────────────────────
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildPage(
          context: context,
          state: state,
          child: const LoginScreen(),
          fade: true,
        ),
      ),

      // ── Biometric Gate ─────────────────────────────────────────────────────
      // Login success ke baad yahan aata hai
      // Biometric off ho toh seedha /home ya /staff/home
      // Biometric on ho toh Face ID / fingerprint prompt
      GoRoute(
        path: '/biometric-gate',
        pageBuilder: (context, state) => _buildPage(
          context: context,
          state: state,
          child: const BiometricGate(),
          fade: true,
        ),
      ),

      // ── Settings — standalone, shell ke bahar ──────────────────────────────
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _buildPage(
          context: context,
          state: state,
          child: const SettingsScreen(),
          slideFromRight: true,
        ),
      ),

      // ── Manager Shell ──────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/sales',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const SalesScreen(),
            ),
          ),
          GoRoute(
            path: '/music',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const MusicScreen(),
            ),
          ),
          GoRoute(
            path: '/housekeeping',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const ManagerHousekeepingScreen(),
            ),
          ),
          GoRoute(
            path: '/complaints',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const ComplaintsScreen(),
            ),
          ),
          GoRoute(
            path: '/maintenance',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const MaintenanceScreen(),
            ),
          ),
          GoRoute(
            path: '/court/:id',
            pageBuilder: (context, state) {
              final court = state.extra as Court;
              return _buildPage(
                context: context,
                state: state,
                child: CourtDetailScreen(court: court),
                slideFromRight: true,
              );
            },
          ),
        ],
      ),

      // ── Staff Shell ────────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => StaffShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/staff/home',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: StaffHomeScreen(
                assignedCourt: authState.courtId,
                staffName:
                    authState.staffName ?? authState.managerName ?? 'Staff',
              ),
            ),
          ),
          GoRoute(
            path: '/staff/checklist',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const StaffChecklistScreen(),
            ),
          ),
          GoRoute(
            path: '/staff/report',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const StaffReportScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
