// lib/features/staff/presentation/attendance_status_widgets.dart
//
// The two attendance-card states that only exist because the network can fail.
// Shared by every home screen that shows attendance, so they all say the same
// thing. `dark` matches the ETL staff home; the others are light.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shown in place of "Check In" when today's status couldn't be loaded.
///
/// Offering "Check In" here would be a guess, and a wrong guess is what made a
/// running shift look logged out. This says what actually happened and gives
/// the one action that helps.
class AttendanceStatusUnknownCard extends StatelessWidget {
  const AttendanceStatusUnknownCard({
    super.key,
    required this.onRetry,
    required this.retrying,
    this.dark = false,
  });

  final VoidCallback onRetry;
  final bool retrying;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : const Color(0xFF0A0A0A);
    final muted = dark ? Colors.white60 : const Color(0xFF666666);
    // The button inverts the card: white on the dark card, black on the light.
    final btnBg = dark ? Colors.white : const Color(0xFF0A0A0A);
    final btnFg = dark ? const Color(0xFF0A0A0A) : Colors.white;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0A0A0A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark ? Colors.white12 : const Color(0xFFE5E5E5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: muted, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Couldn't load your shift",
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Check your internet and try again. If you already started your '
            'shift, it is still running.',
            style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: muted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: retrying ? null : onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: btnBg,
                foregroundColor: btnFg,
                // While retrying the button is disabled. Left to the theme's
                // defaults it went black-on-black on the dark staff home and
                // seemed to vanish the moment it was tapped. Dim it instead,
                // so it visibly stays put and is visibly busy.
                disabledBackgroundColor: btnBg.withValues(alpha: 0.7),
                disabledForegroundColor: btnFg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: retrying
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: btnFg,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                retrying ? 'Checking…' : 'Retry',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-line note above a shift card that came from the phone, not the
/// server — so nobody mistakes it for a fresh answer.
class SavedShiftNote extends StatelessWidget {
  const SavedShiftNote({
    super.key,
    required this.onRefresh,
    required this.refreshing,
    this.dark = false,
  });

  final VoidCallback onRefresh;
  final bool refreshing;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final muted = dark ? Colors.white60 : const Color(0xFF666666);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: refreshing ? null : onRefresh,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, size: 15, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  refreshing
                      ? 'Offline — checking for updates…'
                      : 'Offline — showing your saved shift. Tap to refresh.',
                  style: GoogleFonts.inter(fontSize: 12, color: muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
