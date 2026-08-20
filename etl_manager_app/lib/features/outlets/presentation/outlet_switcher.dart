// lib/features/outlets/presentation/outlet_switcher.dart
//
// Compact outlet switcher shown in the header of outlet-manager screens.
//
// CRITICAL UX RULE: it renders NOTHING when the manager has 0 or 1 outlet, so
// single-outlet owners (the vast majority today) see zero change. It only
// appears for a genuine multi-outlet owner.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/outlet_providers.dart';
import '../data/outlets_repository.dart';

class OutletSwitcher extends ConsumerWidget {
  /// When true (dark headers), text is light. When false (light surfaces),
  /// text is dark. Defaults to dark-header styling used by outlet screens.
  final bool onDark;
  const OutletSwitcher({super.key, this.onDark = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMany = ref.watch(hasMultipleOutletsProvider);
    if (!hasMany) return const SizedBox.shrink(); // single-outlet → nothing

    final outlets = ref.watch(myOutletsProvider).value ?? const <MyOutlet>[];
    final selected = ref.watch(selectedOutletProvider);
    final fg = onDark ? Colors.white : const Color(0xFF0A0A0A);
    final subtle = onDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF2F2F0);
    final border = onDark ? Colors.white.withOpacity(0.10) : const Color(0xFFE2E2E0);

    return GestureDetector(
      onTap: () => _openPicker(context, ref, outlets, selected?.outletId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: subtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, size: 15, color: fg),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                selected?.vendorName ?? 'Select outlet',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
          ],
        ),
      ),
    );
  }

  void _openPicker(
    BuildContext context,
    WidgetRef ref,
    List<MyOutlet> outlets,
    int? selectedId,
  ) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  'Switch outlet',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              ...outlets.map((o) {
                final isSel = o.outletId == selectedId;
                return ListTile(
                  onTap: () {
                    ref.read(selectedOutletIdProvider.notifier).select(o.outletId);
                    Navigator.of(ctx).pop();
                  },
                  leading: Icon(
                    isSel ? Icons.check_circle_rounded : Icons.storefront_outlined,
                    color: isSel ? const Color(0xFFDEFF9A) : Colors.white54,
                    size: 22,
                  ),
                  title: Text(
                    o.vendorName,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    o.courtName + (o.isOwner ? '  ·  Owner' : '  ·  Manager'),
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
