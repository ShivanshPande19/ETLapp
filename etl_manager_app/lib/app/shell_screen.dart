import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class ShellScreen extends StatelessWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    if (loc.startsWith('/sales')) return 1;
    if (loc.startsWith('/music')) return 2;
    if (loc.startsWith('/housekeeping')) return 3;
    if (loc.startsWith('/complaints')) return 4;
    if (loc.startsWith('/maintenance')) return 5;
    if (loc.startsWith('/settings')) return 6;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/sales');
        break;
      case 2:
        context.go('/music');
        break;
      case 3:
        context.go('/housekeeping');
        break;
      case 4:
        context.go('/complaints');
        break;
      case 5:
        context.go('/maintenance');
        break;
      case 6:
        context.go('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final selectedIndex = _selectedIndex(context);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    );

    const items = [
      NavItem(icon: Icons.grid_view_rounded, label: 'Home'),
      NavItem(icon: Icons.bar_chart_rounded, label: 'Sales'),
      NavItem(icon: Icons.music_note_rounded, label: 'Music'),
      NavItem(icon: Icons.cleaning_services_rounded, label: 'Tasks'),
      NavItem(icon: Icons.feedback_rounded, label: 'Issues'),
      NavItem(icon: Icons.handyman_rounded, label: 'Repairs'),
      NavItem(icon: Icons.settings_rounded, label: 'Settings'),
    ];

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
              onTap: (i) => _onTap(context, i),
            ),
          ),
        ],
      ),
    );
  }
}

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
            color: Colors.black.withOpacity(0.18),
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
            onTap: () => onTap(index),
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
                        : Colors.white.withOpacity(0.45),
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

class NavItem {
  final IconData icon;
  final String label;
  const NavItem({required this.icon, required this.label});
}
