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
const _border = Color(0xFF1A1A1A);

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
  int? _prevCourtId = -999;
  double _animTotal = 0;
  double _prevTotal = 0;

  AnimationController? _fadeCtrl;
  AnimationController? _switchCtrl;
  AnimationController? _numCtrl;

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
      duration: const Duration(milliseconds: 340),
    );
    _switchFade = CurvedAnimation(
      parent: _switchCtrl!,
      curve: Curves.easeOutCubic,
    );
    _switchSlide = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _switchCtrl!, curve: Curves.easeOutCubic),
        );
    _switchCtrl!.value = 1.0;

    _numCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _fadeCtrl?.dispose();
    _switchCtrl?.dispose();
    _numCtrl?.dispose();
    super.dispose();
  }

  // ── Trigger on court/period change ────────────────────────────────────────

  void _onNewData(double newTotal, int? courtId) {
    if (courtId == _prevCourtId) return;
    _prevCourtId = courtId;
    _prevTotal = _animTotal;

    _switchCtrl?.reverse().then((_) {
      if (mounted) _switchCtrl?.forward();
    });

    _numCtrl?.reset();
    _numCtrl?.addListener(() {
      if (mounted) {
        setState(() {
          _animTotal =
              _prevTotal + ((_numCtrl?.value ?? 0) * (newTotal - _prevTotal));
        });
      }
    });
    _numCtrl?.animateTo(
      1.0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  // ── Period change — triggers content fade ─────────────────────────────────

  void _onPeriodTap(SalesPeriod period, int? courtId) async {
    if (period == SalesPeriod.custom) {
      final range = await showDateRangePicker(
        context: context,
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
      if (range == null || !mounted) return;
      HapticFeedback.selectionClick();
      _triggerSwitchAnim();
      ref
          .read(salesNotifierProvider.notifier)
          .fetchSummary(
            courtId: courtId,
            period: SalesPeriod.custom,
            customDateFrom: range.start.toIso8601String().split('T').first,
            customDateTo: range.end.toIso8601String().split('T').first,
          );
    } else {
      HapticFeedback.selectionClick();
      _triggerSwitchAnim();
      ref
          .read(salesNotifierProvider.notifier)
          .fetchSummary(courtId: courtId, period: period);
    }
  }

  void _triggerSwitchAnim() {
    _prevCourtId = -998; // force _onNewData to re-trigger
    _switchCtrl?.reverse().then((_) {
      if (mounted) _switchCtrl?.forward();
    });
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
        return 'Custom Range';
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

    if (summary != null && salesState.status == SalesLoadStatus.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onNewData(summary.totalSales, salesState.selectedCourtId);
      });
    }

    return Scaffold(
      backgroundColor: _black,
      body: FadeTransition(
        opacity: _fadeAnim ?? const AlwaysStoppedAnimation(1.0),
        child: RefreshIndicator(
          color: _white,
          backgroundColor: _black,
          strokeWidth: 2,
          onRefresh: () => ref
              .read(salesNotifierProvider.notifier)
              .fetchSummary(
                courtId: salesState.selectedCourtId,
                period: salesState.period,
              ),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Black Header ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
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
                            // Date / period pill
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
                                      // ← now shows period label
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
                ),
              ),

              // ── White Body ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
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
                            _prevCourtId = -998;
                            ref
                                .read(salesNotifierProvider.notifier)
                                .fetchSummary(
                                  courtId: id,
                                  period: salesState.period,
                                );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Period Tabs — fully wired ───────────────────
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
                                child: isLoading
                                    ? _BentoSkeleton()
                                    : salesState.status == SalesLoadStatus.error
                                    ? _ErrorRow(message: 'Could not load sales')
                                    : summary != null &&
                                          summary.vendors.isNotEmpty
                                    ? _VendorBentoGrid(
                                        vendors: summary.vendors,
                                        total: summary.totalSales,
                                        courtId:
                                            salesState.selectedCourtId ?? 1,
                                        repo: repo,
                                      )
                                    : const SizedBox.shrink(),
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

                              if (salesState.status == SalesLoadStatus.error)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _ErrorRow(
                                    message: 'Could not load vendors',
                                  ),
                                )
                              else if (isLoading)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: Column(
                                    children: List.generate(
                                      3,
                                      (i) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: _SkeletonBox(height: 90),
                                      ),
                                    ),
                                  ),
                                )
                              else if (summary != null)
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

                              const SizedBox(height: 110),
                            ],
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
            color: widget.isSelected ? _black : _white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.isSelected ? _black : _border.withOpacity(0.3),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.05,
          ),
          itemCount: isOdd ? visible.length - 1 : visible.length,
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
          const SizedBox(height: 10),
          _VendorBentoCard(
            vendor: visible.last,
            pct: widget.total > 0
                ? visible.last.totalSales / widget.total
                : 0.0,
            fmt: _fmt(visible.last.totalSales),
            isFilled: false,
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
                color: _white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border.withOpacity(0.3), width: 1.5),
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
                      color: _black,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: _black,
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
    final bg = widget.isFilled ? _black : _white;
    final textColor = widget.isFilled ? _white : _black;
    final subColor = widget.isFilled ? Colors.white54 : _grey;
    final barBg = widget.isFilled ? Colors.white.withOpacity(0.15) : _lightGrey;
    final barFg = widget.isFilled ? _white : _black;
    final borderColor = widget.isFilled
        ? Colors.transparent
        : _border.withOpacity(0.3);

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
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border, width: 1.5),
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
                        valueColor: const AlwaysStoppedAnimation<Color>(_black),
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

// ── Error Row ─────────────────────────────────────────────────────────────────

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
