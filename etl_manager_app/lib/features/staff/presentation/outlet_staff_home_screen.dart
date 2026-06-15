// lib/features/staff/presentation/outlet_staff_home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../auth/domain/auth_notifier.dart';
import '../domain/attendance_notifier.dart';
// ✅ IMPORT FOR REAL DATABASE FEEDBACKS
import '../../feedbacks/domain/feedback_notifier.dart';

// ─── Premium Palette ─────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _blue = Color(0xFF60A5FA);
const _warn = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);

class OutletStaffHomeScreen extends ConsumerStatefulWidget {
  const OutletStaffHomeScreen({super.key});

  @override
  ConsumerState<OutletStaffHomeScreen> createState() =>
      _OutletStaffHomeScreenState();
}

class _OutletStaffHomeScreenState extends ConsumerState<OutletStaffHomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // Local state for UI immediate update
  bool _isCheckedIn = false;
  String _checkInTime = "09:30 AM";
  String _address = "Checking location...";

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final firstName = (authState.staffName ?? authState.managerName ?? 'Staff')
        .split(' ')
        .first;

    // Listen to Attendance API responses
    ref.listen<AttendanceState>(attendanceNotifierProvider, (previous, next) {
      if (next.status == AttendanceStatus.success) {
        setState(() {
          _isCheckedIn = true;
          _address = next.address ?? "Location saved";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance Synced with Server!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (next.status == AttendanceStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage ?? 'Failed to check-in'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    final attendanceState = ref.watch(attendanceNotifierProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── DARK HEADER ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WELCOME BACK',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _grey,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          firstName.toUpperCase(),
                          style: GoogleFonts.antonSc(
                            fontSize: 42,
                            color: _white,
                            height: 1.0,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.storefront_rounded,
                              size: 14,
                              color: _blue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Your Outlet',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _white.withOpacity(0.8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    _ProfileButton(firstName: firstName),
                  ],
                ),
              ),

              // ─── SCROLLABLE WHITE CANVAS ──────────────────
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(40),
                  ),
                  child: Container(
                    width: double.infinity,
                    color: _white,
                    child: RefreshIndicator(
                      color: _black,
                      backgroundColor: _white,
                      strokeWidth: 2,
                      onRefresh: () async {
                        HapticFeedback.mediumImpact();
                        // 🟢 FIX: Trigger real feedback sync when user pulls to refresh
                        await ref
                            .read(feedbackNotifierProvider.notifier)
                            .fetchFeedbacks(isRefresh: true);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          24,
                          40,
                          24,
                          MediaQuery.of(context).padding.bottom + 120,
                        ),
                        children: [
                          // 1. ATTENDANCE HUB
                          Text(
                            'Today\'s Shift',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: _black,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 16),

                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: _isCheckedIn
                                ? _ActiveShiftCard(
                                    checkInTime: _checkInTime,
                                    address: _address,
                                    onViewTap: () =>
                                        _showAttendanceDetails(context),
                                  )
                                : attendanceState.status ==
                                      AttendanceStatus.loading
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24.0),
                                      child: CircularProgressIndicator(
                                        color: _black,
                                      ),
                                    ),
                                  )
                                : _MarkAttendanceCard(
                                    onTap: () async {
                                      HapticFeedback.selectionClick();
                                      final result = await context.push(
                                        '/staff/mark-attendance',
                                      );

                                      if (!mounted) return;

                                      if (result != null && result is Map) {
                                        final email = authState.managerEmail;

                                        if (email == null) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Error: User Email not found.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        // 🟢 FIX: don't accept invalid (0,0) location
                                        final lat =
                                            (result['latitude'] as num?)
                                                ?.toDouble() ??
                                            0.0;
                                        final lng =
                                            (result['longitude'] as num?)
                                                ?.toDouble() ??
                                            0.0;
                                        if (lat == 0.0 && lng == 0.0) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Could not capture location. Try again.',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                          return;
                                        }

                                        setState(() {
                                          _checkInTime = TimeOfDay.now().format(
                                            context,
                                          );
                                        });

                                        await ref
                                            .read(
                                              attendanceNotifierProvider
                                                  .notifier,
                                            )
                                            .markAttendance(
                                              email: email,
                                              lat: lat,
                                              lng: lng,
                                              imagePath: result['image_path'],
                                            );
                                      }
                                    },
                                  ),
                          ),

                          const SizedBox(height: 40),

                          // 2. CUSTOMER VOICE (🔥 REDESIGNED — real outlet data)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Customer Voice',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: _black,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: _ok,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Live',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 🟢 Riverpod Consumer for Feedbacks (this outlet only)
                          Consumer(
                            builder: (context, ref, child) {
                              final feedbackState = ref.watch(
                                feedbackNotifierProvider,
                              );

                              return feedbackState.when(
                                loading: () => Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: _black,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                error: (err, stack) => Container(
                                  height: 130,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Center(
                                    child: Text(
                                      // 🟢 FIX: friendly message, no raw error
                                      'Could not load reviews. Pull to refresh.',
                                      style: GoogleFonts.inter(
                                        color: _danger,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                data: (data) {
                                  if (data.allFeedbacks.isEmpty) {
                                    return Container(
                                      height: 130,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFAFAFA),
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                          width: 2,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'No reviews yet',
                                          style: GoogleFonts.inter(
                                            color: _grey,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  // ✅ Redesigned panel (sirf is outlet ka data)
                                  return GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      context.go('/feedbacks');
                                    },
                                    child: _CustomerVoicePanel(
                                      feedbacks: data.allFeedbacks,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttendanceDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 24),
              const Icon(Icons.check_circle_rounded, color: _ok, size: 64),
              const SizedBox(height: 16),
              Text(
                'Attendance Verified',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You securely checked in at $_checkInTime.\nLocation: $_address',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: _grey,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkAttendanceCard extends StatefulWidget {
  final VoidCallback onTap;
  const _MarkAttendanceCard({required this.onTap});

  @override
  State<_MarkAttendanceCard> createState() => _MarkAttendanceCardState();
}

class _MarkAttendanceCardState extends State<_MarkAttendanceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _black,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: _black.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _blue.withOpacity(0.1 + (_pulseCtrl.value * 0.1)),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    color: _blue,
                    size: 48,
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'MARK ATTENDANCE',
              style: GoogleFonts.antonSc(
                fontSize: 28,
                color: _white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Secure check-in via live selfie & location',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white54,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.camera_alt_rounded, size: 16, color: _black),
                  const SizedBox(width: 8),
                  Text(
                    'Start Check-in',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _black,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveShiftCard extends StatelessWidget {
  final String checkInTime;
  final String address;
  final VoidCallback onViewTap;

  const _ActiveShiftCard({
    required this.checkInTime,
    required this.address,
    required this.onViewTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.grey.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _ok.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _ok,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'SHIFT ACTIVE',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _ok,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onViewTap,
                child: Text(
                  'View Details',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Icon(Icons.login_rounded, color: _black, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checked In At',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      checkInTime,
                      style: GoogleFonts.antonSc(
                        fontSize: 32,
                        color: _black,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 14, color: _grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  address,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _grey,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  final String firstName;
  const _ProfileButton({required this.firstName});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/settings');
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _white.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: _white.withOpacity(0.2), width: 1.5),
        ),
        child: Center(
          child: Text(
            firstName.isNotEmpty ? firstName[0].toUpperCase() : 'S',
            style: GoogleFonts.inter(
              fontSize: 18,
              color: _white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOMER VOICE — Redesigned Panel
// ═══════════════════════════════════════════════════════════════════════════

class _CustomerVoicePanel extends StatelessWidget {
  final List<FeedbackModel> feedbacks;
  const _CustomerVoicePanel({required this.feedbacks});

  @override
  Widget build(BuildContext context) {
    final rated = feedbacks.where((f) => f.outletRating != null).toList();

    final avg = rated.isEmpty
        ? 0.0
        : rated.map((f) => f.outletRating!).reduce((a, b) => a + b) /
              rated.length;

    // Star distribution: index 0 => 1★ ... index 4 => 5★
    final dist = List<int>.filled(5, 0);
    for (final f in rated) {
      final r = f.outletRating!;
      if (r >= 1 && r <= 5) dist[r - 1]++;
    }

    final withComments = feedbacks
        .where(
          (f) =>
              f.outletComments != null && f.outletComments!.trim().isNotEmpty,
        )
        .toList();

    final needsAttention = rated.where((f) => f.outletRating! <= 2).length;
    final happy = rated.where((f) => f.outletRating! >= 4).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Top: Mood ring + distribution bars ───
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _black,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _black.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _MoodRing(avg: avg),
              const SizedBox(width: 22),
              Expanded(
                child: _StarDistribution(dist: dist, total: rated.length),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ─── Smart summary line ───
        _SummaryLine(happy: happy, needsAttention: needsAttention),

        // ─── Auto-rotating reviews ───
        if (withComments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RotatingReviews(reviews: withComments),
        ],
      ],
    );
  }
}

// ─── Animated Mood Ring ──────────────────────────────────────────────────────

class _MoodRing extends StatelessWidget {
  final double avg;
  const _MoodRing({required this.avg});

  Color get _color {
    if (avg >= 4.0) return _ok;
    if (avg >= 3.0) return _warn;
    if (avg > 0) return _danger;
    return _grey;
  }

  String get _emoji {
    if (avg >= 4.5) return '😍';
    if (avg >= 3.5) return '🙂';
    if (avg >= 2.5) return '😐';
    if (avg > 0) return '😞';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: avg / 5.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 7,
                  backgroundColor: _white.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(_color),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_emoji, style: const TextStyle(fontSize: 20)),
                  Text(
                    avg > 0 ? avg.toStringAsFixed(1) : '—',
                    style: GoogleFonts.antonSc(
                      fontSize: 24,
                      color: _white,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'avg',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Star Distribution Bars ──────────────────────────────────────────────────

class _StarDistribution extends StatelessWidget {
  final List<int> dist; // index 0 => 1★ ... index 4 => 5★
  final int total;
  const _StarDistribution({required this.dist, required this.total});

  Color _barColor(int star) {
    if (star >= 4) return _ok;
    if (star == 3) return _warn;
    return _danger;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final star = 5 - i; // top row = 5★
        final count = dist[star - 1];
        final frac = total > 0 ? count / total : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(
            children: [
              Text(
                '$star',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Colors.white60,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.star_rounded, size: 9, color: Colors.white38),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: frac),
                    duration: Duration(milliseconds: 700 + (i * 80)),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: _white.withOpacity(0.07),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _barColor(star),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 18,
                child: Text(
                  '$count',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.white60,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ─── Smart Summary Line ──────────────────────────────────────────────────────

class _SummaryLine extends StatelessWidget {
  final int happy;
  final int needsAttention;
  const _SummaryLine({required this.happy, required this.needsAttention});

  @override
  Widget build(BuildContext context) {
    final bool alert = needsAttention > 0;
    final Color c = alert ? _danger : _ok;
    final String text = alert
        ? '$needsAttention review${needsAttention > 1 ? 's' : ''} need attention'
        : happy > 0
        ? '$happy happy customer${happy > 1 ? 's' : ''} 🎉'
        : 'Waiting for more reviews';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(
            alert ? Icons.warning_amber_rounded : Icons.celebration_rounded,
            size: 16,
            color: c,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Auto-rotating Reviews ───────────────────────────────────────────────────

class _RotatingReviews extends StatefulWidget {
  final List<FeedbackModel> reviews;
  const _RotatingReviews({required this.reviews});

  @override
  State<_RotatingReviews> createState() => _RotatingReviewsState();
}

class _RotatingReviewsState extends State<_RotatingReviews> {
  final PageController _ctrl = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.reviews.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted || !_ctrl.hasClients) return;
        _index = (_index + 1) % widget.reviews.length;
        _ctrl.animateToPage(
          _index,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Color _sentiment(int? r) {
    if (r == null) return _grey;
    if (r >= 4) return _ok;
    if (r == 3) return _warn;
    return _danger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _ctrl,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: widget.reviews.length,
              itemBuilder: (context, i) {
                final f = widget.reviews[i];
                final c = _sentiment(f.outletRating);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 3,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.star_rounded, size: 13, color: c),
                                const SizedBox(width: 3),
                                Text(
                                  '${f.outletRating ?? '-'}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: c,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    f.customerName,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _grey,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: Text(
                                '"${f.outletComments}"',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _black,
                                  height: 1.35,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Dots indicator (max 6 shown)
          if (widget.reviews.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.reviews.length > 6 ? 6 : widget.reviews.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: _index % 6 == i ? 14 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _index % 6 == i ? _black : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
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
