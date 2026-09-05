// lib/features/home/presentation/weekly_insights_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/ui/nav_visibility.dart';

import 'home_providers.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _blue = Color(0xFF60A5FA);
const _danger = Color(0xFFEF4444);

// Granularity options for the this-vs-last comparison.
const _granKeys = ['week', 'month', 'year'];
const _granTabs = ['Week', 'Month', 'Year'];

class WeeklyInsightsScreen extends ConsumerStatefulWidget {
  const WeeklyInsightsScreen({super.key});

  @override
  ConsumerState<WeeklyInsightsScreen> createState() =>
      _WeeklyInsightsScreenState();
}

class _WeeklyInsightsScreenState extends ConsumerState<WeeklyInsightsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  // Selected comparison granularity: "week" | "month" | "year".
  String _gran = 'week';

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();

    // Hide the floating bottom nav bar while this full-screen report is open
    // (mirrors the outlet-switcher pattern). Restored in dispose().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(navBarVisibleProvider.notifier).hide();
    });
  }

  @override
  void dispose() {
    // Bring the nav bar back when leaving the report.
    ref.read(navBarVisibleProvider.notifier).show();
    _animCtrl.dispose();
    super.dispose();
  }

  String get _periodWord => _gran; // "week" | "month" | "year"

  double _num(dynamic v) => v is num ? v.toDouble() : 0.0;

  @override
  Widget build(BuildContext context) {
    final compareState = ref.watch(salesCompareProvider(_gran));

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ─── Header ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: _white.withOpacity(0.1)),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: _white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Business Insights',
                          style: GoogleFonts.antonSc(
                            fontSize: 24,
                            color: _white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'This $_periodWord vs last $_periodWord',
                          style: GoogleFonts.inter(fontSize: 12, color: _grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ─── Granularity toggle (Week / Month / Year) ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _GranToggle(
                selected: _gran,
                onChanged: (g) {
                  if (g == _gran) return;
                  HapticFeedback.selectionClick();
                  setState(() => _gran = g);
                },
              ),
            ),

            // ─── White Scrollable Content ───
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: compareState.when(
                  loading: () => const SkeletonList(
                    dark: false,
                    count: 4,
                    tileHeight: 80,
                  ),
                  error: (err, _) => Center(
                    child: Text(
                      "Error fetching insights",
                      style: TextStyle(color: _danger),
                    ),
                  ),
                  data: (data) {
                    final currentLabel =
                        (data['current_label'] ?? 'This $_periodWord').toString();
                    final previousLabel =
                        (data['previous_label'] ?? 'Last $_periodWord').toString();
                    final currentTotal = _num(data['current_total']);
                    final previousTotal = _num(data['previous_total']);
                    final currentBills = (data['current_bills'] ?? 0);
                    final previousBills = (data['previous_bills'] ?? 0);
                    final growth = _num(data['growth_pct']);
                    final isPositive = growth >= 0;
                    final growthStr = isPositive
                        ? '+${growth.toStringAsFixed(1)}%'
                        : '${growth.toStringAsFixed(1)}%';

                    final points = (data['points'] as List? ?? [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();

                    return FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            32,
                            20,
                            MediaQuery.of(context).padding.bottom + 40,
                          ),
                          physics: const BouncingScrollPhysics(),
                          children: [
                            // ─── Headline growth (fair, same-span) ───
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  growthStr,
                                  style: GoogleFonts.antonSc(
                                    fontSize: 56,
                                    color: isPositive ? _ok : _danger,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'vs last $_periodWord',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Crystal-clear statement of exactly what's compared
                            // (same number of days, so it's apples-to-apples).
                            Text(
                              'Comparing $currentLabel against $previousLabel — the same number of days, so it\'s a fair like-for-like comparison.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _black.withOpacity(0.7),
                                height: 1.4,
                              ),
                            ),

                            const SizedBox(height: 28),

                            // ─── This vs Last totals ───
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniMetricCard(
                                    title: 'This $_periodWord',
                                    value: _fmtMoney(currentTotal),
                                    subtitle: '$currentBills bills',
                                    icon: Icons.trending_up_rounded,
                                    color: _ok,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _MiniMetricCard(
                                    title: 'Last $_periodWord',
                                    value: _fmtMoney(previousTotal),
                                    subtitle: '$previousBills bills (same days)',
                                    icon: Icons.history_rounded,
                                    color: _blue,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 36),

                            // ─── Side-by-side comparison chart ───
                            Text(
                              _gran == 'week'
                                  ? 'Day-by-day: this week vs last week'
                                  : _gran == 'month'
                                      ? 'Week-by-week: this month vs last month'
                                      : 'Month-by-month: this year vs last year',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _black,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _CompareBarChart(points: points),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtMoney(double v) {
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)}L';
  if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
  return '₹${v.toStringAsFixed(0)}';
}

// ─── Granularity toggle ───
class _GranToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _GranToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _white.withOpacity(0.08)),
      ),
      child: Row(
        children: List.generate(_granKeys.length, (i) {
          final key = _granKeys[i];
          final isSel = key == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(key),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSel ? _white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _granTabs[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSel ? _black : _grey,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Mini Metric Card ───
class _MiniMetricCard extends StatelessWidget {
  final String title, value, subtitle;
  final IconData icon;
  final Color color;

  const _MiniMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.antonSc(
              fontSize: 24,
              color: _black,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _grey,
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: _grey.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grouped comparison bar chart (current vs previous per aligned bucket) ───
class _CompareBarChart extends StatefulWidget {
  final List<Map<String, dynamic>> points;
  const _CompareBarChart({required this.points});

  @override
  State<_CompareBarChart> createState() => _CompareBarChartState();
}

class _CompareBarChartState extends State<_CompareBarChart> {
  int? _selectedIndex;

  double _n(dynamic v) => v is num ? v.toDouble() : 0.0;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('No data yet', style: TextStyle(color: _grey)),
        ),
      );
    }

    double maxVal = 1.0;
    for (final p in points) {
      final c = _n(p['current_sales']);
      final pr = _n(p['previous_sales']);
      if (c > maxVal) maxVal = c;
      if (pr > maxVal) maxVal = pr;
    }

    final activeIndex = (_selectedIndex != null &&
            _selectedIndex! >= 0 &&
            _selectedIndex! < points.length)
        ? _selectedIndex!
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend + selected-bucket detail
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _legendDot(_ok, 'This'),
                  const SizedBox(width: 14),
                  _legendDot(_white.withOpacity(0.25), 'Last'),
                ],
              ),
              if (activeIndex != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${points[activeIndex]['label']}',
                      style: GoogleFonts.inter(fontSize: 11, color: _grey),
                    ),
                    Text(
                      '${_fmtMoney(_n(points[activeIndex]['current_sales']))}  vs  ${_fmtMoney(_n(points[activeIndex]['previous_sales']))}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _white,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points.asMap().entries.map<Widget>((entry) {
                final idx = entry.key;
                final p = entry.value;
                final cur = _n(p['current_sales']);
                final prev = _n(p['previous_sales']);
                double cv = cur / maxVal;
                double pv = prev / maxVal;
                if (cv < 0) cv = 0;
                if (pv < 0) pv = 0;
                final isSel = idx == activeIndex;

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedIndex = isSel ? null : idx);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _bar(90 * cv, _ok, isSel),
                            const SizedBox(width: 3),
                            _bar(90 * pv, _white.withOpacity(0.25), isSel),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${p['label']}',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight:
                                isSel ? FontWeight.w800 : FontWeight.w600,
                            color: isSel ? _white : _grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(double height, Color color, bool highlight) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 9,
      height: height < 2 ? 2 : height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        boxShadow: highlight
            ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)]
            : [],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _grey,
          ),
        ),
      ],
    );
  }
}
