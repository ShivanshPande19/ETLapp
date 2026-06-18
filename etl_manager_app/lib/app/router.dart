// lib/app/router.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/domain/auth_notifier.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/outlet_home_screen.dart';
import '../features/sales/presentation/sales_screen.dart';
import '../features/sales/presentation/outlet_sales_screen.dart';
import '../features/music/presentation/music_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/housekeeping/presentation/manager_housekeeping_screen.dart';
import '../features/complaints/presentation/complaints_screen.dart';
import '../features/maintenance/presentation/maintenance_screen.dart';

// ✅ BOTH FEEDBACK SCREENS IMPORTED
import '../features/feedbacks/presentation/outlet_feedback_screen.dart';
import '../features/feedbacks/presentation/etl_feedbacks_screen.dart';

import '../features/courts/presentation/court_detail_screen.dart';
import '../features/courts/data/courts_repository.dart';

import '../features/staff/presentation/staff_shell_screen.dart';
import '../features/staff/presentation/staff_home_screen.dart';
import '../features/staff/presentation/staff_checklist_screen.dart';

import '../features/staff/presentation/outlet_staff_home_screen.dart';
import '../features/staff/presentation/mark_attendance_screen.dart';

import 'shell_screen.dart';
import 'biometric_gate.dart';

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

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authState.status == AuthStatus.success;
      final onLogin = state.matchedLocation == '/login';
      final onBioGate = state.matchedLocation == '/biometric-gate';
      final loc = state.matchedLocation;

      if (!isLoggedIn && !onLogin) return '/login';
      if (isLoggedIn && onLogin) return '/biometric-gate';
      if (onBioGate) return null;

      if (isLoggedIn) {
        final role = authState.role;

        if (role == 'etl_staff') {
          if (!loc.startsWith('/staff')) return '/staff/home';
        } else if (role == 'outlet_staff') {
          if (loc == '/staff/mark-attendance') return null;

          if (loc == '/home' ||
              loc == '/outlet-home' ||
              loc == '/sales' ||
              loc == '/outlet-sales' ||
              loc == '/housekeeping' ||
              loc == '/music' ||
              loc.startsWith('/staff/') ||
              loc == '/') {
            return '/outlet-staff-home';
          }
        } else if (role == 'outlet_manager') {
          if (loc == '/home') return '/outlet-home';
          if (loc == '/sales') return '/outlet-sales';
          if (loc == '/housekeeping' ||
              loc == '/music' ||
              loc.startsWith('/staff') ||
              loc == '/outlet-staff-home') {
            return '/outlet-home';
          }
        } else if (role == 'etl_manager') {
          if (loc == '/outlet-home' || loc == '/outlet-staff-home')
            return '/home';
          if (loc == '/outlet-sales') return '/sales';
        }
      }
      return null;
    },

    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildPage(
          context: context,
          state: state,
          child: const LoginScreen(),
          fade: true,
        ),
      ),
      GoRoute(
        path: '/biometric-gate',
        pageBuilder: (context, state) => _buildPage(
          context: context,
          state: state,
          child: const BiometricGate(),
          fade: true,
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _buildPage(
          context: context,
          state: state,
          child: const SettingsScreen(),
          slideFromRight: true,
        ),
      ),
      GoRoute(
        path: '/staff/mark-attendance',
        pageBuilder: (context, state) => _buildPage(
          context: context,
          state: state,
          child: const MarkAttendanceScreen(),
          slideFromRight: true,
        ),
      ),

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
            path: '/outlet-home',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const OutletHomeScreen(),
            ),
          ),
          GoRoute(
            path: '/outlet-staff-home',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const OutletStaffHomeScreen(),
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
            path: '/outlet-sales',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const OutletSalesScreen(),
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

          // ✅ SMART ROUTE: Redirects to proper screen based on role
          GoRoute(
            path: '/feedbacks',
            pageBuilder: (context, state) {
              final isEtlManager =
                  authState.role == 'etl_manager' ||
                  authState.role == 'manager';
              return _buildPage(
                context: context,
                state: state,
                child: isEtlManager
                    ? const EtlFeedbacksScreen()
                    : const OutletFeedbacksScreen(),
              );
            },
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
        ],
      ),
    ],
  );
});
