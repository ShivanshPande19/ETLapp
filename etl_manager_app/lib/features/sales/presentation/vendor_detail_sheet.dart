import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import '../data/sales_repository.dart';
import 'package:flutter/services.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF0A0A0A);
const _grey = Color(0xFF888888);
const _lightGrey = Color(0xFFF2F2F2);
const _border = Color(0xFF1A1A1A);

// Relative "synced Xm ago" from an ISO timestamp (mirrors the sales screen).
String _timeAgo(String? iso) {
  if (iso == null || iso.isEmpty) return 'recently';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  } catch (_) {
    return 'recently';
  }
}

// ── Entry point ───────────────────────────────────────────────────────────────

void showVendorDetail({
  required BuildContext context,
  required String vendorName,
  required int courtId,
  required SalesRepository repo,
}) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true, // ✅ THE MAGIC FIX: Nav bar ko override karega
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VendorDetailSheet(
      vendorName: vendorName,
      courtId: courtId,
      repo: repo,
    ),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _VendorDetailSheet extends StatefulWidget {
  final String vendorName;
  final int courtId;
  final SalesRepository repo;
  const _VendorDetailSheet({
    required this.vendorName,
    required this.courtId,
    required this.repo,
  });

  @override
  State<_VendorDetailSheet> createState() => _VendorDetailSheetState();
}

