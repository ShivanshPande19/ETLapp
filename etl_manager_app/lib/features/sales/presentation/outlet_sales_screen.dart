// lib/features/sales/presentation/outlet_sales_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/sales_notifier.dart';
import '../../home/presentation/home_providers.dart'; // ✅ Imported for Real Graph Data

// ─── Premium Palette ─────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _border = Color(0xFF1A1A1A);
const _ok = Color(0xFF22C55E);
const _blue = Color(0xFF60A5FA);
const _warn = Color(0xFFF59E0B);
const _accent = Color(0xFFDEFF9A); // Lime green

const _periodLabels = [
  'Yesterday',
  'This Week',
  'This Month',
  'This Year',
  'Custom',
];
const _periods = [
  SalesPeriod.yesterday,
  SalesPeriod.week,
  SalesPeriod.month,
  SalesPeriod.year,
  SalesPeriod.custom,
];

class OutletSalesScreen extends ConsumerStatefulWidget {
  const OutletSalesScreen({super.key});
  @override
  ConsumerState<OutletSalesScreen> createState() => _OutletSalesScreenState();
}

class _OutletSalesScreenState extends ConsumerState<OutletSalesScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _switchCtrl;

  late final Animation<double> _fadeAnim;
  late final Animation<double> _switchFade;
  late final Animation<Offset> _switchSlide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _fadeCtrl.forward();

    _switchCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _switchFade = CurvedAnimation(
      parent: _switchCtrl,
      curve: Curves.easeOutCubic,
    );
    _switchSlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _switchCtrl, curve: Curves.easeOutCubic));
    _switchCtrl.value = 1.0;
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _switchCtrl.dispose();
    super.dispose();
  }

  // Fade the analytics section in once when fresh data arrives.
  void _triggerFade() {
    _switchCtrl.forward(from: 0);
  }

  void _onPeriodTap(SalesPeriod period) async {
    if (period == SalesPeriod.custom) {
      final DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: DateTime.now().subtract(const Duration(days: 1)),
        firstDate: DateTime(2024),
        lastDate: DateTime.now(),
        builder: (ctx, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _accent,
              onPrimary: _black,
              surface: Color(0xFF1A1A1A),
              onSurface: _white,
            ),
          ),
          child: child!,
        ),
      );

      if (pickedDate == null || !mounted) return;
      HapticFeedback.selectionClick();

      final dateStr = pickedDate.toIso8601String().split('T').first;
      ref
          .read(salesNotifierProvider.notifier)
          .fetchSummary(
            period: SalesPeriod.custom,
            customDateFrom: dateStr,
            customDateTo: dateStr,
          );
    } else {
      HapticFeedback.selectionClick();
      ref.read(salesNotifierProvider.notifier).fetchSummary(period: period);
    }
  }

  String _fmtFull(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _periodLabel(SalesPeriod p, String? date) {
    switch (p) {
      case SalesPeriod.yesterday:
        return date ?? 'Yesterday';
      case SalesPeriod.week:
        return 'Current Week';
      case SalesPeriod.month:
        return 'Current Month';
      case SalesPeriod.year:
        return 'Annual Gross';
      case SalesPeriod.custom:
        return date ?? 'Selected Date';
    }
  }

  @override
  Widget build(BuildContext context) {
    final salesState = ref.watch(salesNotifierProvider);
    final summary = salesState.summary;
    final isLoading = salesState.status == SalesLoadStatus.loading;

    // ✅ Fade the analytics section in ONCE per real data change (via
    // ref.listen), NOT on every build. The old approach used
    // addPostFrameCallback in build + a self-resetting number animation, which
    // re-fired on each setState frame → infinite loop → cards faded out on
    // rapid chip switching.
    ref.listen<SalesState>(salesNotifierProvider, (prev, next) {
      if (next.status == SalesLoadStatus.loaded && next.summary != null) {
        _triggerFade();
      }
    });

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── FIXED IMMERSIVE DARK HEADER ───────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'FINANCIALS',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _grey,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _white.withOpacity(0.08)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.query_stats_rounded,
                                size: 14,
                                color: _accent,
                              ),
                              const SizedBox(width: 8),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Text(
                                  _periodLabel(
                                    salesState.period,
                                    summary?.date,
                                  ),
                                  key: ValueKey(
                                    '${salesState.period}_${summary?.date}',
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: _white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 50),

                    Text(
                      'GROSS REVENUE',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white54,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),

                    isLoading && summary == null
                        ? Container(
                            width: 220,
                            height: 70,
                            decoration: BoxDecoration(
                              color: _white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          )
                        : TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0,
                              end: summary?.totalSales ?? 0,
                            ),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (_, val, __) => Text(
                              '₹${_fmtFull(val)}',
                              style: GoogleFonts.antonSc(
                                fontSize: 78,
                                color: _white,
                                height: 1.0,
                                letterSpacing: -1.5,
                              ),
                            ),
                          ),
                  ],
                ),
              ),

              // ─── SCROLLABLE PREMIUM WHITE CANVAS (BUG FIXED) ───────────────
              Expanded(
                child: ClipRRect(
                  // ✅ FIX: ClipRRect add kiya taaki scrolling rounded corners ke bahar na nikle
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(40),
                  ),
                  child: Container(
                    width: double.infinity,
                    color: _white, // ✅ Background color
                    child: RefreshIndicator(
                      color: _black,
                      backgroundColor: _white,
                      strokeWidth: 2,
                      onRefresh: () async {
                        HapticFeedback.mediumImpact();
                        ref
                            .read(salesNotifierProvider.notifier)
                            .fetchSummary(
                              period: salesState.period,
                              customDateFrom: salesState.customDateFrom,
                              customDateTo: salesState.customDateTo,
                            );
                        ref.invalidate(weeklyInsightsProvider);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          0,
                          32,
                          0,
                          MediaQuery.of(context).padding.bottom + 120,
                        ),
                        children: [
                          // Time Configurator
                          SizedBox(
                            height: 40,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              itemCount: _periodLabels.length,
                              itemBuilder: (_, i) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _PeriodTab(
                                  label: _periodLabels[i],
                                  isSelected: salesState.period == _periods[i],
                                  onTap: () => _onPeriodTap(_periods[i]),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Core Analytics
                          FadeTransition(
                            opacity: _switchFade,
                            child: SlideTransition(
                              position: _switchSlide,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Performance Matrices',
                                      style: GoogleFonts.inter(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: _black,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 20),

                                    isLoading
                                        ? _PremiumSkeleton()
                                        : salesState.status ==
                                              SalesLoadStatus.error
                                        ? const _ErrorRow(
                                            message: 'Data Sync Failed',
                                          )
                                        : summary != null
                                        ? _VisualDataRings(
                                            bills: summary.totalBills,
                                            avgBill: summary.avgBillValue,
                                          )
                                        : const SizedBox.shrink(),

                                    const SizedBox(height: 24),

                                    // INTERACTIVE DYNAMIC GRAPH
                                    const _InteractiveTrendGraph(),
                                  ],
                                ),
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

// ─── Sleek Period Tabs ────────────────────────────────────────────────────────
class _PeriodTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _black : const Color(0xFFF9F9FB),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? _black : Colors.grey.shade200,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? _white : _grey,
          ),
        ),
      ),
    );
  }
}

