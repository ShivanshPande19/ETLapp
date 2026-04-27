// lib/app/shell_screen.dart
// UPDATED — added Complaints tab at index 4, Settings moved to index 5

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.child});
  final Widget child;
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  static const _routes = [
    '/home',
    '/sales',
    '/music',
    '/housekeeping',
    '/complaints', // ← NEW (index 4)
    '/settings', // was index 4, now index 5
  ];

  static const _items = [
    _NavItem(Icons.grid_view_rounded, 'Home'),
    _NavItem(Icons.bar_chart_rounded, 'Sales'),
    _NavItem(Icons.music_note_rounded, 'Music'),
    _NavItem(Icons.cleaning_services_rounded, 'Tasks'), // shortened label
    _NavItem(Icons.feedback_outlined, 'Issues'), // ← NEW
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  int get _selectedIndex {
    final loc = GoRouterState.of(context).uri.path;
    final idx = _routes.indexWhere((r) => loc.startsWith(r));
    return idx < 0 ? 0 : idx;
  }

  void _onTap(int index) {
    HapticFeedback.selectionClick();
    if (index != _selectedIndex) {
      context.go(_routes[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selectedIndex;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: widget.child,
      bottomNavigationBar: Container(
        color: const Color(0xFF080808),
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad + 8),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final active = sel == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item.icon,
                          size: 20,
                          color: active
                              ? Colors.white
                              : Colors.white.withOpacity(0.35),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: active
                              ? Colors.white
                              : Colors.white.withOpacity(0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
