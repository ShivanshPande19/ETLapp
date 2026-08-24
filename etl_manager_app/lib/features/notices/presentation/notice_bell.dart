// lib/features/notices/presentation/notice_bell.dart
//
// Reusable notifications bell for the manager home headers. Shows the live
// unread count (from unreadCountProvider) and opens the notices inbox. Managers
// previously could ONLY reach notices buried inside Settings — this surfaces it
// as a top-level entry, matching the staff home bell.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/notices_notifier.dart';
import 'notices_screen.dart';

class NoticeBell extends ConsumerWidget {
  final Color color; // icon + ring tint (over a dark header)
  final double size;
  const NoticeBell({super.key, this.color = Colors.white, this.size = 38});

  static const _red = Color(0xFFD02128);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).maybeWhen(
          data: (v) => v,
          orElse: () => 0,
        );

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const NoticesScreen()))
            .then((_) => ref.invalidate(unreadCountProvider));
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.18), width: 1.2),
            ),
            child: Icon(Icons.notifications_none_rounded,
                size: size * 0.5, color: color),
          ),
          if (unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF080808), width: 1.5),
                ),
                child: Center(
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
