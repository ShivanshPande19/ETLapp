// lib/app/shell_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/domain/auth_notifier.dart';
import '../core/widgets/liquid_nav_bar.dart';
import '../core/ui/nav_visibility.dart';

class NavItem {
  final IconData icon;
  final String label;
  final String route;
  const NavItem({required this.icon, required this.label, required this.route});
}

class ShellScreen extends ConsumerWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  List<NavItem> _getNavItems(AuthState authState) {
    if (authState.isEtlManager) {
      return const [
        NavItem(icon: Icons.grid_view_rounded, label: 'Home', route: '/home'),
        NavItem(icon: Icons.bar_chart_rounded, label: 'Sales', route: '/sales'),
        NavItem(
          icon: Icons.cleaning_services_rounded,
          label: 'Tasks',
          route: '/housekeeping',
        ),
        NavItem(
          icon: Icons.star_rounded,
          label: 'Feedbacks',
          route: '/feedbacks',
        ),
        NavItem(
          icon: Icons.handyman_rounded,
          label: 'Repairs',
          route: '/maintenance',
        ),
      ];
    } else if (authState.isOutletManager) {
      return const [
        NavItem(
          icon: Icons.grid_view_rounded,
          label: 'Home',
          route: '/outlet-home',
        ),
        NavItem(
          icon: Icons.bar_chart_rounded,
          label: 'Sales',
          route: '/outlet-sales',
        ),
        NavItem(
          icon: Icons.star_rounded,
          label: 'Feedbacks',
          route: '/feedbacks',
        ),
        NavItem(
          icon: Icons.handyman_rounded,
          label: 'Repairs',
          route: '/maintenance',
        ),
      ];
    } else if (authState.isOutletStaff) {
      return const [
        NavItem(
          icon: Icons.grid_view_rounded,
          label: 'Home',
          route: '/outlet-staff-home',
        ),
        NavItem(
          icon: Icons.handyman_rounded,
          label: 'Repairs',
          route: '/maintenance',
        ),
        NavItem(
          icon: Icons.star_rounded,
          label: 'Feedbacks',
          route: '/feedbacks',
        ),
      ];
    }

    // Default fallback
    return const [
      NavItem(
        icon: Icons.feedback_rounded,
        label: 'Issues',
        route: '/complaints',
      ),
    ];
  }

  int _selectedIndex(BuildContext context, List<NavItem> items) {
    final loc = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < items.length; i++) {
      if (loc.startsWith(items[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final authState = ref.watch(authNotifierProvider);
    final items = _getNavItems(authState);
    final selectedIndex = _selectedIndex(context, items);
    // Hidden while a screen shows a bottom sheet (e.g. the outlet switcher), so
    // the floating bar never covers the sheet's content.
    final navVisible = ref.watch(navBarVisibleProvider);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Stack(
        children: [
          child,
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPadding + 12,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              // Slide fully off-screen (2x its own height) when hidden.
              offset: navVisible ? Offset.zero : const Offset(0, 2),
              child: IgnorePointer(
                ignoring: !navVisible,
                child: LiquidNavBar(
                  items: items
                      .map((e) => LiquidNavItem(icon: e.icon, label: e.label))
                      .toList(),
                  selectedIndex: selectedIndex,
                  onTap: (i) => context.go(items[i].route),
                  accent: const Color(0xFFFF4444),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
