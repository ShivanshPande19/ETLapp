// lib/features/staff/presentation/outlet_staff_home_screen.dart

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
                        await Future.delayed(const Duration(milliseconds: 500));
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
                                              lat: result['latitude'] ?? 0.0,
                                              lng: result['longitude'] ?? 0.0,
                                              imagePath: result['image_path'],
                                            );
                                      }
                                    },
                                  ),
                          ),

                          const SizedBox(height: 40),

                          // 2. CUSTOMER FEEDBACK OVERVIEW (🔥 REAL DATA INJECTED HERE)
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
                              Text(
                                'Real-time Sync',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 🟢 Riverpod Consumer for Feedbacks
                          Consumer(
                            builder: (context, ref, child) {
                              final feedbackState = ref.watch(
                                feedbackNotifierProvider,
                              );

                              return feedbackState.when(
                                loading: () => Container(
                                  height: 130,
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
                                      'Data sync failed: $err',
                                      style: GoogleFonts.inter(
                                        color: Colors.red,
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

                                  // Extract Real Data
                                  final latestFeedback =
                                      data.allFeedbacks.first;

                                  // Calculate Average Rating
                                  double totalRating = 0;
                                  int ratingCount = 0;
                                  for (var f in data.allFeedbacks) {
                                    if (f.outletRating != null) {
                                      totalRating += f.outletRating!;
                                      ratingCount++;
                                    }
                                  }
                                  final avgRating = ratingCount > 0
                                      ? (totalRating / ratingCount)
                                            .toStringAsFixed(1)
                                      : 'N/A';

                                  final latestComment =
                                      (latestFeedback.outletComments != null &&
                                          latestFeedback
                                              .outletComments!
                                              .isNotEmpty)
                                      ? '"${latestFeedback.outletComments}"'
                                      : '"Rated ${latestFeedback.outletRating} Stars"';

                                  return Row(
                                    children: [
                                      // Average Rating Box
                                      Expanded(
                                        flex: 4,
                                        child: Container(
                                          height: 130,
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: _black,
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: _black.withOpacity(0.15),
                                                blurRadius: 16,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Icon(
                                                Icons.star_rounded,
                                                color: _warn,
                                                size: 28,
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    avgRating,
                                                    style: GoogleFonts.antonSc(
                                                      fontSize: 38,
                                                      color: _white,
                                                      height: 1.0,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Avg Rating',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11,
                                                      color: Colors.white70,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),

                                      // Latest Review Box
                                      Expanded(
                                        flex: 6,
                                        child: GestureDetector(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            context.go(
                                              '/feedbacks',
                                            ); // Goes to detailed feedbacks screen
                                          },
                                          child: Container(
                                            height: 130,
                                            padding: const EdgeInsets.all(20),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFAFAFA),
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              border: Border.all(
                                                color: Colors.grey.shade200,
                                                width: 2,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            6,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: _ok.withOpacity(
                                                          0.15,
                                                        ),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(
                                                        Icons.thumb_up_rounded,
                                                        color: _ok,
                                                        size: 14,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      'Recent Review',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: _grey,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const Spacer(),
                                                Text(
                                                  latestComment,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: _black,
                                                    height: 1.4,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
