// lib/features/home/presentation/home_screen.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/token_storage.dart';
import '../../courts/domain/courts_notifier.dart';
import 'home_providers.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _lightGrey = Color(0xFFF2F2F2);
const _border = Color(0xFF1A1A1A);
const _red = Color(0xFFd02128);

const _pillGreenFg = Color(0xFF15803D);
const _pillGreenBg = Color(0xFFDCFCE7);
const _pillYellowFg = Color(0xFFB45309);
const _pillYellowBg = Color(0xFFFEF3C7);
const _pillInactiveFg = Color(0xFFBBBBBB);
const _pillInactiveBg = Color(0xFFF5F5F5);

// ─── Home Screen ──────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  String _managerName = 'Manager';

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  late final AnimationController _heroCtrl;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  late final AnimationController _cardsCtrl;

  final ScrollController _scrollCtrl = ScrollController();

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

    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));
    _heroCtrl.forward();

    _cardsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _cardsCtrl.forward();

    _loadName();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _heroCtrl.dispose();
    _cardsCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadName() async {
    final name = await TokenStorage.getManagerName();
    if (name != null && mounted) setState(() => _managerName = name);
  }

  Future<void> _refreshAll() async {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    ref.invalidate(homeYesterdaySalesProvider);
    ref.invalidate(homeMonthSalesProvider);
    ref.read(courtsNotifierProvider.notifier).fetchCourts();
    ref.invalidate(homeHousekeepingProvider);
    ref.invalidate(
      homeFeedbacksProvider,
    ); // 🟢 FIX: Updated to Feedbacks Provider
    ref.invalidate(homeMaintenanceProvider);
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Animation<double> _stagger(int index) {
    final start = (index * 0.1).clamp(0.0, 0.7);
    final end = (start + 0.4).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _cardsCtrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final yesterdayAsync = ref.watch(homeYesterdaySalesProvider);
    final monthAsync = ref.watch(homeMonthSalesProvider);
    final courtsAsync = ref.watch(courtsNotifierProvider);
    final hkAsync = ref.watch(homeHousekeepingProvider);
    final feedbackAsync = ref.watch(
      homeFeedbacksProvider,
    ); // 🟢 FIX: Feedbacks Provider
    final maintenanceAsync = ref.watch(homeMaintenanceProvider);

    final yesterdaySales = yesterdayAsync.maybeWhen(
      data: (v) => v,
      orElse: () => 0.0,
    );
    final monthSales = monthAsync.maybeWhen(data: (v) => v, orElse: () => 0.0);
    final isLoadingYesterday = yesterdayAsync is AsyncLoading;
    final isLoadingMonth = monthAsync is AsyncLoading;

    final totalCourts = courtsAsync.whenData((c) => c.length).value ?? 0;
    final isLoadingCourts = courtsAsync is AsyncLoading;

    final hkRows = hkAsync.maybeWhen(
      data: (v) => v,
      orElse: () => <CourtHkRow>[],
    );
    final hkLoading = hkAsync is AsyncLoading;

    // 🟢 FIX: Feedback Count extract kiya
    final feedbackCount = feedbackAsync.maybeWhen(
      data: (v) => v,
      orElse: () => 0,
    );

    final maintenanceCount = maintenanceAsync.maybeWhen(
      data: (v) => v,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: _black,
      body: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              // ══════════════════════════════════════════════
              // BLACK HEADER
              // ══════════════════════════════════════════════
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopRow(managerName: _managerName),
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

              // ══════════════════════════════════════════════
              // WHITE CONTENT
              // ══════════════════════════════════════════════
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
                    strokeWidth: 2,
                    backgroundColor: _white,
                    onRefresh: _refreshAll,
                    child: SingleChildScrollView(
                      controller: _scrollCtrl,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Revenue + Courts — stagger 0 ──────────────
                          _StaggerRow(
                            anim: _stagger(0),
                            child: SizedBox(
                              height: 120,
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 55,
                                    child: _OutlineCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Revenue',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: _grey,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                'Yesterday · All Courts',
                                                style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  color: _grey.withOpacity(
                                                    0.65,
                                                  ),
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ],
                                          ),
                                          isLoadingYesterday
                                              ? const _Skeleton(
                                                  width: 100,
                                                  height: 32,
                                                )
                                              : TweenAnimationBuilder<double>(
                                                  tween: Tween<double>(
                                                    begin: 0,
                                                    end: yesterdaySales,
                                                  ),
                                                  duration: const Duration(
                                                    milliseconds: 700,
                                                  ),
                                                  curve: Curves.easeOutCubic,
                                                  builder: (_, val, __) => Text(
                                                    '₹${_fmt(val)}',
                                                    style: GoogleFonts.antonSc(
                                                      fontSize: 30,
                                                      color: _black,
                                                      height: 1,
                                                    ),
                                                  ),
                                                ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 45,
                                    child: _FilledCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Courts',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Colors.white60,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          isLoadingCourts
                                              ? const _Skeleton(
                                                  width: 70,
                                                  height: 28,
                                                  dark: true,
                                                )
                                              : AnimatedSwitcher(
                                                  duration: const Duration(
                                                    milliseconds: 350,
                                                  ),
                                                  switchInCurve:
                                                      Curves.easeOutCubic,
                                                  switchOutCurve:
                                                      Curves.easeInCubic,
                                                  transitionBuilder:
                                                      (
                                                        child,
                                                        anim,
                                                      ) => FadeTransition(
                                                        opacity: anim,
                                                        child: SlideTransition(
                                                          position:
                                                              Tween<Offset>(
                                                                begin:
                                                                    const Offset(
                                                                      0,
                                                                      0.3,
                                                                    ),
                                                                end:
                                                                    Offset.zero,
                                                              ).animate(anim),
                                                          child: child,
                                                        ),
                                                      ),
                                                  child: Text(
                                                    '$totalCourts Active',
                                                    key: ValueKey(totalCourts),
                                                    style: GoogleFonts.antonSc(
                                                      fontSize: 24,
                                                      color: _white,
                                                      height: 1,
                                                    ),
                                                  ),
                                                ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ── Sparkline (Monthly Total) — stagger 1 ─────
                          _StaggerRow(
                            anim: _stagger(1),
                            child: _OutlineCard(
                              height: 96,
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: SizedBox(
                                      height: 46,
                                      child: CustomPaint(
                                        painter: _SparklinePainter(
                                          color: _black,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 46,
                                    color: _border.withOpacity(0.12),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Total Sales',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: _grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          'This Month · All Courts',
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            color: _grey.withOpacity(0.65),
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        isLoadingMonth
                                            ? const _Skeleton(
                                                width: 80,
                                                height: 24,
                                              )
                                            : TweenAnimationBuilder<double>(
                                                tween: Tween<double>(
                                                  begin: 0,
                                                  end: monthSales,
                                                ),
                                                duration: const Duration(
                                                  milliseconds: 700,
                                                ),
                                                curve: Curves.easeOutCubic,
                                                builder: (_, val, __) => Text(
                                                  '₹${_fmt(val)}',
                                                  style: GoogleFonts.antonSc(
                                                    fontSize: 26,
                                                    color: _black,
                                                    height: 1,
                                                  ),
                                                ),
                                              ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ── Feedback + Maintenance — stagger 2 ──────
                          _StaggerRow(
                            anim: _stagger(2),
                            child: SizedBox(
                              height: 100,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        context.go(
                                          '/feedbacks',
                                        ); // 🟢 FIX: Feedback route wired
                                      },
                                      child: _OutlineCard(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'Feedback', // 🟢 FIX: Name changed
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: _grey,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const Icon(
                                                  Icons
                                                      .arrow_forward_ios_rounded,
                                                  size: 11,
                                                  color: _grey,
                                                ),
                                              ],
                                            ),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                feedbackAsync is AsyncLoading
                                                    ? const _Skeleton(
                                                        width: 36,
                                                        height: 32,
                                                      )
                                                    : AnimatedSwitcher(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 350,
                                                            ),
                                                        switchInCurve:
                                                            Curves.easeOutCubic,
                                                        switchOutCurve:
                                                            Curves.easeInCubic,
                                                        transitionBuilder:
                                                            (
                                                              child,
                                                              anim,
                                                            ) => FadeTransition(
                                                              opacity: anim,
                                                              child: SlideTransition(
                                                                position: Tween<Offset>(
                                                                  begin:
                                                                      const Offset(
                                                                        0,
                                                                        0.3,
                                                                      ),
                                                                  end: Offset
                                                                      .zero,
                                                                ).animate(anim),
                                                                child: child,
                                                              ),
                                                            ),
                                                        child: Text(
                                                          '$feedbackCount', // 🟢 FIX: Connected to feedback count
                                                          key: ValueKey(
                                                            feedbackCount,
                                                          ),
                                                          style:
                                                              GoogleFonts.antonSc(
                                                                fontSize: 32,
                                                                color: _black,
                                                                height: 1,
                                                              ),
                                                        ),
                                                      ),
                                                const SizedBox(width: 6),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 3,
                                                      ),
                                                  child: Text(
                                                    'new', // Updated for feedbacks
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12,
                                                      color: _grey,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        context.go('/maintenance');
                                      },
                                      child: _FilledCard(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'Maintenance',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: Colors.white60,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                Icon(
                                                  Icons
                                                      .arrow_forward_ios_rounded,
                                                  size: 11,
                                                  color: Colors.white
                                                      .withOpacity(0.4),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                maintenanceAsync is AsyncLoading
                                                    ? const _Skeleton(
                                                        width: 36,
                                                        height: 32,
                                                        dark: true,
                                                      )
                                                    : AnimatedSwitcher(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 350,
                                                            ),
                                                        switchInCurve:
                                                            Curves.easeOutCubic,
                                                        switchOutCurve:
                                                            Curves.easeInCubic,
                                                        transitionBuilder:
                                                            (
                                                              child,
                                                              anim,
                                                            ) => FadeTransition(
                                                              opacity: anim,
                                                              child: SlideTransition(
                                                                position: Tween<Offset>(
                                                                  begin:
                                                                      const Offset(
                                                                        0,
                                                                        0.3,
                                                                      ),
                                                                  end: Offset
                                                                      .zero,
                                                                ).animate(anim),
                                                                child: child,
                                                              ),
                                                            ),
                                                        child: Text(
                                                          '$maintenanceCount',
                                                          key: ValueKey(
                                                            maintenanceCount,
                                                          ),
                                                          style:
                                                              GoogleFonts.antonSc(
                                                                fontSize: 32,
                                                                color: _white,
                                                                height: 1,
                                                              ),
                                                        ),
                                                      ),
                                                const SizedBox(width: 6),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 3,
                                                      ),
                                                  child: Text(
                                                    'pending',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12,
                                                      color: Colors.white60,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
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
                          const SizedBox(height: 10),

                          // ── Housekeeping — stagger 3 ──────────────────
                          _StaggerRow(
                            anim: _stagger(3),
                            child: _HousekeepingCard(
                              loading: hkLoading,
                              rows: hkRows,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                context.go('/housekeeping');
                              },
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── Staff Attendance roster entry ─────────────
                          _StaggerRow(
                            anim: _stagger(4),
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                context.push('/attendance-roster');
                              },
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: _black,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _black.withOpacity(0.12),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF60A5FA,
                                        ).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: const Icon(
                                        Icons.groups_rounded,
                                        color: Color(0xFF60A5FA),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Staff Attendance',
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: _white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Court-wise roster & check-ins',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Colors.white60,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 14,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── Courts — stagger 4 ────────────────────────
                          _StaggerRow(
                            anim: _stagger(4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionHeader(
                                  title: 'Courts',
                                  onViewAll: () {},
                                ),
                                const SizedBox(height: 12),
                                courtsAsync.when(
                                  loading: () => Column(
                                    children: List.generate(
                                      3,
                                      (_) => const Padding(
                                        padding: EdgeInsets.only(bottom: 10),
                                        child: _Skeleton(
                                          width: double.infinity,
                                          height: 72,
                                        ),
                                      ),
                                    ),
                                  ),
                                  error: (_, __) => const _ErrorRow(
                                    message: 'Could not load courts',
                                  ),
                                  data: (courts) => Column(
                                    children: courts
                                        .asMap()
                                        .entries
                                        .map(
                                          (e) => Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            child: _CourtRow(
                                              court: e.value,
                                              index: e.key,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
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

// ─── Top Row ──────────────────────────────────────────────────────────────────

class _TopRow extends StatefulWidget {
  final String managerName;
  const _TopRow({required this.managerName});

  @override
  State<_TopRow> createState() => _TopRowState();
}

class _TopRowState extends State<_TopRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        'Hi, ${widget.managerName}',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: _white.withOpacity(0.55),
          fontWeight: FontWeight.w500,
        ),
      ),
      GestureDetector(
        onTapDown: (_) {
          HapticFeedback.selectionClick();
          setState(() => _pressed = true);
        },
        onTapUp: (_) {
          setState(() => _pressed = false);
          context.push('/settings');
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _red.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: _red.withOpacity(0.35), width: 1.5),
            ),
            child: Center(
              child: Text(
                widget.managerName.isNotEmpty
                    ? widget.managerName[0].toUpperCase()
                    : 'M',
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
  );
}

// ─── StaggerRow ───────────────────────────────────────────────────────────────

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

// ─── Legend Dot ───────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color fg;
  final String label;
  const _LegendDot({required this.fg, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          color: _grey,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

// ─── Housekeeping Card (interactive) ──────────────────────────────────────────

class _HousekeepingCard extends StatefulWidget {
  final bool loading;
  final List<CourtHkRow> rows;
  final VoidCallback onTap;
  const _HousekeepingCard({
    required this.loading,
    required this.rows,
    required this.onTap,
  });

  @override
  State<_HousekeepingCard> createState() => _HousekeepingCardState();
}

class _HousekeepingCardState extends State<_HousekeepingCard> {
  bool _pressed = false;

  bool get _tappable => !widget.loading;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final totalDone = rows.fold<int>(0, (s, r) => s + r.done);
    final totalTasks = rows.fold<int>(0, (s, r) => s + r.total);
    final overallPct = totalTasks == 0 ? 0.0 : totalDone / totalTasks;
    final hasData = !widget.loading && rows.isNotEmpty;

    final String subtitle = widget.loading
        ? 'Fetching today\u2019s checklists\u2026'
        : rows.isEmpty
        ? 'No checklist configured yet'
        : totalTasks == 0
        ? 'No tasks scheduled today'
        : '$totalDone of $totalTasks tasks done today';

    return GestureDetector(
      onTapDown: _tappable ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: _tappable
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: _OutlineCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: title + summary + ring + chevron ──
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Housekeeping',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: _black,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (hasData && totalTasks > 0) _HkRing(pct: overallPct),
                  if (_tappable) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: _grey,
                    ),
                  ],
                ],
              ),

              if (widget.loading) ...[
                const SizedBox(height: 16),
                ...List.generate(
                  3,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _Skeleton(width: 110, height: 13),
                            Spacer(),
                            _Skeleton(width: 38, height: 13),
                          ],
                        ),
                        SizedBox(height: 9),
                        _Skeleton(width: double.infinity, height: 6),
                        SizedBox(height: 9),
                        Row(
                          children: [
                            _Skeleton(width: 64, height: 24),
                            SizedBox(width: 5),
                            _Skeleton(width: 64, height: 24),
                            SizedBox(width: 5),
                            _Skeleton(width: 64, height: 24),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (rows.isEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Build a checklist from the Housekeeping tab to track '
                  'shift completion here.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: _grey,
                    height: 1.35,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                const Divider(height: 22, thickness: 1, color: Color(0xFFF1F1F1)),
                for (int i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 15),
                  _CourtHkRow(row: rows[i]),
                ],
                const SizedBox(height: 14),
                // legend footer
                Row(
                  children: const [
                    _LegendDot(fg: _pillGreenFg, label: 'Done'),
                    SizedBox(width: 12),
                    _LegendDot(fg: _pillYellowFg, label: 'In progress'),
                    SizedBox(width: 12),
                    _LegendDot(fg: _pillInactiveFg, label: 'Pending'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Overall completion ring ──────────────────────────────────────────────────

class _HkRing extends StatelessWidget {
  final double pct;
  const _HkRing({required this.pct});

  @override
  Widget build(BuildContext context) {
    final bool complete = pct >= 0.999;
    final Color color = complete
        ? _pillGreenFg
        : pct > 0
        ? _black
        : _grey;

    return SizedBox(
      width: 44,
      height: 44,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: pct.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => CustomPaint(
          painter: _RingPainter(pct: v, color: color),
          child: Center(
            child: complete
                ? const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: _pillGreenFg,
                  )
                : Text(
                    '${(v * 100).round()}',
                    style: GoogleFonts.antonSc(
                      fontSize: 14,
                      color: color,
                      height: 1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final Color color;
  const _RingPainter({required this.pct, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFFEDEDED);
    canvas.drawCircle(center, radius, track);

    if (pct > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * pct.clamp(0.0, 1.0),
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.pct != pct || old.color != color;
}

// ─── Court HK Row ─────────────────────────────────────────────────────────────

class _CourtHkRow extends StatelessWidget {
  final CourtHkRow row;
  const _CourtHkRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final bool hasTasks = row.total > 0;
    final bool allDone = row.isComplete;
    final bool started = row.done > 0;

    final Color dotColor = !hasTasks
        ? _pillInactiveFg
        : allDone
        ? _pillGreenFg
        : started
        ? _pillYellowFg
        : _pillInactiveFg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                row.courtName,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _black,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            if (!hasTasks)
              Text(
                'No checklist',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: _grey,
                  fontWeight: FontWeight.w500,
                ),
              )
            else if (allDone)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: _pillGreenFg),
                  const SizedBox(width: 4),
                  Text(
                    'All done',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: _pillGreenFg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            else
              Text(
                '${row.done}/${row.total}',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: _grey,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        if (hasTasks) ...[
          const SizedBox(height: 8),
          _MiniBar(
            pct: row.pct,
            color: allDone ? _pillGreenFg : _black,
          ),
        ],
        if (row.shifts.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [for (final p in row.shifts) _ShiftPill(pill: p)],
          ),
        ],
      ],
    );
  }
}

// ─── Mini progress bar ────────────────────────────────────────────────────────

class _MiniBar extends StatelessWidget {
  final double pct;
  final Color color;
  const _MiniBar({required this.pct, required this.color});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: SizedBox(
      height: 6,
      child: Stack(
        children: [
          Container(color: const Color(0xFFF0F0F0)),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: pct.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 850),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Shift Pill ───────────────────────────────────────────────────────────────

class _ShiftPill extends StatelessWidget {
  final ShiftPillData pill;
  const _ShiftPill({required this.pill});

  @override
  Widget build(BuildContext context) {
    final bool empty = pill.total == 0;
    final bool complete = pill.isComplete;
    final bool started = pill.done > 0;

    // Colour reflects actual completion (a finished shift stays green even if
    // it's no longer the active window). The active shift is highlighted with
    // a live dot + ring instead of being greyed out.
    final Color fg = empty
        ? _pillInactiveFg
        : complete
        ? _pillGreenFg
        : started
        ? _pillYellowFg
        : _pillInactiveFg;
    final Color bg = empty
        ? _pillInactiveBg
        : complete
        ? _pillGreenBg
        : started
        ? _pillYellowBg
        : _pillInactiveBg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: pill.isActive
            ? Border.all(color: fg.withOpacity(0.55), width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pill.isActive) ...[
            _LiveDot(color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            pill.label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(width: 4),
          if (empty)
            Text(
              '\u2014',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            )
          else if (complete)
            Icon(Icons.check_rounded, size: 12, color: fg)
          else
            Text(
              '${(pill.pct * 100).round()}%',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Live (pulsing) dot — marks the currently-active shift ────────────────────

class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    ),
    child: Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;
  const _SectionHeader({required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: _red,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _black,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      if (onViewAll != null)
        GestureDetector(
          onTap: onViewAll,
          child: Text(
            'View All',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: _grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
    ],
  );
}

// ─── Outline Card ─────────────────────────────────────────────────────────────

class _OutlineCard extends StatelessWidget {
  final Widget child;
  final double? height;
  const _OutlineCard({required this.child, this.height});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFECECEC), width: 1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

// ─── Filled Card ──────────────────────────────────────────────────────────────

class _FilledCard extends StatelessWidget {
  final Widget child;
  final double? height;
  const _FilledCard({required this.child, this.height});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF161616), _black],
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: _black.withOpacity(0.22),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

// ─── Court Row ────────────────────────────────────────────────────────────────

class _CourtRow extends StatefulWidget {
  final dynamic court;
  final int index;
  const _CourtRow({required this.court, required this.index});

  @override
  State<_CourtRow> createState() => _CourtRowState();
}

class _CourtRowState extends State<_CourtRow>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _anim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _anim = CurvedAnimation(parent: _ctrl!, curve: Curves.easeOutCubic);
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _ctrl?.forward();
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim ?? const AlwaysStoppedAnimation(1.0),
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(_anim ?? const AlwaysStoppedAnimation(1.0)),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.selectionClick();
          context.push('/court/${widget.court.id}', extra: widget.court);
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFECECEC), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _lightGrey,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFECECEC)),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: _black,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.court.name ?? 'Court',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.court.location ?? 'Food Court',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _grey,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _black,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Active',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: _grey,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ─── Sparkline Painter ────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final Color color;
  const _SparklinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const pts = [0.55, 0.40, 0.65, 0.30, 0.70, 0.45, 0.35, 0.60, 0.50, 0.75];
    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final x = (i / (pts.length - 1)) * size.width;
      final y = size.height - (pts[i] * size.height);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Skeleton ─────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  final double width;
  final double height;
  final bool dark;
  const _Skeleton({
    required this.width,
    required this.height,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final box = SkeletonBox(width: width, height: height, radius: 8);
    return dark ? Shimmer(child: box) : Shimmer.light(child: box);
  }
}

// ─── Error Row ────────────────────────────────────────────────────────────────

class _ErrorRow extends StatelessWidget {
  final String message;
  const _ErrorRow({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border, width: 1.5),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
        const SizedBox(width: 10),
        Text(message, style: GoogleFonts.inter(fontSize: 13, color: _grey)),
      ],
    ),
  );
}