class _VendorDetailSheetState extends State<_VendorDetailSheet>
    with SingleTickerProviderStateMixin {
  VendorHistory? _data;
  bool _loading = true;
  String? _error;
  late AnimationController _barCtrl;

  // Selected bar ko track karne ke liye state variable
  int? _selectedIndex;

  // ── Breakdown (week / month) ──────────────────────────────
  // Week k = the 7 days ending (yesterday - 7k). Month k = the calendar month
  // k months before yesterday's month. Offset 0 is always the latest period.
  _Mode _mode = _Mode.week;
  int _weekOffset = 0;
  int _monthOffset = 0;
  final Map<String, List<DailySnapshot>> _periods = {};
  bool _periodLoading = false;
  bool _periodFailed = false;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.repo.fetchVendorHistory(
        vendorName: widget.vendorName,
        courtId: widget.courtId,
      );

      if (mounted) {
        setState(() {
          _data = result;
          _loading = false;
          // The default history IS the latest week, so that period needs no
          // second request — as long as the server's "yesterday" agrees with
          // this phone's.
          final (start, _) = _rangeFor(_Mode.week, 0);
          if (result.dailyHistory.isNotEmpty &&
              result.dailyHistory.first.date == _iso(start)) {
            _periods[_key(_Mode.week, 0)] = result.dailyHistory;
          }
          _selectedIndex = _bestIndex(result.dailyHistory);
        });
        _barCtrl.forward();
        _ensurePeriod();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load vendor data';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  // ── Breakdown periods ───────────────────────────────────

  static const _months = [
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
  ];
  static const _monthsLong = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // How far back the arrows go.
  static const _maxWeekOffset = 104;
  static const _maxMonthOffset = 24;

  static DateTime get _yesterday {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day - 1);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _key(_Mode m, int offset) => '${m.name}:$offset';

  int get _offset => _mode == _Mode.week ? _weekOffset : _monthOffset;

  /// First and last day of a period. A month's last day is its real last day;
  /// the server stops at yesterday for the month in progress.
  static (DateTime, DateTime) _rangeFor(_Mode m, int offset) {
    final y = _yesterday;
    if (m == _Mode.week) {
      final end = DateTime(y.year, y.month, y.day - 7 * offset);
      return (DateTime(end.year, end.month, end.day - 6), end);
    }
    final start = DateTime(y.year, y.month - offset, 1);
    return (start, DateTime(start.year, start.month + 1, 0));
  }

  String _periodLabel() {
    final (start, end) = _rangeFor(_mode, _offset);
    if (_mode == _Mode.month) {
      final thisYear = start.year == _yesterday.year;
      return thisYear
          ? _monthsLong[start.month - 1]
          : '${_monthsLong[start.month - 1]} ${start.year}';
    }
    if (_weekOffset == 0) return 'Last 7 days';
    final s = start.month == end.month
        ? '${start.day}'
        : '${start.day} ${_months[start.month - 1]}';
    final yr = end.year == _yesterday.year ? '' : ' ${end.year}';
    return '$s – ${end.day} ${_months[end.month - 1]}$yr';
  }

  static int? _bestIndex(List<DailySnapshot> days) {
    if (days.isEmpty) return null;
    var idx = 0;
    for (var i = 1; i < days.length; i++) {
      if (days[i].totalSales > days[idx].totalSales) idx = i;
    }
    return idx;
  }

  Future<void> _ensurePeriod() async {
    final key = _key(_mode, _offset);
    final cached = _periods[key];
    if (cached != null) {
      setState(() {
        _periodFailed = false;
        _periodLoading = false;
        _selectedIndex = _bestIndex(cached);
      });
      _barCtrl.forward(from: 0);
      return;
    }
    setState(() {
      _periodLoading = true;
      _periodFailed = false;
    });
    final (start, end) = _rangeFor(_mode, _offset);
    try {
      final days = await widget.repo.fetchVendorDaily(
        vendorName: widget.vendorName,
        courtId: widget.courtId,
        from: start,
        to: end,
      );
      _periods[key] = days;
      // Answers can arrive out of order when the arrows are tapped quickly;
      // only the one for the period on screen updates it.
      if (!mounted || key != _key(_mode, _offset)) return;
      setState(() {
        _periodLoading = false;
        _selectedIndex = _bestIndex(days);
      });
      _barCtrl.forward(from: 0);
    } catch (_) {
      if (!mounted || key != _key(_mode, _offset)) return;
      setState(() {
        _periodLoading = false;
        _periodFailed = true;
      });
    }
  }

  void _setMode(_Mode m) {
    if (m == _mode) return;
    HapticFeedback.selectionClick();
    setState(() => _mode = m);
    _ensurePeriod();
  }

  void _step(int delta) {
    final next = _offset + delta;
    final max = _mode == _Mode.week ? _maxWeekOffset : _maxMonthOffset;
    if (next < 0 || next > max) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_mode == _Mode.week) {
        _weekOffset = next;
      } else {
        _monthOffset = next;
      }
    });
    _ensurePeriod();
  }

  // ── Helpers ─────────────────────────────────────────────

  String _fmt(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  String _dayLetter(String iso) {
    try {
      const l = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      return l[DateTime.parse(iso).weekday - 1];
    } catch (_) {
      return '?';
    }
  }

  String _shortDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const m = [
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
      ];
      return '${m[d.month - 1]} ${d.day}';
    } catch (_) {
      return iso;
    }
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _border.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _black,
                        strokeWidth: 2,
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: _grey,
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: GoogleFonts.inter(
                              color: _grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildContent(scrollCtrl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ScrollController scrollCtrl) {
    final d = _data!;

    final weekDiff = d.weekTotal - d.lastWeekTotal;
    final weekDiffPct = d.lastWeekTotal > 0
        ? (weekDiff / d.lastWeekTotal * 100)
        : 0.0;
    final isUp = weekDiff >= 0;

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        // ── Header ─────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _black,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  d.vendorName.substring(0, 1).toUpperCase(),
                  style: GoogleFonts.antonSc(fontSize: 20, color: _white),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.vendorName,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _black,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Data as of yesterday · synced ${_timeAgo(d.lastSynced)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _grey,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Yesterday stats ─────────────────────────────────
        Row(
          children: [
            _StatBox(label: 'Yesterday', value: _fmt(d.totalSales), flex: 2),
            const SizedBox(width: 10),
            _StatBox(label: 'Bills', value: '${d.billCount}'),
            const SizedBox(width: 10),
            _StatBox(label: 'Avg Bill', value: _fmt(d.avgBillValue)),
          ],
        ),
        const SizedBox(height: 10),

        // ── Week comparison ─────────────────────────────────
        Row(
          children: [
            _StatBox(label: 'Last 7 Days', value: _fmt(d.weekTotal), flex: 2),
            const SizedBox(width: 10),
            _StatBox(
              label: 'Prev 7 Days',
              value: _fmt(d.lastWeekTotal),
              flex: 2,
            ),
            const SizedBox(width: 10),
            _StatBox(
              label: 'WoW',
              value: '${isUp ? '+' : ''}${weekDiffPct.toStringAsFixed(1)}%',
              valueColor: isUp
                  ? const Color(0xFF22A06B)
                  : const Color(0xFFE53E3E),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Best day badge ──────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _black,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
              const SizedBox(width: 8),
              Text(
                'Best day (last 7d): ',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white54,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Flexible(
                child: Text(
                  d.bestDay,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        ..._buildBreakdown(),
      ],
    );
  }

  // ── Breakdown section ───────────────────────────────────

  List<Widget> _buildBreakdown() {
    final days = _periods[_key(_mode, _offset)];
    final maxOffset = _mode == _Mode.week ? _maxWeekOffset : _maxMonthOffset;

    return [
      // Title + Week/Month toggle
      Row(
        children: [
          Text(
            'Breakdown',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _black,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          _ModeToggle(mode: _mode, onChanged: _setMode),
        ],
      ),
      const SizedBox(height: 12),

      // ‹ period ›
      _PeriodSelector(
        label: _periodLabel(),
        subtitle: days == null
            ? null
            : '${_fmt(days.fold(0.0, (a, s) => a + s.totalSales))} · '
                  '${days.fold(0, (a, s) => a + s.totalBills)} bills',
        canGoBack: _offset < maxOffset,
        canGoForward: _offset > 0,
        onBack: () => _step(1),
        onForward: () => _step(-1),
      ),
      SizedBox(
        height: 2,
        child: _periodLoading
            ? LinearProgressIndicator(
                color: _black,
                backgroundColor: _lightGrey,
                minHeight: 2,
                borderRadius: BorderRadius.circular(999),
              )
            : null,
      ),
      const SizedBox(height: 14),

      if (_periodFailed && days == null)
        _PeriodMessage(
          text: 'Could not load this period.',
          action: 'Retry',
          onAction: _ensurePeriod,
        )
      else if (days == null)
        const SizedBox(height: 190)
      else if (days.isEmpty)
        const _PeriodMessage(text: 'No sales data for this period yet.')
      else
        AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _periodLoading ? 0.4 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _periodStats(days),
              const SizedBox(height: 18),
              if (_mode == _Mode.week) _weekChart(days) else _monthChart(days),
              const SizedBox(height: 22),
              Text(
                'Daily Breakdown',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _black,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              ..._dayList(days, compact: _mode == _Mode.month),
            ],
          ),
        ),
    ];
  }

  Widget _periodStats(List<DailySnapshot> days) {
    final total = days.fold(0.0, (a, s) => a + s.totalSales);
    final open = days.where((s) => s.totalSales > 0).length;
    final best = days[_bestIndex(days)!];
    return Row(
      children: [
        _StatBox(label: 'Total', value: _fmt(total), flex: 2),
        const SizedBox(width: 10),
        _StatBox(
          label: 'Avg / day',
          value: _fmt(open == 0 ? 0 : total / open),
          flex: 2,
        ),
        const SizedBox(width: 10),
        _StatBox(
          label: 'Best day',
          value: best.totalSales > 0 ? _shortDate(best.date) : '—',
          flex: 2,
        ),
      ],
    );
  }

  Widget _weekChart(List<DailySnapshot> days) {
    final maxSales = days.map((e) => e.totalSales).fold(0.0, math.max);
    return SizedBox(
      height: 190,
      child: AnimatedBuilder(
        animation: _barCtrl,
        builder: (_, _) {
          final progress = CurvedAnimation(
            parent: _barCtrl,
            curve: Curves.easeOutCubic,
          ).value;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: days.asMap().entries.map((e) {
              final snap = e.value;
              final index = e.key;
              final isLast = index == days.length - 1;
              final isSelected = _selectedIndex == index;
              final ratio = maxSales > 0 ? snap.totalSales / maxSales : 0.0;
              final barH = (120 * ratio * progress).clamp(2.0, 120.0);

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedIndex = index);
                  },
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 20,
                          child: isSelected
                              ? Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Text(
                                    _fmt(snap.totalSales),
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      color: _black,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          height: barH,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _black
                                : isLast
                                ? _border.withValues(alpha: 0.6)
                                : _lightGrey,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: 14,
                          child: Text(
                            _dayLetter(snap.date),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isSelected ? _black : _grey,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                          height: 12,
                          child: Text(
                            _shortDate(snap.date).split(' ').last,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color: isSelected
                                  ? _black.withValues(alpha: 0.6)
                                  : _grey.withValues(alpha: 0.5),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  /// A month as thin bars: tap or drag across to read any day. Dates are
  /// labelled on the 1st, every 5th and the last day so they never collide.
  Widget _monthChart(List<DailySnapshot> days) {
    final maxSales = days.map((e) => e.totalSales).fold(0.0, math.max);
    final sel = (_selectedIndex ?? 0).clamp(0, days.length - 1);
    final selDay = days[sel];
    final selDate = DateTime.tryParse(selDay.date);
    // Width of a full month, so a month in progress keeps the same bar size
    // and fills from the left instead of stretching a few fat bars.
    final (start, _) = _rangeFor(_Mode.month, _monthOffset);
    final slots = DateTime(start.year, start.month + 1, 0).day;

    void pick(double dx, double width) {
      final i = (dx / (width / slots)).floor().clamp(0, days.length - 1);
      if (i != _selectedIndex) {
        HapticFeedback.selectionClick();
        setState(() => _selectedIndex = i);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Readout for the selected day
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _black,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selDate == null
                      ? selDay.date
                      : '${_weekdays[selDate.weekday - 1]}, ${selDate.day} ${_months[selDate.month - 1]}',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${selDay.totalBills} bills',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(width: 12),
              Text(
                _fmt(selDay.totalSales),
                style: GoogleFonts.antonSc(
                  fontSize: 15,
                  color: _white,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (_, box) {
            final w = box.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (e) => pick(e.localPosition.dx, w),
              onHorizontalDragUpdate: (e) => pick(e.localPosition.dx, w),
              child: AnimatedBuilder(
                animation: _barCtrl,
                builder: (_, _) {
                  final progress = CurvedAnimation(
                    parent: _barCtrl,
                    curve: Curves.easeOutCubic,
                  ).value;
                  return Column(
                    children: [
                      SizedBox(
                        height: 110,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(slots, (i) {
                            if (i >= days.length) {
                              return const Expanded(child: SizedBox());
                            }
                            final s = days[i];
                            final ratio = maxSales > 0
                                ? s.totalSales / maxSales
                                : 0.0;
                            final selected = i == sel;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1.2,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  height: (110 * ratio * progress).clamp(
                                    2.0,
                                    110.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? _black
                                        : const Color(0xFFD9D9D9),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 12,
                        child: Row(
                          children: List.generate(slots, (i) {
                            final dayNo = i + 1;
                            final show =
                                i == sel ||
                                // A 5th that sits next to the month's last
                                // day (30 in a 31-day month) would collide
                                // with its label, so it gives way.
                                ((dayNo == 1 ||
                                        (dayNo % 5 == 0 && slots - dayNo > 1) ||
                                        dayNo == slots) &&
                                    (i - sel).abs() > 1);
                            return Expanded(
                              child: OverflowBox(
                                maxWidth: 24,
                                child: Text(
                                  show ? '$dayNo' : '',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    color: i == sel ? _black : _grey,
                                    fontWeight: i == sel
                                        ? FontWeight.w800
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  /// Newest day first. The month view uses tighter rows so 30 days stay
  /// scannable; days with no sales are dimmed.
  List<Widget> _dayList(List<DailySnapshot> days, {required bool compact}) {
    final maxSales = days.map((e) => e.totalSales).fold(0.0, math.max);
    return days.reversed.map((snap) {
      final isBest = maxSales > 0 && snap.totalSales == maxSales;
      final empty = snap.totalSales <= 0;
      final dt = DateTime.tryParse(snap.date);
      final label = compact && dt != null
          ? '${_weekdays[dt.weekday - 1]}, ${dt.day} ${_months[dt.month - 1]}'
          : _shortDate(snap.date);
      return Container(
        margin: EdgeInsets.only(bottom: compact ? 6 : 8),
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 9 : 12,
        ),
        decoration: BoxDecoration(
          color: isBest ? _black : _lightGrey,
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
        ),
        child: Row(
          children: [
            // Label (+ Best badge) takes the free width, so the bills and
            // amount columns line up on the right edge in every row.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: GoogleFonts.inter(
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: isBest
                            ? _white
                            : empty
                            ? _grey
                            : _black,
                      ),
                    ),
                  ),
                  if (isBest) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Best',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: Colors.amber,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!empty) ...[
              Text(
                '${snap.totalBills} bills',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isBest ? Colors.white54 : _grey,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              empty ? '—' : _fmt(snap.totalSales),
              style: GoogleFonts.antonSc(
                fontSize: compact ? 14 : 15,
                color: isBest
                    ? _white
                    : empty
                    ? _grey
                    : _black,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

enum _Mode { week, month }

// ── Week / Month toggle ───────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const w = 64.0;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _lightGrey,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: mode == _Mode.week ? 0 : w,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: _black,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in _Mode.values)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(m),
                  child: SizedBox(
                    width: w,
                    height: 30,
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: m == mode ? _white : _grey,
                        ),
                        child: Text(m == _Mode.week ? 'Week' : 'Month'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── ‹ period › selector ───────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  const _PeriodSelector({
    required this.label,
    required this.subtitle,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, bool enabled, VoidCallback onTap, String tip) {
      return Semantics(
        button: true,
        enabled: enabled,
        label: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: enabled ? _white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? _black : _grey.withValues(alpha: 0.35),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _lightGrey,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          arrow(Icons.chevron_left_rounded, canGoBack, onBack, 'Previous'),
          Expanded(
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    label,
                    key: ValueKey(label),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _black,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle ?? ' ',
                  style: GoogleFonts.inter(fontSize: 11, color: _grey),
                ),
              ],
            ),
          ),
          arrow(Icons.chevron_right_rounded, canGoForward, onForward, 'Next'),
        ],
      ),
    );
  }
}

class _PeriodMessage extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const _PeriodMessage({required this.text, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: GoogleFonts.inter(fontSize: 13, color: _grey)),
          if (action != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: _black),
              child: Text(
                action!,
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Stat Box ──────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final int flex;
  final Color? valueColor;
  const _StatBox({
    required this.label,
    required this.value,
    this.flex = 1,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _lightGrey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _grey,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: GoogleFonts.antonSc(
                fontSize: 17,
                color: valueColor ?? _black,
                height: 1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
