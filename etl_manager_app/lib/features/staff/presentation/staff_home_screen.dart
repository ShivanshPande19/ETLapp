// lib/features/staff/presentation/staff_home_screen.dart
//
// Premium ETL staff home — hero header, attendance hub (check-in/out),
// housekeeping progress and a court-feedback card (court voice only).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../staff/domain/housekeeping_models.dart' as hk;
import '../../staff/data/housekeeping_repository.dart';
import '../domain/attendance_notifier.dart';
import '../../feedbacks/domain/court_feedback_notifier.dart';
import '../../feedbacks/presentation/staff_court_feedback_screen.dart';
import '../../settings/presentation/staff_settings_screen.dart';
import '../../notices/domain/notices_notifier.dart';
import '../../notices/presentation/notices_screen.dart';
import '../../attendance_calendar/presentation/staff_calendar_screen.dart';

// ✅ Real court name from DB
import '../../courts/domain/courts_notifier.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFE5A000);
const _danger = Color(0xFFFF4444);
const _blue = Color(0xFF60A5FA);
const _red = Color(0xFFD02128);

// ─── Providers ────────────────────────────────────────────────────────────────
final _staffHkProvider = FutureProvider.autoDispose
    .family<hk.FullStatusResponse?, String>((ref, date) async {
      return ref.read(housekeepingRepoProvider).getFullStatus(date: date);
    });

// ─── Screen ───────────────────────────────────────────────────────────────────
class StaffHomeScreen extends ConsumerStatefulWidget {
  final int assignedCourt;
  final String staffName;

  const StaffHomeScreen({
    super.key,
    required this.assignedCourt,
    required this.staffName,
  });

