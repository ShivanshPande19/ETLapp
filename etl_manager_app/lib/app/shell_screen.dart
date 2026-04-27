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
    if (loc.startsWith('/settings')) return 4;
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
      _NavItem(icon: Icons.grid_view_rounded, label: 'Home'),
      _NavItem(icon: Icons.bar_chart_rounded, label: 'Sales'),
      _NavItem(icon: Icons.music_note_rounded, label: 'Music'),
      _NavItem(icon: Icons.cleaning_services_rounded, label: 'Housekeeping'),
      _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Stack(
        children: [
          child,
          Positioned(
            left: 20,
            right: 20,
            bottom: bottomPadding + 16,
            child: _NavBar(
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

// ── Nav Bar ───────────────────────────────────────────────────────────────────

class _NavBar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final void Function(int) onTap;

  const _NavBar({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
                horizontal: isSelected ? 14 : 12,
                vertical: 6,
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
                    size: 18,
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
                              const SizedBox(width: 6),
                              Text(
                                items[index].label,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
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

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
