// lib/app/shell_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/auth/domain/auth_notifier.dart';

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
          icon: Icons.feedback_rounded,
          label: 'Issues',
          route: '/complaints',
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
          icon: Icons.feedback_rounded,
          label: 'Issues',
          route: '/complaints',
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
      // ✅ CHANGED: Issues (complaints) hataya, Repairs (maintenance) add kiya
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
            child: NavBar(
              items: items,
              selectedIndex: selectedIndex,
              onTap: (i) => context.go(items[i].route),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── NavBar widget ───
class NavBar extends StatelessWidget {
  final List<NavItem> items;
  final int selectedIndex;
  final void Function(int) onTap;

  const NavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isSelected = selectedIndex == index;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(index);
            },
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 10.0 : 8.0,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    items[index].icon,
                    size: 17,
                    color: isSelected
                        ? const Color(0xFF0A0A0A)
                        : Colors.white.withValues(alpha: 0.45),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: isSelected
                        ? Row(
                            children: [
                              const SizedBox(width: 5),
                              Text(
                                items[index].label,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0A0A0A),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
