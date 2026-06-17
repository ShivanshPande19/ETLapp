// lib/features/home/presentation/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
                            child: _OutlineCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Housekeeping',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _grey,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          _LegendDot(
                                            fg: _pillGreenFg,
                                            label: 'Done',
                                          ),
                                          const SizedBox(width: 8),
                                          _LegendDot(
                                            fg: _pillYellowFg,
                                            label: 'In progress',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (hkLoading) ...[
                                    const SizedBox(height: 14),
                                    ...List.generate(
                                      3,
                                      (_) => const Padding(
                                        padding: EdgeInsets.only(bottom: 10),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: _Skeleton(
                                                width: double.infinity,
                                                height: 14,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            _Skeleton(width: 52, height: 26),
                                            SizedBox(width: 5),
                                            _Skeleton(width: 52, height: 26),
                                            SizedBox(width: 5),
                                            _Skeleton(width: 52, height: 26),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ] else if (hkRows.isEmpty) ...[
                                    const SizedBox(height: 14),
                                    Text(
                                      'No submissions today',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: _grey,
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 12),
                                    ...hkRows.map(
                                      (row) => _CourtHkRow(row: row),
                                    ),
                                  ],
                                ],
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

// ─── Court HK Row ─────────────────────────────────────────────────────────────

class _CourtHkRow extends StatelessWidget {
  final CourtHkRow row;
  const _CourtHkRow({required this.row});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(
            row.courtName,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _black,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 8),
        _ShiftPill(pill: row.morning),
        const SizedBox(width: 5),
        _ShiftPill(pill: row.day),
        const SizedBox(width: 5),
        _ShiftPill(pill: row.night),
      ],
    ),
  );
}

// ─── Shift Pill ───────────────────────────────────────────────────────────────

class _ShiftPill extends StatelessWidget {
  final ShiftPillData pill;
  const _ShiftPill({required this.pill});

  bool _isShiftTimeActive(String label) {
    final h = TimeOfDay.now().hour;
    switch (label.toUpperCase()) {
      case 'M':
        return h >= 6 && h < 12;
      case 'D':
        return h >= 12 && h < 16;
      case 'N':
        return h >= 16 && h < 24;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = _isShiftTimeActive(pill.label);
    final Color fg = !isActive
        ? _pillInactiveFg
        : pill.isComplete
        ? _pillGreenFg
        : _pillYellowFg;
    final Color bg = !isActive
        ? _pillInactiveBg
        : pill.isComplete
        ? _pillGreenBg
        : _pillYellowBg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pill.label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 3),
            Text(
              '${(pill.pct * 100).round()}%',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ],
      ),
    );
  }
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
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _lightGrey,
                    shape: BoxShape.circle,
                    border: Border.all(color: _border.withOpacity(0.12)),
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
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: dark ? Colors.white.withOpacity(0.15) : _lightGrey,
      borderRadius: BorderRadius.circular(8),
    ),
  );
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
