// lib/features/staff/presentation/staff_home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../staff/domain/housekeeping_models.dart' as hk;
import '../../staff/data/housekeeping_repository.dart';
import '../../complaints/domain/complaint_model.dart';
import '../../complaints/data/complaints_repository.dart';
import 'staff_complaints_screen.dart';
import '../../settings/presentation/staff_settings_screen.dart'; // ← NEW

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
const _border = Color(0xFF1A1A1A);

// ─── Shift ranges ─────────────────────────────────────────────────────────────
const _shiftRanges = {
  hk.Shift.morning: (start: 6, end: 12),
  hk.Shift.day: (start: 12, end: 16),
  hk.Shift.night: (start: 16, end: 24),
};

// ─── Providers ────────────────────────────────────────────────────────────────
final _staffHkProvider = FutureProvider.autoDispose
    .family<hk.FullStatusResponse?, String>((ref, date) async {
      return ref.read(housekeepingRepoProvider).getFullStatus(date: date);
    });

final _staffComplaintsProvider = FutureProvider.autoDispose
    .family<List<ComplaintModel>, int>((ref, courtId) async {
      return ref
          .read(complaintsRepoProvider)
          .getComplaints(courtId: courtId, status: 'open');
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
    ref.invalidate(_staffHkProvider(_dateStr));
    ref.invalidate(_staffComplaintsProvider(widget.assignedCourt));
    await Future.wait([
      ref.read(_staffHkProvider(_dateStr).future).catchError((_) => null),
      ref
          .read(_staffComplaintsProvider(widget.assignedCourt).future)
          .catchError((_) => <ComplaintModel>[]),
    ]);
  }

  void _openComplaints() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => StaffComplaintsScreen(
          courtId: widget.assignedCourt,
          courtName: 'Court ${widget.assignedCourt}',
        ),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
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

  // ── NEW: Navigation to StaffSettingsScreen ──────────────────────────────────
  void _openSettings() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const StaffSettingsScreen(),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
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
    final hkAsync = ref.watch(_staffHkProvider(_dateStr));
    final cmpAsync = ref.watch(_staffComplaintsProvider(widget.assignedCourt));
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
                          child: SlideTransition(
                            position: _heroSlide,
                            child: Text(
                              'Hi, ${widget.staffName}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _white.withOpacity(0.55),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                        // ── Avatar → tappable → opens Settings ──────
                        FadeTransition(
                          opacity: _heroFade,
                          child: GestureDetector(
                            onTap: _openSettings, // ← NEW
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
                                  fontSize: 54,
                                  height: 0.95,
                                  letterSpacing: -1,
                                ),
                                children: const [
                                  TextSpan(
                                    text: 'E',
                                    style: TextStyle(color: _red),
                                  ),
                                  TextSpan(
                                    text: 'TL ',
                                    style: TextStyle(color: _white),
                                  ),
                                  TextSpan(
                                    text: 'F',
                                    style: TextStyle(color: _red),
                                  ),
                                  TextSpan(
                                    text: 'OOD',
                                    style: TextStyle(color: _white),
                                  ),
                                ],
                              ),
                            ),
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.antonSc(
                                  fontSize: 54,
                                  height: 0.95,
                                  letterSpacing: -1,
                                ),
                                children: const [
                                  TextSpan(
                                    text: 'C',
                                    style: TextStyle(color: _red),
                                  ),
                                  TextSpan(
                                    text: 'OURT',
                                    style: TextStyle(color: _white),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── WHITE CARDS AREA ─────────────────────────────────────
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: RefreshIndicator(
                    color: _black,
                    backgroundColor: _white,
                    strokeWidth: 2,
                    displacement: 40,
                    onRefresh: _refreshAll,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollEndNotification &&
                            _scrollCtrl.hasClients &&
                            _scrollCtrl.offset < 0) {
                          _scrollCtrl.animateTo(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                          );
                        }
                        return false;
                      },
                      child: ListView(
                        controller: _scrollCtrl,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: EdgeInsets.fromLTRB(20, 24, 20, navClearance),
                        children: [
                          // 1. Shift Card
                          _StaggerRow(
                            anim: _stagger(0),
                            child: _ShiftCard(shift: _currentShift, now: _now),
                          ),
                          const SizedBox(height: 10),

                          // 2. Housekeeping Card
                          _StaggerRow(
                            anim: _stagger(1),
                            child: hkAsync.when(
                              loading: () => const _SkeletonCard(height: 120),
                              error: (_, __) => _ErrorCard(
                                label: 'Housekeeping',
                                onRetry: () =>
                                    ref.invalidate(_staffHkProvider(_dateStr)),
                              ),
                              data: (data) {
                                if (data == null) {
                                  return _ErrorCard(
                                    label: 'Housekeeping',
                                    onRetry: () => ref.invalidate(
                                      _staffHkProvider(_dateStr),
                                    ),
                                  );
                                }
                                final courtData = data.courts.firstWhere(
                                  (c) => c.courtId == widget.assignedCourt,
                                  orElse: () => hk.CourtDayStatus(
                                    courtId: widget.assignedCourt,
                                    date: _dateStr,
                                    shifts: [],
                                  ),
                                );
                                final shiftData = courtData.shifts.firstWhere(
                                  (s) => s.shift == _currentShift,
                                  orElse: () => hk.ShiftStatus(
                                    shift: _currentShift,
                                    total: hk.kTasksPerShift,
                                    done: 0,
                                    submitted: false,
                                    tasks: [],
                                  ),
                                );
                                return _HousekeepingCard(
                                  shift: _currentShift,
                                  court: widget.assignedCourt,
                                  done: shiftData.done,
                                  total: shiftData.total == 0
                                      ? hk.kTasksPerShift
                                      : shiftData.total,
                                  onTap: () {},
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 3. Complaints Card
                          _StaggerRow(
                            anim: _stagger(2),
                            child: cmpAsync.when(
                              loading: () => const _SkeletonCard(height: 80),
                              error: (_, __) => _ErrorCard(
                                label: 'Complaints',
                                onRetry: () => ref.invalidate(
                                  _staffComplaintsProvider(
                                    widget.assignedCourt,
                                  ),
                                ),
                              ),
                              data: (complaints) => _ComplaintsCard(
                                openCount: complaints.length,
                                courtId: widget.assignedCourt,
                                onViewTap: _openComplaints,
                              ),
                            ),
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
}

// ─── _StaggerRow ──────────────────────────────────────────────────────────────
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

// ─── Shift Card ───────────────────────────────────────────────────────────────
class _ShiftCard extends StatelessWidget {
  final hk.Shift shift;
  final DateTime now;
  const _ShiftCard({required this.shift, required this.now});

  @override
  Widget build(BuildContext context) {
    final range = _shiftRanges[shift]!;

    final DateTime endTime = switch (shift) {
      hk.Shift.night =>
        now.hour >= 16
            ? DateTime(now.year, now.month, now.day + 1, 0, 0)
            : DateTime(now.year, now.month, now.day, 0, 0),
      _ => DateTime(now.year, now.month, now.day, range.end, 0),
    };

    final remaining = endTime.difference(now);
    final isOver = remaining.isNegative;

    final String timeLeft = isOver
        ? 'Shift ended'
        : remaining.inHours > 0
        ? '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m left'
        : '${remaining.inMinutes}m left';

    final IconData shiftIcon = switch (shift) {
      hk.Shift.morning => Icons.wb_sunny_rounded,
      hk.Shift.day => Icons.light_mode_rounded,
      hk.Shift.night => Icons.nights_stay_rounded,
    };
    final String shiftLabel = switch (shift) {
      hk.Shift.morning => 'MORNING SHIFT',
      hk.Shift.day => 'DAY SHIFT',
      hk.Shift.night => 'NIGHT SHIFT',
    };
    final String shiftTime = switch (shift) {
      hk.Shift.morning => '06:00 – 12:00',
      hk.Shift.day => '12:00 – 16:00',
      hk.Shift.night => '16:00 – 00:00',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(shiftIcon, size: 20, color: _warn),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shiftLabel,
                  style: GoogleFonts.antonSc(
                    fontSize: 15,
                    color: _white,
                    letterSpacing: 0.5,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  shiftTime,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isOver ? _grey.withOpacity(0.12) : _ok.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isOver ? _grey.withOpacity(0.2) : _ok.withOpacity(0.3),
              ),
            ),
            child: Text(
              timeLeft,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isOver ? _grey : _ok,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Housekeeping Card ────────────────────────────────────────────────────────
class _HousekeepingCard extends StatefulWidget {
  final hk.Shift shift;
  final int court, done, total;
  final VoidCallback onTap;
  const _HousekeepingCard({
    required this.shift,
    required this.court,
    required this.done,
    required this.total,
    required this.onTap,
  });
  @override
  State<_HousekeepingCard> createState() => _HousekeepingCardState();
}

class _HousekeepingCardState extends State<_HousekeepingCard> {
  bool _pressed = false;

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
              color: allDone ? _ok.withOpacity(0.4) : _border,
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
                          'Housekeeping',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _black,
                          ),
                        ),
                        Text(
                          'Court ${widget.court} · ${_shiftLbl(widget.shift)} Shift',
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
                        allDone ? 'Completed' : 'Open Tasks',
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

// ─── Complaints Card ──────────────────────────────────────────────────────────
class _ComplaintsCard extends StatefulWidget {
  final int openCount, courtId;
  final VoidCallback onViewTap;
  const _ComplaintsCard({
    required this.openCount,
    required this.courtId,
    required this.onViewTap,
  });
  @override
  State<_ComplaintsCard> createState() => _ComplaintsCardState();
}

class _ComplaintsCardState extends State<_ComplaintsCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final hasOpen = widget.openCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasOpen ? _danger.withOpacity(0.3) : _border,
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
                  color: (hasOpen ? _danger : _ok).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.report_problem_rounded,
                  size: 18,
                  color: hasOpen ? _danger : _ok,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complaints',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _black,
                      ),
                    ),
                    Text(
                      'Court ${widget.courtId}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Container(
                  key: ValueKey(
                    'complaints_badge_${widget.courtId}_${widget.openCount}',
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: (hasOpen ? _danger : _ok).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (hasOpen ? _danger : _ok).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    hasOpen ? '${widget.openCount} open' : 'All clear',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: hasOpen ? _danger : _ok,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTapDown: (_) {
              HapticFeedback.selectionClick();
              setState(() => _pressed = true);
            },
            onTapUp: (_) {
              setState(() => _pressed = false);
              widget.onViewTap();
            },
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: _pressed ? 0.96 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: _black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.list_rounded, size: 15, color: _white),
                    const SizedBox(width: 6),
                    Text(
                      'View Complaints',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Skeleton Card ────────────────────────────────────────────────────────────
class _SkeletonCard extends StatefulWidget {
  final double height;
  const _SkeletonCard({required this.height});
  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Color.lerp(
          const Color(0xFFF0F0F0),
          const Color(0xFFE0E0E0),
          _anim.value,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  );
}

// ─── Error Card ───────────────────────────────────────────────────────────────
class _ErrorCard extends StatelessWidget {
  final String label;
  final VoidCallback onRetry;
  const _ErrorCard({required this.label, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _danger.withOpacity(0.05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _danger.withOpacity(0.2)),
    ),
    child: Row(
      children: [
        Icon(Icons.wifi_off_rounded, color: _danger.withOpacity(0.6), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Could not load $label',
            style: GoogleFonts.inter(fontSize: 13, color: _danger),
          ),
        ),
        GestureDetector(
          onTap: onRetry,
          child: Text(
            'Retry',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _danger,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─── Helper ───────────────────────────────────────────────────────────────────
String _shiftLbl(hk.Shift s) => const {
  hk.Shift.morning: 'Morning',
  hk.Shift.day: 'Day',
  hk.Shift.night: 'Night',
}[s]!;
