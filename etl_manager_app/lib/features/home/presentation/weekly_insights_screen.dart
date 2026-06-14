// lib/features/home/presentation/weekly_insights_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insightsState = ref.watch(weeklyInsightsProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ─── Header ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                          'Weekly Performance Report',
                          style: GoogleFonts.inter(fontSize: 12, color: _grey),
                        ),
                      ],
                    ),
                  ),
                ],
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
                child: insightsState.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: _black),
                  ),
                  error: (err, _) => Center(
                    child: Text(
                      "Error fetching insights",
                      style: TextStyle(color: _danger),
                    ),
                  ),
                  data: (data) {
                    // 1. Calculations
                    final weekTotal = (data['week_total'] as num).toDouble();
                    final lastWeekTotal = (data['last_week_total'] as num)
                        .toDouble();
                    double growth = 0.0;
                    if (lastWeekTotal > 0)
                      growth =
                          ((weekTotal - lastWeekTotal) / lastWeekTotal) * 100;
                    else if (weekTotal > 0)
                      growth = 100.0;
                    final growthStr = growth >= 0
                        ? '+${growth.toStringAsFixed(1)}%'
                        : '${growth.toStringAsFixed(1)}%';
                    final isPositive = growth >= 0;

                    // Parse Best Day
                    String bestDayStr = "N/A";
                    String bestDayFull = "N/A";
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
                        bestDayFull = [
                          'Monday',
                          'Tuesday',
                          'Wednesday',
                          'Thursday',
                          'Friday',
                          'Saturday',
                          'Sunday',
                        ][parsed.weekday - 1];
                      } catch (_) {}
                    }

                    // Process Daily History for Chart & List
                    List history = (data['daily_history'] as List).reversed
                        .toList(); // Reverse to show oldest to newest left to right
                    double maxSales = 1.0; // Avoid Div/0
                    for (var h in history) {
                      if ((h['total_sales'] as num).toDouble() > maxSales) {
                        maxSales = (h['total_sales'] as num).toDouble();
                      }
                    }

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
                            // ─── Highlight Section ───
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
                                    'Growth WoW',
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
                            Text(
                              isPositive
                                  ? 'Your outlet is performing great, outperforming the previous week.'
                                  : 'Revenue is slightly lower compared to last week. Monitor peak hours.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _black.withOpacity(0.7),
                                height: 1.4,
                              ),
                            ),

                            const SizedBox(height: 36),

                            // ─── Mini Metrics Grid ───
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniMetricCard(
                                    title: 'Best Day',
                                    value: bestDayStr,
                                    subtitle: 'Top Performer',
                                    icon: Icons.star_rounded,
                                    color: _blue,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _MiniMetricCard(
                                    title: 'Avg Bill',
                                    value:
                                        '₹${(data['avg_bill_value'] as num).toStringAsFixed(0)}',
                                    subtitle: 'Stable Value',
                                    icon: Icons.receipt_long_rounded,
                                    color: _warn,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 36),

                            // ─── 7-Day Chart (Dynamic Data) ───
                            Text(
                              '7-Day Revenue Trend',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _black,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _PremiumDynamicBarChart(
                              history: history,
                              maxSales: maxSales,
                              bestDayFull: bestDayFull,
                            ),

                            const SizedBox(height: 36),

                            // ─── Daily Breakdown List ───
                            Text(
                              'Daily Breakdown',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _black,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Reversing again to show newest day at the top of the list
                            ...history.reversed.map((dayData) {
                              DateTime dt = DateTime.parse(dayData['date']);
                              String dName = [
                                'Mon',
                                'Tue',
                                'Wed',
                                'Thu',
                                'Fri',
                                'Sat',
                                'Sun',
                              ][dt.weekday - 1];
                              String dMonth = [
                                'Jan',
                                'Feb',
                                'Mar',
                                'Apr',
                                'May',
                                'Jun',
                                'Jul',
                                'Aug',
                                'Sep',
                                'Oct',
                                'Nov',
                                'Dec',
                              ][dt.month - 1];

                              return _DailyRow(
                                day: dName,
                                date: '$dMonth ${dt.day}',
                                rev:
                                    '₹${(dayData['total_sales'] as num).toStringAsFixed(0)}',
                                bills: '${dayData['total_bills']} bills',
                                isPeak: dayData['date'] == data['best_day'],
                              );
                            }).toList(),
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

// ─── Custom Dynamic Bar Chart ───
class _PremiumDynamicBarChart extends StatelessWidget {
  final List history;
  final double maxSales;
  final String bestDayFull;

  const _PremiumDynamicBarChart({
    required this.history,
    required this.maxSales,
    required this.bestDayFull,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _black,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: history.map((e) {
          DateTime dt = DateTime.parse(e['date']);
          String dayLetter = [
            'M',
            'T',
            'W',
            'T',
            'F',
            'S',
            'S',
          ][dt.weekday - 1];
          double val = (e['total_sales'] as num) / maxSales;
          if (val == 0)
            val = 0.05; // Make sure bar doesn't completely disappear

          final isPeak = (e['total_sales'] as num) == maxSales && maxSales > 1;

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isPeak)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _ok.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'PEAK',
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: _ok,
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                width: 28,
                height: 100 * val,
                decoration: BoxDecoration(
                  color: isPeak ? _ok : _white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                dayLetter,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isPeak ? FontWeight.w800 : FontWeight.w600,
                  color: isPeak ? _white : _grey,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─── Daily List Row ───
class _DailyRow extends StatelessWidget {
  final String day, date, rev, bills;
  final bool isPeak;

  const _DailyRow({
    required this.day,
    required this.date,
    required this.rev,
    required this.bills,
    this.isPeak = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPeak ? _ok.withOpacity(0.3) : Colors.grey.shade200,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPeak ? _ok.withOpacity(0.1) : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPeak ? Icons.star_rounded : Icons.calendar_today_rounded,
              size: 18,
              color: isPeak ? _ok : _grey,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _black,
                  ),
                ),
                Text(
                  date,
                  style: GoogleFonts.inter(fontSize: 12, color: _grey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rev,
                style: GoogleFonts.antonSc(
                  fontSize: 20,
                  color: isPeak ? _ok : _black,
                  height: 1.0,
                ),
              ),
              Text(bills, style: GoogleFonts.inter(fontSize: 11, color: _grey)),
            ],
          ),
        ],
      ),
    );
  }
}