  @override
  ConsumerState<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends ConsumerState<StaffHomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _heroCtrl;
  late final AnimationController _cardsCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  final ScrollController _scrollCtrl = ScrollController();

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

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
    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _cardsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));

    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _heroCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _cardsCtrl.forward();
    });

    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    // ✅ Load today's attendance so the hub survives restarts.
    Future.microtask(
      () => ref.read(attendanceNotifierProvider.notifier).loadToday(),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _heroCtrl.dispose();
    _cardsCtrl.dispose();
    _scrollCtrl.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  String get _dateStr => _now.toIso8601String().substring(0, 10);

  hk.Shift get _currentShift {
    final h = _now.hour;
    if (h >= 6 && h < 12) return hk.Shift.morning;
    if (h >= 12 && h < 16) return hk.Shift.day;
    return hk.Shift.night;
  }

  Future<void> _refreshAll() async {
    HapticFeedback.mediumImpact();
    if (_scrollCtrl.hasClients && _scrollCtrl.offset > 0) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) setState(() => _now = DateTime.now());
    _cardsCtrl
      ..reset()
      ..forward();

    ref.invalidate(courtsNotifierProvider);
    ref.invalidate(_staffHkProvider(_dateStr));

    await Future.wait([
      ref.read(_staffHkProvider(_dateStr).future).catchError((_) => null),
      ref.read(attendanceNotifierProvider.notifier).loadToday(),
      ref.read(courtFeedbackNotifierProvider.notifier).fetch(isRefresh: true),
    ]);
  }

  void _openFeedback(String courtName) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) =>
            StaffCourtFeedbackScreen(courtName: courtName),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _openSettings() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const StaffSettingsScreen(),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  // ─── Attendance flows ───────────────────────────────────────────────────────

  Future<void> _startCheckIn() async {
    HapticFeedback.selectionClick();
    final result = await context.push('/staff/mark-attendance');
    if (!mounted || result is! Map) return;

    final lat = (result['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (result['longitude'] as num?)?.toDouble() ?? 0.0;
    final imagePath = result['image_path'] as String?;
    if ((lat == 0.0 && lng == 0.0) || imagePath == null) {
      _toast('Could not capture location/photo. Try again.', isError: true);
      return;
    }
    final accuracy = (result['accuracy'] as num?)?.toDouble();
    final isMocked = result['is_mocked'] == true;
    await ref
        .read(attendanceNotifierProvider.notifier)
        .markAttendance(
          lat: lat,
          lng: lng,
          imagePath: imagePath,
          accuracy: accuracy,
          isMocked: isMocked,
        );
  }

  Future<void> _startCheckOut() async {
    HapticFeedback.selectionClick();
    final result = await context.push('/staff/mark-attendance');
    if (!mounted || result is! Map) return;

    final lat = (result['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (result['longitude'] as num?)?.toDouble() ?? 0.0;
    final imagePath = result['image_path'] as String?;
    if (lat == 0.0 && lng == 0.0) {
      _toast('Could not capture location. Try again.', isError: true);
      return;
    }
    final accuracy = (result['accuracy'] as num?)?.toDouble();
    final isMocked = result['is_mocked'] == true;
    await ref
        .read(attendanceNotifierProvider.notifier)
        .checkOut(
          lat: lat,
          lng: lng,
          imagePath: imagePath,
          accuracy: accuracy,
          isMocked: isMocked,
        );
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? _danger : _ok,
        content: Text(msg),
      ),
    );
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return TimeOfDay.fromDateTime(dt).format(context);
  }

  String? _durationLabel(int? minutes) {
    if (minutes == null) return null;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Animation<double> _stagger(int index) => CurvedAnimation(
    parent: _cardsCtrl,
    curve: Interval(
      (index * 0.1).clamp(0.0, 0.7),
      ((index * 0.1) + 0.4).clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Attendance snackbars
    ref.listen<AttendanceState>(attendanceNotifierProvider, (prev, next) {
      if (prev?.status == next.status) return;
      if (next.status == AttendanceStatus.success) {
        _toast(
          next.isCheckedOut
              ? 'Shift ended. Great work today!'
              : 'Checked in successfully!',
        );
      } else if (next.status == AttendanceStatus.error) {
        _toast(next.errorMessage ?? 'Something went wrong.', isError: true);
      }
    });

    final hkAsync = ref.watch(_staffHkProvider(_dateStr));
    final attendance = ref.watch(attendanceNotifierProvider);
    final feedbackAsync = ref.watch(courtFeedbackNotifierProvider);

    final courtsAsync = ref.watch(courtsNotifierProvider);
    String realCourtName = 'Court ${widget.assignedCourt}';
    courtsAsync.whenData((courts) {
      final match = courts.where((c) => c.id == widget.assignedCourt);
      if (match.isNotEmpty) realCourtName = match.first.name;
    });

    final navClearance = MediaQuery.of(context).padding.bottom + 92.0;

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── BLACK HEADER ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FadeTransition(
                          opacity: _heroFade,
                          child: Text(
                            'Hi, ${widget.staffName}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _white.withOpacity(0.55),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        FadeTransition(
                          opacity: _heroFade,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const StaffCalendarScreen(),
                                  ),
                                ),
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _white.withOpacity(0.08),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _white.withOpacity(0.15),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.calendar_month_rounded,
                                    size: 19,
                                    color: _white.withOpacity(0.9),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Consumer(
                                builder: (context, ref, _) {
                                  final unread =
                                      ref.watch(unreadCountProvider).value ?? 0;
                                  return GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const NoticesScreen(),
                                      ),
                                    ).then((_) =>
                                        ref.invalidate(unreadCountProvider)),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: _white.withOpacity(0.08),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _white.withOpacity(0.15),
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.notifications_none_rounded,
                                            size: 19,
                                            color: _white.withOpacity(0.9),
                                          ),
                                        ),
                                        if (unread > 0)
                                          Positioned(
                                            right: -2,
                                            top: -2,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              constraints: const BoxConstraints(
                                                minWidth: 16,
                                                minHeight: 16,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _red,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: _bg, width: 1.5),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  unread > 9 ? '9+' : '$unread',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 9,
                                                    height: 1,
                                                    color: _white,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: _openSettings,
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _red.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _red.withOpacity(0.35),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      widget.staffName.isNotEmpty
                                          ? widget.staffName[0].toUpperCase()
                                          : 'S',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        color: _red,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FadeTransition(
                      opacity: _heroFade,
                      child: SlideTransition(
                        position: _heroSlide,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.antonSc(
                                  fontSize: 50,
                                  height: 0.95,
                                  letterSpacing: -1,
                                ),
                                children: const [
                                  TextSpan(text: 'E', style: TextStyle(color: _red)),
                                  TextSpan(text: 'TL ', style: TextStyle(color: _white)),
                                  TextSpan(text: 'F', style: TextStyle(color: _red)),
                                  TextSpan(text: 'OOD', style: TextStyle(color: _white)),
                                ],
                              ),
                            ),
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.antonSc(
                                  fontSize: 50,
                                  height: 0.95,
                                  letterSpacing: -1,
                                ),
                                children: const [
                                  TextSpan(text: 'C', style: TextStyle(color: _red)),
                                  TextSpan(text: 'OURT', style: TextStyle(color: _white)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FadeTransition(
                      opacity: _heroFade,
                      child: Row(
                        children: [
                          _HeaderTag(
                            icon: Icons.stadium_rounded,
                            label: realCourtName,
                            color: _blue,
                          ),
                          const SizedBox(width: 8),
                          _HeaderTag(
                            icon: Icons.calendar_today_rounded,
                            label: _prettyDate(_now),
                            color: _white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── WHITE CANVAS ─────────────────────────────────────────
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: RefreshIndicator(
                    color: _black,
                    backgroundColor: _white,
                    strokeWidth: 2,
                    displacement: 40,
                    onRefresh: _refreshAll,
                    child: ListView(
                      controller: _scrollCtrl,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: EdgeInsets.fromLTRB(20, 24, 20, navClearance),
                      children: [
                        // 1) Attendance hub
                        _SectionLabel(
                          title: "Today's Shift",
                          trailing: _ShiftClock(shift: _currentShift, now: _now),
                        ),
                        const SizedBox(height: 12),
                        _StaggerRow(
                          anim: _stagger(0),
                          child: _buildAttendance(attendance),
                        ),
                        const SizedBox(height: 26),

                        // 2) Housekeeping progress
                        _SectionLabel(title: 'Housekeeping'),
                        const SizedBox(height: 12),
                        _StaggerRow(
                          anim: _stagger(1),
                          child: hkAsync.when(
                            loading: () => const _SkeletonCard(height: 130),
                            error: (_, __) => _ErrorCard(
                              label: 'Housekeeping',
                              onRetry: () =>
                                  ref.invalidate(_staffHkProvider(_dateStr)),
                            ),
                            data: (data) {
                              final shiftData = _resolveShift(data);
                              return _HousekeepingCard(
                                shift: _currentShift,
                                courtName: realCourtName,
                                done: shiftData.done,
                                total: shiftData.total == 0
                                    ? hk.kTasksPerShift
                                    : shiftData.total,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  context.go('/staff/checklist');
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 26),

                        // 3) Court feedback (replaces complaints)
                        _SectionLabel(title: 'Court Voice'),
                        const SizedBox(height: 12),
                        _StaggerRow(
                          anim: _stagger(2),
                          child: feedbackAsync.when(
                            loading: () => const _SkeletonCard(height: 120),
                            error: (_, __) => _ErrorCard(
                              label: 'Feedback',
                              onRetry: () => ref
                                  .read(courtFeedbackNotifierProvider.notifier)
                                  .fetch(isRefresh: true),
                            ),
                            data: (data) => _FeedbackCard(
                              analytics: data.analytics,
                              courtName: realCourtName,
                              onTap: () => _openFeedback(realCourtName),
                            ),
                          ),
                        ),
                      ],
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

  hk.ShiftStatus _resolveShift(hk.FullStatusResponse? data) {
    if (data == null) {
      return hk.ShiftStatus(
        shift: _currentShift,
        total: hk.kTasksPerShift,
        done: 0,
        submitted: false,
        tasks: const [],
      );
    }
    final courtData = data.courts.firstWhere(
      (c) => c.courtId == widget.assignedCourt,
      orElse: () => hk.CourtDayStatus(
        courtId: widget.assignedCourt,
        date: _dateStr,
        shifts: const [],
      ),
    );
    return courtData.shifts.firstWhere(
      (s) => s.shift == _currentShift,
      orElse: () => hk.ShiftStatus(
        shift: _currentShift,
        total: hk.kTasksPerShift,
        done: 0,
        submitted: false,
        tasks: const [],
      ),
    );
  }

  Widget _buildAttendance(AttendanceState attendance) {
    if (attendance.loadingToday ||
        attendance.status == AttendanceStatus.loading) {
      return const _SkeletonCard(height: 150);
    }
    if (attendance.isCheckedIn) {
      return _ActiveShiftCard(
        checkInTime: _fmtTime(attendance.today.checkInTime),
        checkInAt: attendance.today.checkInTime,
        address: attendance.today.checkInAddress ?? 'Location saved',
        checkedOut: attendance.isCheckedOut,
        checkOutTime: _fmtTime(attendance.today.checkOutTime),
        durationLabel: _durationLabel(attendance.today.workDurationMinutes),
        onEndShift:
            attendance.isShiftActive ? () => _startCheckOut() : null,
      );
    }
    return _MarkAttendanceCard(onTap: _startCheckIn);
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _prettyDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_monthsShort[d.month - 1]}';

// ─── Header tag chip ───────────────────────────────────────────────────────────
class _HeaderTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HeaderTag({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color == _white ? _white.withOpacity(0.85) : color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionLabel({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: _black,
            letterSpacing: -0.3,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─── Stagger wrapper ───────────────────────────────────────────────────────────
class _StaggerRow extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  const _StaggerRow({required this.anim, required this.child});

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: anim,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(anim),
      child: child,
    ),
  );
}

// ─── Shift clock pill (header trailing) ─────────────────────────────────────────
class _ShiftClock extends StatelessWidget {
  final hk.Shift shift;
  final DateTime now;
  const _ShiftClock({required this.shift, required this.now});

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (shift) {
      hk.Shift.morning => ('Morning', Icons.wb_sunny_rounded),
      hk.Shift.day => ('Day', Icons.light_mode_rounded),
      hk.Shift.night => ('Night', Icons.nights_stay_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _warn.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _warn.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _warn),
          const SizedBox(width: 5),
          Text(
            '$label Shift',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _warn,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mark Attendance Card ────────────────────────────────────────────────────
class _MarkAttendanceCard extends StatefulWidget {
  final VoidCallback onTap;
  const _MarkAttendanceCard({required this.onTap});

  @override
  State<_MarkAttendanceCard> createState() => _MarkAttendanceCardState();
}

class _MarkAttendanceCardState extends State<_MarkAttendanceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  bool _pressed = false;

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
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _black,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _black.withOpacity(0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) => Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _blue.withOpacity(0.10 + (_pulseCtrl.value * 0.10)),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    color: _blue,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'MARK ATTENDANCE',
                style: GoogleFonts.antonSc(
                  fontSize: 26,
                  color: _white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Secure check-in via live selfie & location',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
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
      ),
    );
  }
}

// ─── Active / Completed Shift Card ────────────────────────────────────────────
class _ActiveShiftCard extends StatelessWidget {
  final String checkInTime;
  final DateTime? checkInAt;
  final String address;
  final bool checkedOut;
  final String checkOutTime;
  final String? durationLabel;
  final VoidCallback? onEndShift;

  const _ActiveShiftCard({
    required this.checkInTime,
    required this.address,
    this.checkInAt,
    this.checkedOut = false,
    this.checkOutTime = '--:--',
    this.durationLabel,
    this.onEndShift,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = checkedOut ? _blue : _ok;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEDEDED), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      checkedOut ? 'SHIFT COMPLETED' : 'SHIFT ACTIVE',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                if (!checkedOut)
                  _LiveShiftTimer(since: checkInAt)
                else
                  Text(
                    durationLabel ?? '--',
                    style: GoogleFonts.antonSc(
                      fontSize: 46,
                      color: _black,
                      height: 1.0,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  checkedOut
                      ? 'Total time on shift'
                      : 'On shift since $checkInTime',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: _grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (checkedOut) ...[
            Row(
              children: [
                Expanded(
                  child: _TimeBlock(
                    icon: Icons.login_rounded,
                    label: 'Checked In',
                    value: checkInTime,
                    color: _ok,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeBlock(
                    icon: Icons.logout_rounded,
                    label: 'Checked Out',
                    value: checkOutTime,
                    color: _blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          const Divider(height: 1, color: Color(0xFFEDEDED)),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 15, color: _grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (onEndShift != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onEndShift,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _black,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.logout_rounded, size: 16, color: _white),
                      const SizedBox(width: 8),
                      Text(
                        'End Shift',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _TimeBlock({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFEDEDED)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _black,
          ),
        ),
      ],
    ),
  );
}

// ─── Live ticking timer ───────────────────────────────────────────────────────
class _LiveShiftTimer extends StatefulWidget {
  final DateTime? since;
  const _LiveShiftTimer({this.since});

  @override
  State<_LiveShiftTimer> createState() => _LiveShiftTimerState();
}

class _LiveShiftTimerState extends State<_LiveShiftTimer> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.since;
    String txt = '00:00:00';
    if (since != null) {
      final d = DateTime.now().difference(since);
      final h = d.inHours.toString().padLeft(2, '0');
      final m = (d.inMinutes % 60).toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      txt = '$h:$m:$s';
    }
    return Text(
      txt,
      style: GoogleFonts.antonSc(fontSize: 46, color: _black, height: 1.0),
    );
  }
}

// ─── Housekeeping Card ────────────────────────────────────────────────────────
class _HousekeepingCard extends StatefulWidget {
  final hk.Shift shift;
  final String courtName;
  final int done, total;
  final VoidCallback onTap;

  const _HousekeepingCard({
    required this.shift,
    required this.courtName,
    required this.done,
    required this.total,
    required this.onTap,
  });

  @override
  State<_HousekeepingCard> createState() => _HousekeepingCardState();
}

class _HousekeepingCardState extends State<_HousekeepingCard> {
  bool _pressed = false;

  String _shiftLbl(hk.Shift s) => switch (s) {
    hk.Shift.morning => 'Morning',
    hk.Shift.day => 'Day',
    hk.Shift.night => 'Night',
  };

  @override
  Widget build(BuildContext context) {
    final pct = widget.total == 0 ? 0.0 : widget.done / widget.total;
    final allDone = widget.total > 0 && widget.done == widget.total;
    final barColor = allDone ? _ok : (pct >= 0.5 ? _warn : _danger);

    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        setState(() => _pressed = true);
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: allDone ? _ok.withOpacity(0.4) : const Color(0xFFEDEDED),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (allDone ? _ok : _blue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      allDone
                          ? Icons.verified_rounded
                          : Icons.cleaning_services_rounded,
                      size: 18,
                      color: allDone ? _ok : _blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shift Tasks',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _black,
                          ),
                        ),
                        Text(
                          '${widget.courtName} · ${_shiftLbl(widget.shift)} Shift',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: pct * 100),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, val, __) => Text(
                      '${val.round()}%',
                      style: GoogleFonts.antonSc(
                        fontSize: 30,
                        color: allDone ? _ok : _black,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, val, __) => LinearProgressIndicator(
                    value: val,
                    minHeight: 7,
                    backgroundColor: Colors.black.withOpacity(0.06),
                    valueColor: AlwaysStoppedAnimation(barColor),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${widget.done} / ${widget.total} tasks done',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        allDone ? 'Completed' : 'Open Checklist',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: allDone ? _ok : _blue,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: allDone ? _ok : _blue,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Court Feedback Card (replaces complaints) ──────────────────────────────────
class _FeedbackCard extends StatefulWidget {
  final CourtFeedbackAnalytics? analytics;
  final String courtName;
  final VoidCallback onTap;

  const _FeedbackCard({
    required this.analytics,
    required this.courtName,
    required this.onTap,
  });

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.analytics;
    final avg = a?.avgCourtRating;
    final total = a?.totalCount ?? 0;
    final hasData = total > 0;

    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        setState(() => _pressed = true);
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _black,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _black.withOpacity(0.15),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.rate_review_rounded,
                      size: 18,
                      color: _blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guest Feedback',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _white,
                          ),
                        ),
                        Text(
                          hasData
                              ? '$total ${total == 1 ? 'review' : 'reviews'} for your court'
                              : 'No reviews yet',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.white38,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    avg != null ? avg.toStringAsFixed(1) : '—',
                    style: GoogleFonts.antonSc(
                      fontSize: 40,
                      color: _white,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: List.generate(5, (i) {
                        final filled = avg != null && i < avg.round();
                        return Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 15,
                          color: filled ? _warn : Colors.white24,
                        );
                      }),
                    ),
                  ),
                  const Spacer(),
                  if (a != null && hasData)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: (a.isGrowing ? _ok : _danger).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        a.isGrowing
                            ? '+${a.wowGrowth.toStringAsFixed(0)}%'
                            : '${a.wowGrowth.toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: a.isGrowing ? _ok : _danger,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Skeleton + Error ──────────────────────────────────────────────────────────
class _SkeletonCard extends StatefulWidget {
  final double height;
  const _SkeletonCard({required this.height});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            const Color(0xFFF0F0F0),
            const Color(0xFFE3E3E3),
            _ctrl.value,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String label;
  final VoidCallback onRetry;
  const _ErrorCard({required this.label, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _danger.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _danger.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: _danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Couldn't load $label",
              style: GoogleFonts.inter(
                fontSize: 13,
                color: _danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              'Retry',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
