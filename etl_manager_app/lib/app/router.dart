import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/domain/auth_notifier.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/sales/presentation/sales_screen.dart';
import '../features/music/presentation/music_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/staff/presentation/staff_shell_screen.dart';
import '../features/staff/presentation/staff_home_screen.dart';
import '../features/staff/presentation/staff_checklist_screen.dart';
import '../features/staff/presentation/staff_report_screen.dart';
import 'shell_screen.dart';

// ── Custom fade + slide transition ────────────────────────────────────────────
CustomTransitionPage<T> _buildPage<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
  bool fade = false,
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
      // Slide up + fade for main navigation
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

      final fade_ = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        ),
      );

      return FadeTransition(
        opacity: fade_,
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

      if (!isLoggedIn && !onLogin) return '/login';
      if (isLoggedIn && onLogin) {
        return authState.isStaff ? '/staff/home' : '/home';
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

      // ── Manager Shell ─────────────────────────────────────────────────────
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
            path: '/settings',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const SettingsScreen(),
            ),
          ),
        ],
      ),

      // ── Staff Shell ───────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => StaffShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/staff/home',
            pageBuilder: (context, state) => _buildPage(
              context: context,
              state: state,
              child: const StaffHomeScreen(),
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
