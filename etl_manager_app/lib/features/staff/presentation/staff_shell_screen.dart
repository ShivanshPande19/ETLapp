import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/liquid_nav_bar.dart';

class StaffShellScreen extends StatelessWidget {
  final Widget child;
  const StaffShellScreen({super.key, required this.child});

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/staff/checklist')) return 1;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/staff/home');
        break;
      case 1:
        context.go('/staff/checklist');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final selectedIndex = _selectedIndex(context);

    const items = [
      LiquidNavItem(icon: Icons.home_rounded, label: 'Home'),
      LiquidNavItem(icon: Icons.checklist_rounded, label: 'Checklist'),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          child,
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPadding + 14,
            child: Center(
              child: LiquidNavBar(
                items: items,
                selectedIndex: selectedIndex,
                onTap: (i) => _onTap(context, i),
                accent: const Color(0xFFFF4D4D),
                stretch: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
