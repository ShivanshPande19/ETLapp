// lib/features/home/presentation/outlet_home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../auth/domain/auth_notifier.dart';
import '../../staff/presentation/view_roster_screen.dart';
import 'home_providers.dart';
import 'weekly_insights_screen.dart';
import '../../../core/widgets/skeleton.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);
const _blue = Color(0xFF60A5FA);
const _purple = Color(0xFFA78BFA);
const _red = Color(0xFFd02128);

class OutletHomeScreen extends ConsumerStatefulWidget {
  const OutletHomeScreen({super.key});

  @override
  ConsumerState<OutletHomeScreen> createState() => _OutletHomeScreenState();
}

class _OutletHomeScreenState extends ConsumerState<OutletHomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final AnimationController _listCtrl;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();

    // Staggered entrance for the content sections (replays on every tab switch).
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _listCtrl.forward();
  }

  // Per-section staggered fade+slide animation.
  Animation<double> _itemAnim(int i) => CurvedAnimation(
    parent: _listCtrl,
    curve: Interval(
      (i * 0.15).clamp(0.0, 0.6),
      ((i * 0.15) + 0.5).clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final firstName = (authState.managerName ?? 'Manager').split(' ').first;

    // Real Data fetching from API
    final dashboardState = ref.watch(outletDashboardProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header (Dark Area) ──────────────────────────────────────
              _buildHeader(firstName, ref.watch(currentOutletNameProvider).value),

              // ─── White Card Area ─────────────────────────────────────────
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
                    onRefresh: () async {
                      HapticFeedback.mediumImpact();
                      // Refresh all 3 dynamic sections
                      ref.invalidate(outletDashboardProvider);
                      ref.invalidate(dailyRosterProvider);
                      ref.invalidate(weeklyInsightsProvider);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        20,
                        28,
                        20,
                        MediaQuery.of(context).padding.bottom + 100,
                      ),
                      children: [
                        // ─── 1. REAL SALES DATA ─────────────────────────────
                        _Stagger(
                          anim: _itemAnim(0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _sectionTitle("Yesterday's Performance"),
                                  const Icon(
                                    Icons.show_chart_rounded,
                                    size: 16,
                                    color: _grey,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              dashboardState.when(
                                loading: () => _skeletonCard(120),
                                error: (_, __) =>
                                    _errorCard('Sales data unavailable'),
                                data: (data) {
                                  final rev = (data['revenue'] as num)
                                      .toDouble();
                                  final bills = (data['orders'] as num).toInt();
                                  final avg = bills > 0 ? rev / bills : 0.0;
                                  return _SalesCard(
                                    rev: rev,
                                    bills: bills,
                                    avg: avg,
                                    fmt: _fmt,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ─── 2. STAFF ROSTER (Now WIRED to DB) ────────────────
                        _Stagger(
                          anim: _itemAnim(1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle('Staff & Attendance'),
                              const SizedBox(height: 12),
                              _PressableScale(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.push(
                                    context,
                                    _fadeSlideRoute(const ViewRosterScreen()),
                                  );
                                },
                                child: AbsorbPointer(
                                  child: _StaffRosterCard(onTap: () {}),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ─── 3. BUSINESS INSIGHTS (Now WIRED to DB) ───────────
                        _Stagger(
                          anim: _itemAnim(2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle('Weekly Highlights'),
                              const SizedBox(height: 12),
                              _PressableScale(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.push(
                                    context,
                                    _fadeSlideRoute(
                                      const WeeklyInsightsScreen(),
                                    ),
                                  );
                                },
                                child: AbsorbPointer(
                                  child: _ReportsCard(onTap: () {}),
                                ),
                              ),
                            ],
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

  // ─── Header UI ─────────────────────────────────────────────────────────────
  Widget _buildHeader(String firstName, String? outletName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HELLO, ${firstName.toUpperCase()}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _grey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // ✅ Real outlet name; neutral fallback while loading (no fake).
                  (outletName != null && outletName.isNotEmpty)
                      ? outletName
                      : 'My Outlet',
                  style: GoogleFonts.antonSc(
                    fontSize: 38,
                    color: _white,
                    letterSpacing: -0.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
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
                    const SizedBox(width: 4),
                    Text(
                      'Active',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _ok,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _ProfileButton(firstName: firstName),
        ],
      ),
    );
  }

  // ─── Utils ─────────────────────────────────────────────────────────────────
  Widget _sectionTitle(String t) => Text(
    t,
    style: GoogleFonts.inter(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: _black,
      letterSpacing: -0.2,
    ),
  );

  Widget _skeletonCard(double h) => Shimmer.light(
    child: SkeletonBox(height: h, radius: 18),
  );

  Widget _errorCard(String msg) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _danger.withOpacity(0.15), width: 1.5),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: _warn),
        const SizedBox(width: 8),
        Text(msg, style: GoogleFonts.inter(fontSize: 13, color: _grey)),
      ],
    ),
  );
}

// ─── Staggered entrance wrapper (fade + slide-up) ───────────────────────────
class _Stagger extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  const _Stagger({required this.anim, required this.child});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }
}

// ─── Smooth fade + slide route (for pushed screens) ─────────────────────────
Route _fadeSlideRoute(Widget page) {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
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
  );
}

// ─── Reusable press-scale wrapper (tactile tap feedback) ────────────────────
class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PressableScale({required this.child, required this.onTap});

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

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
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ─── Profile Button (Animated) ──────────────────────────────────────────────
class _ProfileButton extends StatefulWidget {
  final String firstName;
  const _ProfileButton({required this.firstName});

  @override
  State<_ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends State<_ProfileButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
              widget.firstName.isNotEmpty
                  ? widget.firstName[0].toUpperCase()
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
    );
  }
}

// ─── Sales Card (Real Data) ─────────────────────────────────────────────────
class _SalesCard extends StatelessWidget {
  final double rev;
  final int bills;
  final double avg;
  final String Function(double) fmt;
  const _SalesCard({
    required this.rev,
    required this.bills,
    required this.avg,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return _AppCard(
      child: Row(
        children: [
          _StatBox(
            label: 'Revenue',
            value: '₹${fmt(rev)}',
            icon: Icons.currency_rupee_rounded,
            color: _ok,
          ),
          _vDiv(),
          _StatBox(
            label: 'Total Bills',
            value: '$bills',
            icon: Icons.receipt_long_rounded,
            color: _blue,
          ),
          _vDiv(),
          _StatBox(
            label: 'Avg Bill',
            value: '₹${fmt(avg)}',
            icon: Icons.analytics_outlined,
            color: _warn,
          ),
        ],
      ),
    );
  }

  Widget _vDiv() => Container(
    width: 1,
    height: 40,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: Colors.grey.shade100,
  );
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.antonSc(fontSize: 22, color: _black, height: 1.0),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 4),
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
      ],
    ),
  );
}

