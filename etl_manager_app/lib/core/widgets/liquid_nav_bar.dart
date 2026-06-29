// lib/core/widgets/liquid_nav_bar.dart
//
// Premium "liquid glass" bottom navigation bar — built natively (no extra
// package) so it stays fully under our control and can't break the build.
//
// Look & feel:
//  - Frosted glass: real backdrop blur + translucent dark tint + a top sheen
//    and hairline rim-light (the three ingredients of iOS-26 "liquid glass").
//  - Soft drop shadow + a subtle accent-coloured glow under the bar.
//  - Active item morphs into a glossy white pill (icon + label) with an
//    accent under-glow; it pops in with a quick elastic spring.
//  - Inactive icons are muted; everything animates smoothly. Haptics on tap.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class LiquidNavItem {
  final IconData icon;
  final String label;
  const LiquidNavItem({required this.icon, required this.label});
}

class LiquidNavBar extends StatelessWidget {
  final List<LiquidNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// Accent colour used for the glow under the bar and the active pill.
  final Color accent;

  /// Bar height (the pill radius is derived from it).
  final double height;

  /// When true (default) the bar fills the available width and spreads its
  /// items (caller bounds the width, e.g. via Positioned left/right). When
  /// false the bar hugs its content — center it yourself.
  final bool stretch;

  const LiquidNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    this.accent = const Color(0xFFFF4D4D),
    this.height = 66,
    this.stretch = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = height / 2;

    final tiles = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (!stretch && i > 0) tiles.add(const SizedBox(width: 6));
      tiles.add(
        _LiquidNavTile(
          item: items[i],
          selected: i == selectedIndex,
          accent: accent,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap(i);
          },
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            // Dark frosted glass with a faintly lighter top (sheen).
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xE61E1E26), // ~0.90 — subtle light top
                Color(0xF20A0A0E), // ~0.95 — deep bottom
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.14),
              width: 1,
            ),
            boxShadow: [
              // Depth shadow.
              BoxShadow(
                color: Colors.black.withOpacity(0.40),
                blurRadius: 30,
                spreadRadius: -6,
                offset: const Offset(0, 14),
              ),
              // Soft accent glow.
              BoxShadow(
                color: accent.withOpacity(0.20),
                blurRadius: 26,
                spreadRadius: -10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: stretch
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
            children: tiles,
          ),
        ),
      ),
    );
  }
}

class _LiquidNavTile extends StatelessWidget {
  final LiquidNavItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _LiquidNavTile({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
        horizontal: selected ? 15 : 12,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFFFF), Color(0xFFE9E9EF)],
              )
            : null,
        borderRadius: BorderRadius.circular(999),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.20),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: accent.withOpacity(0.45),
                  blurRadius: 18,
                  spreadRadius: -6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutBack,
            scale: selected ? 1.0 : 0.96,
            child: Icon(
              item.icon,
              size: 20,
              color: selected
                  ? const Color(0xFF0A0A0A)
                  : Colors.white.withOpacity(0.52),
            ),
          ),
          // Label reveals only on the active item (keeps the bar compact).
          AnimatedSize(
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
            child: selected
                ? Padding(
                    padding: const EdgeInsets.only(left: 7),
                    child: Text(
                      item.label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0A0A0A),
                        letterSpacing: -0.1,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );

    // Quick elastic "pop" each time an item becomes active. Swapping between
    // the plain pill and this wrapper remounts the builder, so it re-fires
    // exactly on selection.
    final content = selected
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.82, end: 1.0),
            duration: const Duration(milliseconds: 440),
            curve: Curves.elasticOut,
            builder: (_, value, child) =>
                Transform.scale(scale: value, child: child),
            child: pill,
          )
        : pill;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