// ─── Radial Visual Analytics Component ───────────────────────────────────────
class _VisualDataRings extends StatelessWidget {
  final int bills;
  final double avgBill;

  const _VisualDataRings({required this.bills, required this.avgBill});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // LEFT CARD: Volume (Bills)
        Expanded(
          child: Container(
            height: 190,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _black,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: _black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _blue.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: _blue,
                        size: 20,
                      ),
                    ),
                    Icon(
                      Icons.arrow_outward_rounded,
                      color: _white.withOpacity(0.3),
                      size: 16,
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: bills.toDouble()),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => Text(
                        val.toInt().toString(),
                        style: GoogleFonts.antonSc(
                          fontSize: 42,
                          color: _white,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Total Output',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),

        // RIGHT CARD: Quality (Avg Bill)
        Expanded(
          child: Container(
            height: 190,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.grey.shade200, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _warn.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.analytics_rounded,
                        color: _warn,
                        size: 20,
                      ),
                    ),
                    Icon(
                      Icons.arrow_outward_rounded,
                      color: _black.withOpacity(0.2),
                      size: 16,
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: avgBill),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => Text(
                        '₹${val.toStringAsFixed(0)}',
                        style: GoogleFonts.antonSc(
                          fontSize: 42,
                          color: _black,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Avg Ticket',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── INTERACTIVE 7-Day Trend Graph (LATEST ON RIGHT) ─────────────────────────
class _InteractiveTrendGraph extends ConsumerStatefulWidget {
  const _InteractiveTrendGraph();

  @override
  ConsumerState<_InteractiveTrendGraph> createState() =>
      _InteractiveTrendGraphState();
}

class _InteractiveTrendGraphState
    extends ConsumerState<_InteractiveTrendGraph> {
  int? _selectedIndex;

  String _formatDate(String iso) {
    try {
      DateTime dt = DateTime.parse(iso);
      String day = [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][dt.weekday - 1];
      String mon = [
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
      return "$day, $mon ${dt.day}";
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final insightsState = ref.watch(weeklyInsightsProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.grey.shade200, width: 2),
      ),
      child: insightsState.when(
        loading: () => const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator(color: _black)),
        ),
        error: (err, _) => const SizedBox(
          height: 160,
          child: Center(
            child: Text(
              "Graph data unavailable",
              style: TextStyle(color: _grey),
            ),
          ),
        ),
        data: (data) {
          List history = List.from(data['daily_history'] as List);

          if (history.isEmpty) return const SizedBox.shrink();

          // Find Max Sales
          double maxSales = 1.0;
          int peakIndex = 0;
          for (int i = 0; i < history.length; i++) {
            if ((history[i]['total_sales'] as num).toDouble() > maxSales) {
              maxSales = (history[i]['total_sales'] as num).toDouble();
              peakIndex = i; // Save exact peak index
            }
          }

          // Auto-select peak day on first load
          final activeIndex = _selectedIndex ?? peakIndex;

          // Fallback safe checking in case activeIndex is somehow out of bounds
          final activeData = (activeIndex >= 0 && activeIndex < history.length)
              ? history[activeIndex]
              : history.last;

          final activeSales = (activeData['total_sales'] as num).toDouble();
          final activeBills = activeData['total_bills'];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── DYNAMIC INFO PANEL ───
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '7-Day Trajectory',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _formatDate(activeData['date']),
                          key: ValueKey(activeData['date']),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _grey,
                          ),
                        ),
                      ),
                    ],
                  ),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(activeIndex),
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${activeSales.toStringAsFixed(0)}',
                          style: GoogleFonts.antonSc(
                            fontSize: 24,
                            color: _black,
                            height: 1.0,
                          ),
                        ),
                        Text(
                          '$activeBills Bills',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ─── INTERACTIVE BAR CHART ───
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: history.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var dayData = entry.value;

                  DateTime dt = DateTime.parse(dayData['date']);
                  String dayLetter = [
                    'M',
                    'T',
                    'W',
                    'T',
                    'F',
                    'S',
                    'S',
                  ][dt.weekday - 1];

                  double sales = (dayData['total_sales'] as num).toDouble();
                  double val = sales / maxSales;
                  if (val == 0) val = 0.05;

                  final isPeak = sales == maxSales && maxSales > 1;
                  final isSelected = idx == activeIndex;

                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedIndex = idx;
                      });
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isPeak)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _black,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PEAK',
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: _white,
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 18),

                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          width: isSelected ? 28 : 22,
                          height: 110 * val,
                          decoration: BoxDecoration(
                            color: isSelected ? _black : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: _black.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                        const SizedBox(height: 12),

                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected ? _black : _grey,
                          ),
                          child: Text(dayLetter),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Premium Skeleton Loader ─────────────────────────────────────────────────
class _PremiumSkeleton extends StatefulWidget {
  @override
  State<_PremiumSkeleton> createState() => _PremiumSkeletonState();
}

class _PremiumSkeletonState extends State<_PremiumSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final color = Color.lerp(
          const Color(0xFFF2F2F2),
          const Color(0xFFE5E5E5),
          _anim.value,
        )!;
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 190,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 190,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Fallback Error Card ─────────────────────────────────────────────────────
class _ErrorRow extends StatelessWidget {
  final String message;
  const _ErrorRow({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: const Color(0xFFEF4444).withOpacity(0.2),
        width: 1.5,
      ),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFEF4444),
          size: 20,
        ),
        const SizedBox(width: 12),
        Text(
          message,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: _grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