// ─── Staff Roster Card (Now Wired to DB) ────────────────────────────────────
class _StaffRosterCard extends ConsumerWidget {
  final VoidCallback onTap;
  const _StaffRosterCard({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterState = ref.watch(dailyRosterProvider);

    return GestureDetector(
      onTap: onTap,
      child: _AppCard(
        child: rosterState.when(
          loading: () => Shimmer.light(
            child: Column(
              children: const [
                SkeletonTile(height: 52),
                SkeletonTile(height: 52),
              ],
            ),
          ),
          error: (_, __) => const SizedBox(
            height: 120,
            child: Center(
              child: Text(
                'Failed to load roster',
                style: TextStyle(color: _grey),
              ),
            ),
          ),
          data: (data) {
            final total = data['total_staff'] as int;
            final present = data['present_count'] as int;
            final pct = total > 0 ? present / total : 0.0;
            final staffList = data['staff_list'] as List;

            // Generate avatar names dynamically from present staff
            final presentStaff = staffList
                .where((s) => s['status'].toString().toLowerCase() == 'present')
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.people_alt_rounded,
                        color: _blue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$present Active Staff',
                            style: GoogleFonts.antonSc(
                              fontSize: 20,
                              color: _black,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Out of $total scheduled today',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Mini avatar stack built from real data
                    SizedBox(
                      width: 50,
                      height: 28,
                      child: Stack(
                        children: [
                          if (presentStaff.isNotEmpty)
                            Positioned(
                              right: 20,
                              child: _miniAvatar(
                                'https://ui-avatars.com/api/?name=${presentStaff[0]['name']}&background=8B5CF6&color=fff&format=png',
                              ),
                            ),
                          if (presentStaff.length > 1)
                            Positioned(
                              right: 10,
                              child: _miniAvatar(
                                'https://ui-avatars.com/api/?name=${presentStaff[1]['name']}&background=3B82F6&color=fff&format=png',
                              ),
                            ),
                          if (presentStaff.length > 2)
                            Positioned(
                              right: 0,
                              child: _miniAvatar(
                                'https://ui-avatars.com/api/?name=${presentStaff[2]['name']}&background=10B981&color=fff&format=png',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: const AlwaysStoppedAnimation<Color>(_ok),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _black,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.list_alt_rounded,
                        size: 16,
                        color: _white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'View Roster',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _miniAvatar(String url) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: _white, width: 2),
      image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
    ),
  );
}

// ─── Detailed Reports Card (Now Wired to DB) ────────────────────────────────
class _ReportsCard extends ConsumerWidget {
  final VoidCallback onTap;
  const _ReportsCard({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsState = ref.watch(weeklyInsightsProvider);

    return GestureDetector(
      onTap: onTap,
      child: _AppCard(
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.trending_up_rounded,
                    color: _purple,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '7-Day Revenue Trend',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Compare this week vs last week',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _grey),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: insightsState.when(
                loading: () => Shimmer.light(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonLine(width: 150, height: 13),
                        SizedBox(height: 14),
                        SkeletonBox(height: 78, radius: 12),
                      ],
                    ),
                  ),
                ),
                error: (_, __) => const Center(
                  child: Text(
                    "Data unavailable",
                    style: TextStyle(color: _grey, fontSize: 12),
                  ),
                ),
                data: (data) {
                  final weekTotal = (data['week_total'] as num).toDouble();
                  final lastWeekTotal = (data['last_week_total'] as num)
                      .toDouble();

                  double growth = 0.0;
                  if (lastWeekTotal > 0) {
                    growth =
                        ((weekTotal - lastWeekTotal) / lastWeekTotal) * 100;
                  } else if (weekTotal > 0) {
                    growth = 100.0;
                  }

                  final growthStr = growth >= 0
                      ? '+${growth.toStringAsFixed(1)}%'
                      : '${growth.toStringAsFixed(1)}%';
                  final growthColor = growth >= 0 ? _ok : _danger;

                  String bestDayStr = "N/A";
                  if (data['best_day'] != null &&
                      data['best_day'].toString().isNotEmpty) {
                    try {
                      DateTime parsed = DateTime.parse(data['best_day']);
                      bestDayStr = [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ][parsed.weekday - 1];
                    } catch (_) {}
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _ReportMiniStat(
                        icon: growth >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        label: 'Growth',
                        value: growthStr,
                        color: growthColor,
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.grey.shade200,
                      ),
                      _ReportMiniStat(
                        icon: Icons.star_rounded,
                        label: 'Best Day',
                        value: bestDayStr,
                        color: _blue,
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.grey.shade200,
                      ),
                      _ReportMiniStat(
                        icon: Icons.receipt_long_rounded,
                        label: 'Avg Bill',
                        value:
                            '₹${(data['avg_bill_value'] as num).toStringAsFixed(0)}',
                        color: _warn,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportMiniStat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _ReportMiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _black,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: _grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Base Card UI ────────────────────────────────────────────────────────────
class _AppCard extends StatelessWidget {
  final Widget child;
  const _AppCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE8E8E6), width: 1.2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}
