import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../courts/domain/courts_notifier.dart';
import '../data/sales_repository.dart';
import '../domain/sales_notifier.dart';
import 'vendor_detail_sheet.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _lightGrey = Color(0xFFF2F2F2);
// Premium accents (subtle — not loud)
const _accent = Color(0xFF22C55E); // emerald — revenue/positive (matches app)
const _cardBorder = Color(0xFFECECEC); // soft light border for premium cards

// ── Period config ─────────────────────────────────────────────────────────────

const _periodLabels = ['Yesterday', 'Week', 'Month', 'Year', 'Custom'];
const _periods = [
  SalesPeriod.yesterday,
  SalesPeriod.week,
  SalesPeriod.month,
  SalesPeriod.year,
  SalesPeriod.custom,
];

// ── Screen ────────────────────────────────────────────────────────────────────

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});
  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen>
    with TickerProviderStateMixin {
  AnimationController? _fadeCtrl;
  AnimationController? _switchCtrl;

  Animation<double>? _fadeAnim;
  Animation<double>? _switchFade;
  Animation<Offset>? _switchSlide;

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
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl!, curve: Curves.easeOutCubic);
    _fadeCtrl!.forward();

    _switchCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _switchFade = CurvedAnimation(
      parent: _switchCtrl!,
      curve: Curves.easeOutCubic,
    );
    _switchSlide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _switchCtrl!, curve: Curves.easeOutCubic),
        );
    _switchCtrl!.value = 1.0;
  }

  @override
  void dispose() {
    _fadeCtrl?.dispose();
    _switchCtrl?.dispose();
    super.dispose();
  }

  // ── Period change — triggers content fade ─────────────────────────────────

  void _onPeriodTap(SalesPeriod period, int? courtId) async {
    if (period == SalesPeriod.custom) {
      final DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: DateTime.now().subtract(const Duration(days: 1)),
        firstDate: DateTime(2024),
        lastDate: DateTime.now(),
        builder: (ctx, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _white,
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
            courtId: courtId,
            period: SalesPeriod.custom,
            customDateFrom: dateStr,
            customDateTo: dateStr,
          );
    } else {
      HapticFeedback.selectionClick();
      ref
          .read(salesNotifierProvider.notifier)
          .fetchSummary(courtId: courtId, period: period);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _timeAgo(String iso) {
    try {
      final diff = DateTime.now().difference(DateTime.parse(iso));
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    } catch (_) {
      return iso;
    }
  }

  String _fmtFull(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _periodLabel(SalesPeriod p, String? date) {
    switch (p) {
      case SalesPeriod.yesterday:
        return date ?? 'Yesterday';
      case SalesPeriod.week:
        return 'This Week';
      case SalesPeriod.month:
        return 'This Month';
      case SalesPeriod.year:
        return 'This Year';
      case SalesPeriod.custom:
        return date ?? 'Custom Date';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final salesState = ref.watch(salesNotifierProvider);
    final courtsAsync = ref.watch(courtsNotifierProvider);
    final summary = salesState.summary;
    final isLoading = salesState.status == SalesLoadStatus.loading;
    final repo = ref.read(salesRepositoryProvider);

    // ✅ Fade the content in once per real data change (no postFrame loop /
    // vestigial number animation — that pattern caused the fade glitch).
    ref.listen<SalesState>(salesNotifierProvider, (prev, next) {
      if (next.status == SalesLoadStatus.loaded && next.summary != null) {
        _switchCtrl?.forward(from: 0);
      }
    });

    return Scaffold(
      backgroundColor: _black,
      body: FadeTransition(
        opacity: _fadeAnim ?? const AlwaysStoppedAnimation(1.0),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Fixed Black Header (does NOT scroll) ─────────────────────
              Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Sales',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: Colors.white54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                key: ValueKey(
                                  '${salesState.period}_${summary?.date}',
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_rounded,
                                      size: 12,
                                      color: Colors.white.withOpacity(0.6),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _periodLabel(
                                        salesState.period,
                                        summary?.date,
                                      ),
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Text(
                          'Total Sales',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),

                        isLoading && summary == null
                            ? Container(
                                width: 180,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              )
                            : TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  begin: 0,
                                  end: summary?.totalSales ?? 0,
                                ),
                                duration: const Duration(milliseconds: 700),
                                curve: Curves.easeOutCubic,
                                builder: (_, val, __) => Text(
                                  '₹${_fmtFull(val)}',
                                  style: GoogleFonts.antonSc(
                                    fontSize: 52,
                                    color: _white,
                                    height: 1,
                                  ),
                                ),
                              ),
                        const SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _AnimatedHeaderStat(
                              label: 'Bills',
                              value: '${summary?.totalBills ?? 0}',
                            ),
                            Container(
                              width: 1,
                              height: 28,
                              color: Colors.white.withOpacity(0.15),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                            ),
                            _AnimatedHeaderStat(
                              label: 'Avg Bill',
                              value:
                                  '₹${(summary?.avgBillValue ?? 0).toStringAsFixed(0)}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

              // ── Fixed white sheet; only its content scrolls ──────────────
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    child: RefreshIndicator(
                      color: _black,
                      backgroundColor: _white,
                      strokeWidth: 2,
                      onRefresh: () => ref
                          .read(salesNotifierProvider.notifier)
                          .fetchSummary(
                            courtId: salesState.selectedCourtId,
                            period: salesState.period,
                            customDateFrom: salesState.customDateFrom,
                            customDateTo: salesState.customDateTo,
                          ),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 28),

                      // ── Court Tabs ──────────────────────────────────
                      courtsAsync.when(
                        loading: () => const SizedBox(height: 44),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (courts) => _CourtTabs(
                          courts: courts,
                          selectedCourtId: salesState.selectedCourtId,
                          onSelect: (id) {
                            HapticFeedback.selectionClick();
                            ref
                                .read(salesNotifierProvider.notifier)
                                .fetchSummary(
                                  courtId: id,
                                  period: salesState.period,
                                  customDateFrom: salesState.customDateFrom,
                                  customDateTo: salesState.customDateTo,
                                );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Period Tabs ───────────────────
                      SizedBox(
                        height: 36,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _periodLabels.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _PeriodTab(
                              label: _periodLabels[i],
                              isSelected: salesState.period == _periods[i],
                              onTap: () => _onPeriodTap(
                                _periods[i],
                                salesState.selectedCourtId,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Animated content area ───────────────────────
                      FadeTransition(
                        opacity:
                            _switchFade ?? const AlwaysStoppedAnimation(1.0),
                        child: SlideTransition(
                          position:
                              _switchSlide ??
                              const AlwaysStoppedAnimation(Offset.zero),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Trend chart (period + court scoped) ──
                              if (salesState.status !=
                                  SalesLoadStatus.error) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _SalesTrendChart(
                                    trend: salesState.trend,
                                    period: salesState.period,
                                    loading:
                                        isLoading && salesState.trend == null,
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],

                              // ── Body: error / loading / empty / content ──
                              if (salesState.status == SalesLoadStatus.error)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _SalesErrorState(
                                    onRetry: () => ref
                                        .read(salesNotifierProvider.notifier)
                                        .fetchSummary(
                                          courtId: salesState.selectedCourtId,
                                          period: salesState.period,
                                          customDateFrom:
                                              salesState.customDateFrom,
                                          customDateTo: salesState.customDateTo,
                                        ),
                                  ),
                                )
                              else if (isLoading && summary == null) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _BentoSkeleton(),
                                ),
                                const SizedBox(height: 20),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: Column(
                                    children: List.generate(
                                      3,
                                      (i) => const Padding(
                                        padding: EdgeInsets.only(bottom: 10),
                                        child: _SkeletonBox(height: 90),
                                      ),
                                    ),
                                  ),
                                ),
                              ] else if (summary == null ||
                                  summary.vendors.isEmpty ||
                                  summary.totalSales <= 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _SalesEmptyState(
                                    courtSelected:
                                        salesState.selectedCourtId != null,
                                    hasOutlets: summary != null &&
                                        summary.vendors.isNotEmpty,
                                    periodLabel: _periodLabel(
                                      salesState.period,
                                      summary?.date,
                                    ),
                                  ),
                                )
                              else ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: Text(
                                    'Vendor Breakdown',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: _black,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _VendorBentoGrid(
                                    vendors: summary.vendors,
                                    total: summary.totalSales,
                                    courtId: salesState.selectedCourtId ?? 1,
                                    repo: repo,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: Text(
                                    'Vendors',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: _black,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...summary.vendors.asMap().entries.map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      0,
                                      20,
                                      10,
                                    ),
                                    child: _VendorRow(
                                      vendor: e.value,
                                      total: summary.totalSales,
                                      timeAgo: _timeAgo(e.value.lastSynced),
                                      index: e.key,
                                      onTap: () => showVendorDetail(
                                        context: context,
                                        vendorName: e.value.vendorName,
                                        courtId:
                                            salesState.selectedCourtId ?? 1,
                                        repo: repo,
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 110),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
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

// ── Animated Header Stat ──────────────────────────────────────────────────────

class _AnimatedHeaderStat extends StatelessWidget {
  final String label;
  final String value;
  const _AnimatedHeaderStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
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
          child: Text(
            value,
            key: ValueKey(value),
            style: GoogleFonts.antonSc(fontSize: 22, color: _white, height: 1),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.white54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Court Tabs ────────────────────────────────────────────────────────────────

class _CourtTabs extends StatelessWidget {
  final List<dynamic> courts;
  final int? selectedCourtId;
  final void Function(int?) onSelect;
  const _CourtTabs({
    required this.courts,
    required this.selectedCourtId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _PeriodTab(
              label: 'All Courts',
              isSelected: selectedCourtId == null,
              onTap: () => onSelect(null),
            ),
          ),
          ...courts.map(
            (c) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _PeriodTab(
                label: c.name ?? 'Court',
                isSelected: selectedCourtId == c.id,
                onTap: () => onSelect(c.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Period / Court Tab Pill ───────────────────────────────────────────────────

class _PeriodTab extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _PeriodTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_PeriodTab> createState() => _PeriodTabState();
}

class _PeriodTabState extends State<_PeriodTab>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.93,
    ).animate(CurvedAnimation(parent: _ctrl!, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl?.forward(),
      onTapUp: (_) {
        _ctrl?.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl?.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim ?? const AlwaysStoppedAnimation(1.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: widget.isSelected ? _black : const Color(0xFFF6F6F7),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.isSelected ? _black : const Color(0xFFECECEC),
              width: 1.5,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: _black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: widget.isSelected ? _white : _grey,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Vendor Bento Grid ─────────────────────────────────────────────────────────

class _VendorBentoGrid extends StatefulWidget {
  final List<VendorSaleDetail> vendors;
  final double total;
  final int courtId;
  final SalesRepository repo;
  const _VendorBentoGrid({
    required this.vendors,
    required this.total,
    required this.courtId,
    required this.repo,
  });

  @override
  State<_VendorBentoGrid> createState() => _VendorBentoGridState();
}

class _VendorBentoGridState extends State<_VendorBentoGrid> {
  bool _expanded = false;

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.vendors]
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
    final visible = _expanded ? sorted : sorted.take(4).toList();
    final hasMore = sorted.length > 4;
    final remaining = sorted.length - 4;

    final isOdd = visible.length.isOdd;
    final gridCount = isOdd ? visible.length - 1 : visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (gridCount > 0)
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.05,
            ),
            itemCount: gridCount,
            itemBuilder: (_, i) {
              final v = visible[i];
              final pct = widget.total > 0 ? v.totalSales / widget.total : 0.0;
              return _VendorBentoCard(
                vendor: v,
                pct: pct,
                fmt: _fmt(v.totalSales),
                isFilled: i == 0,
                onTap: () => showVendorDetail(
                  context: context,
                  vendorName: v.vendorName,
                  courtId: widget.courtId,
                  repo: widget.repo,
                ),
              );
            },
          ),

        if (isOdd) ...[
          if (gridCount > 0) const SizedBox(height: 10),

          _VendorBentoCard(
            vendor: visible.last,
            pct: widget.total > 0
                ? visible.last.totalSales / widget.total
                : 0.0,
            fmt: _fmt(visible.last.totalSales),
            isFilled: gridCount == 0,
            isFullWidth: true,
            onTap: () => showVendorDetail(
              context: context,
              vendorName: visible.last.vendorName,
              courtId: widget.courtId,
              repo: widget.repo,
            ),
          ),
        ],

        if (hasMore) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder, width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _expanded
                        ? 'View Less'
                        : 'View $remaining More Vendor${remaining > 1 ? 's' : ''}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0A0A0A),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Vendor Bento Card ─────────────────────────────────────────────────────────

class _VendorBentoCard extends StatefulWidget {
  final VendorSaleDetail vendor;
  final double pct;
  final String fmt;
  final bool isFilled;
  final bool isFullWidth;
  final VoidCallback? onTap;
  const _VendorBentoCard({
    required this.vendor,
    required this.pct,
    required this.fmt,
    required this.isFilled,
    this.isFullWidth = false,
    this.onTap,
  });

  @override
  State<_VendorBentoCard> createState() => _VendorBentoCardState();
}

class _VendorBentoCardState extends State<_VendorBentoCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _pressCtrl;
  Animation<double>? _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _pressAnim = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _pressCtrl!, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isFilled ? _white : _black;
    final subColor = widget.isFilled ? Colors.white54 : _grey;
    final barBg = widget.isFilled ? Colors.white.withOpacity(0.15) : _lightGrey;
    final barFg = widget.isFilled ? _white : _accent;

    return GestureDetector(
      onTapDown: (_) => _pressCtrl?.forward(),
      onTapUp: (_) {
        _pressCtrl?.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _pressCtrl?.reverse(),
      child: ScaleTransition(
        scale: _pressAnim ?? const AlwaysStoppedAnimation(1.0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isFilled ? null : _white,
            gradient: widget.isFilled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E1E1E), _black],
                  )
                : null,
            borderRadius: BorderRadius.circular(20),
            border: widget.isFilled
                ? null
                : Border.all(color: _cardBorder, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: widget.isFilled
                    ? _black.withOpacity(0.22)
                    : Colors.black.withOpacity(0.04),
                blurRadius: widget.isFilled ? 18 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: widget.isFilled
                          ? Colors.white.withOpacity(0.15)
                          : _lightGrey,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        widget.vendor.vendorName.substring(0, 1).toUpperCase(),
                        style: GoogleFonts.antonSc(
                          fontSize: 15,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.vendor.vendorName,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.vendor.sourceSystem,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: subColor,
                            fontWeight: FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${widget.fmt}',
                    style: GoogleFonts.antonSc(
                      fontSize: widget.isFullWidth ? 28 : 24,
                      color: textColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.vendor.billCount} bills',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: subColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: widget.pct),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => LinearProgressIndicator(
                        value: val,
                        minHeight: 4,
                        backgroundColor: barBg,
                        valueColor: AlwaysStoppedAnimation<Color>(barFg),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(widget.pct * 100).toStringAsFixed(1)}% of total',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: subColor,
                      fontWeight: FontWeight.w400,
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

// ── Vendor Row ────────────────────────────────────────────────────────────────

class _VendorRow extends StatefulWidget {
  final VendorSaleDetail vendor;
  final double total;
  final String timeAgo;
  final int index;
  final VoidCallback? onTap;
  const _VendorRow({
    required this.vendor,
    required this.total,
    required this.timeAgo,
    required this.index,
    this.onTap,
  });

  @override
  State<_VendorRow> createState() => _VendorRowState();
}

class _VendorRowState extends State<_VendorRow>
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
  Widget build(BuildContext context) {
    final pct = widget.total > 0
        ? widget.vendor.totalSales / widget.total
        : 0.0;

    return FadeTransition(
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
            widget.onTap?.call();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _cardBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _lightGrey,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            widget.vendor.vendorName
                                .substring(0, 1)
                                .toUpperCase(),
                            style: GoogleFonts.antonSc(
                              fontSize: 18,
                              color: _black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.vendor.vendorName,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _black,
                              ),
                            ),
                            Text(
                              widget.vendor.sourceSystem,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _grey,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${widget.vendor.totalSales.toStringAsFixed(0)}',
                            style: GoogleFonts.antonSc(
                              fontSize: 18,
                              color: _black,
                              height: 1,
                            ),
                          ),
                          Text(
                            '${widget.vendor.billCount} bills',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _grey,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pct),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => LinearProgressIndicator(
                        value: val,
                        minHeight: 5,
                        backgroundColor: _lightGrey,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          _accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(pct * 100).toStringAsFixed(1)}% of total',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _grey,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      Text(
                        'Synced ${widget.timeAgo}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _grey,
                          fontWeight: FontWeight.w400,
                        ),
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
}

// ── Bento Skeleton ────────────────────────────────────────────────────────────

class _BentoSkeleton extends StatefulWidget {
  @override
  State<_BentoSkeleton> createState() => _BentoSkeletonState();
}

class _BentoSkeletonState extends State<_BentoSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl!, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim ?? const AlwaysStoppedAnimation(0.5),
      builder: (_, __) {
        final color = Color.lerp(
          const Color(0xFFEEEEEE),
          const Color(0xFFD5D5D5),
          _anim?.value ?? 0.5,
        )!;
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: List.generate(
            4,
            (_) => Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Skeleton Box ──────────────────────────────────────────────────────────────

class _SkeletonBox extends StatelessWidget {
  final double height;
  const _SkeletonBox({required this.height});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFEEEEEE),
      borderRadius: BorderRadius.circular(16),
    ),
  );
}

// ── Sales Trend Chart (native bar chart — no package) ─────────────────────────

class _SalesTrendChart extends StatelessWidget {
  final SalesTrend? trend;
  final SalesPeriod period;
  final bool loading;
  const _SalesTrendChart({
    required this.trend,
    required this.period,
    required this.loading,
  });

  String get _title {
    switch (period) {
      case SalesPeriod.yesterday:
        return 'Last 7 days';
      case SalesPeriod.week:
        return 'This week';
      case SalesPeriod.month:
        return 'This month';
      case SalesPeriod.year:
        return 'This year';
      case SalesPeriod.custom:
        return 'Trend';
    }
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _ChartSkeleton();
    final t = trend;
    if (t == null || t.points.isEmpty) return const SizedBox.shrink();

    final maxV = t.maxSales;
    final n = t.points.length;
    final step = n <= 12 ? 1 : (n / 8).ceil();
    final showValues = n <= 5; // month = 4 weekly bars -> show ₹ on each
    int peakIdx = 0;
    for (var i = 1; i < n; i++) {
      if (t.points[i].totalSales > t.points[peakIdx].totalSales) peakIdx = i;
    }

    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _black,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Sales trend',
                    style: GoogleFonts.inter(fontSize: 11.5, color: _grey),
                  ),
                ],
              ),
              if (t.hasAnySales)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${_fmt(maxV)}',
                      style: GoogleFonts.antonSc(fontSize: 18, color: _black),
                    ),
                    Text(
                      'peak',
                      style: GoogleFonts.inter(fontSize: 10.5, color: _grey),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!t.hasAnySales)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'No sales in this period',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(n, (i) {
                  final p = t.points[i];
                  final frac = maxV > 0 ? p.totalSales / maxV : 0.0;
                  final isPeak = i == peakIdx;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: n > 8 ? 2 : 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (showValues && p.totalSales > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Text(
                                '₹${_fmt(p.totalSales)}',
                                maxLines: 1,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: _black,
                                ),
                              ),
                            ),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: frac),
                            duration: Duration(milliseconds: 500 + i * 30),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, __) => Container(
                              height: (v * 104).clamp(3.0, 104.0),
                              decoration: BoxDecoration(
                                color: isPeak
                                    ? _accent
                                    : _accent.withOpacity(0.26),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(n, (i) {
                final show = i % step == 0 || i == n - 1;
                return Expanded(
                  child: Text(
                    show ? t.points[i].label : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      color: _grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}



// ── Chart skeleton ────────────────────────────────────────────────────────────

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder, width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final h = 30.0 + (i % 3) * 34.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                height: h,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEDED),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
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

// ── Empty state (no outlets / no sales) ───────────────────────────────────────

class _SalesEmptyState extends StatelessWidget {
  final bool courtSelected;
  final bool hasOutlets;
  final String periodLabel;
  const _SalesEmptyState({
    required this.courtSelected,
    required this.hasOutlets,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final bool noOutlets = courtSelected && !hasOutlets;
    final IconData icon =
        noOutlets ? Icons.storefront_outlined : Icons.bar_chart_rounded;
    final String title =
        noOutlets ? 'No outlets in this court' : 'No sales to show';
    final String subtitle = noOutlets
        ? 'Assign vendors/outlets to this court to start seeing their sales here.'
        : 'There were no recorded sales for $periodLabel. Try a different period or court.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: _lightGrey,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: _grey),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _black,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: _grey,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}



// ── Error state (network / server) with retry ─────────────────────────────────

class _SalesErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _SalesErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              size: 28,
              color: Color(0xFFEF4444),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Couldn't load sales",
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _black,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check your internet connection and try again.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: _grey, height: 1.45),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onRetry();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: _black,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded, size: 16, color: _white),
                  const SizedBox(width: 8),
                  Text(
                    'Retry',
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
        ],
      ),
    );
  }
}
