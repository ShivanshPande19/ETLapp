// lib/features/home/presentation/outlet_home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../auth/domain/auth_notifier.dart';
import '../../notices/presentation/notice_bell.dart';
import '../../staff/presentation/view_roster_screen.dart';
import 'home_providers.dart';
import 'weekly_insights_screen.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/ui/motion.dart';
import '../../../core/ui/nav_visibility.dart'; // hide nav bar over full-screen report
import '../../outlets/presentation/outlet_switcher.dart'; // multi-outlet switcher

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
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
  }

  // Entrance motion is handled per-section by `StaggerIn`, which owns its own
  // controller. This screen used to run a 400 ms full-screen fade with a 900 ms
  // staggered reveal layered on top — so the last card landed about 1.1 s after
  // the tab was tapped, every single time. The sections now settle in roughly
  // 0.45 s, and nothing gates the header behind a fade.

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
      body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header (Dark Area) ──────────────────────────────────────
              StaggerIn(
                index: 0,
                child: _buildHeader(
                  firstName,
                  ref.watch(currentOutletNameProvider).value,
                ),
              ),

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
                        StaggerIn(
                          index: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: _sectionTitle(
                                        "Yesterday's Performance"),
                                  ),
                                  const Icon(
                                    Icons.show_chart_rounded,
                                    size: 16,
                                    color: _grey,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Skeleton dissolves into the loaded card rather
                              // than being swapped in a single frame.
                              MotionSwitcher(
                                child: dashboardState.when(
                                  loading: () => _skeletonCard(120),
                                  error: (_, __) =>
                                      _errorCard('Sales data unavailable'),
                                  data: (data) {
                                    final rev =
                                        (data['revenue'] as num).toDouble();
                                    final bills =
                                        (data['orders'] as num).toInt();
                                    final avg = bills > 0 ? rev / bills : 0.0;
                                    return _SalesCard(
                                      rev: rev,
                                      bills: bills,
                                      avg: avg,
                                      fmt: _fmt,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ─── 2. STAFF ROSTER (Now WIRED to DB) ────────────────
                        StaggerIn(
                          index: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle('Staff & Attendance'),
                              const SizedBox(height: 12),
                              Pressable(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.push(
                                    context,
                                    motionRoute(const ViewRosterScreen()),
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
                        StaggerIn(
                          index: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle('Weekly Highlights'),
                              const SizedBox(height: 12),
                              Pressable(
                                onTap: () async {
                                  HapticFeedback.selectionClick();
                                  // Hide the floating nav bar ONLY while the
                                  // full-screen report is open, and restore it
                                  // the moment we return. Doing it here (around
                                  // the push) is robust — show() always runs on
                                  // pop, unlike a dispose() hook which could be
                                  // skipped and leave the bar stuck hidden.
                                  final navBar =
                                      ref.read(navBarVisibleProvider.notifier);
                                  navBar.hide();
                                  await Navigator.push(
                                    context,
                                    motionRoute(
                                      const WeeklyInsightsScreen(),
                                    ),
                                  );
                                  navBar.show();
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
                // MULTI-OUTLET: renders nothing for single-outlet owners, so
                // there is zero UX change for them. Only a genuine multi-outlet
                // owner sees this switcher.
                const SizedBox(height: 14),
                const OutletSwitcher(),
              ],
            ),
          ),
          const NoticeBell(),
          const SizedBox(width: 10),
          _ProfileButton(firstName: firstName),
        ],
      ),
    );
  }

  // ─── Utils ─────────────────────────────────────────────────────────────────
  Widget _sectionTitle(String t) => Text(
    t,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
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

// Entrance wrapper, press-scale and the push route all now come from
// core/ui/motion.dart (StaggerIn / Pressable / motionRoute), so every screen
// shares one set of timings instead of three private copies.

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
            count: rev,
            format: (v) => '₹${fmt(v)}',
            icon: Icons.currency_rupee_rounded,
            color: _ok,
          ),
          _vDiv(),
          _StatBox(
            label: 'Total Bills',
            count: bills.toDouble(),
            format: (v) => v.round().toString(),
            icon: Icons.receipt_long_rounded,
            color: _blue,
          ),
          _vDiv(),
          _StatBox(
            label: 'Avg Bill',
            count: avg,
            format: (v) => '₹${fmt(v)}',
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
  final String label;

  /// The raw figure. Taken as a number rather than a pre-formatted string so
  /// it can count up to its value — a freshly loaded card used to snap from
  /// skeleton straight to a static number, which read as "nothing happened".
  final double count;

  /// Formats the in-flight value (currency symbol, K/L shortening, rounding).
  final String Function(double) format;

  final IconData icon;
  final Color color;
  const _StatBox({
    required this.label,
    required this.count,
    required this.format,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedCount(
          value: count,
          builder: (context, v) => Text(
            format(v),
            style: GoogleFonts.antonSc(
              fontSize: 22,
              color: _black,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: _grey,
                  fontWeight: FontWeight.w600,
                ),
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
    // Fair same-span growth (this week-to-date vs last week SAME days) from
    // /sales/compare — consistent with the Business Insights screen. best_day /
    // avg_bill still come from vendor/history below.
    final compareState = ref.watch(salesCompareProvider('week'));

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
                        'This week vs last week · same days',
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
                  final double growth = compareState.maybeWhen(
                    data: (c) => (c['growth_pct'] as num?)?.toDouble() ?? 0.0,
                    orElse: () => 0.0,
                  );

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
