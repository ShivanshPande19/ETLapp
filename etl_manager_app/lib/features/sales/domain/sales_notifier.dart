import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sales_repository.dart';

enum SalesLoadStatus { idle, loading, loaded, error }

enum SalesPeriod { yesterday, week, month, year, custom }

// ── Period-window helpers (for the clickable date pill) ───────────────────────
// offset 0 = this week/month/year, 1 = previous, 2 = two ago … The client
// computes the concrete from/to and the backend just sums that window.
const _kMonthsShort = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _kMonthsLong = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

DateTime _kDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String _kIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class PeriodWindow {
  final String from;
  final String to;
  final String label;
  const PeriodWindow(this.from, this.to, this.label);
}

/// Concrete window + label for a week/month/year at the given offset.
PeriodWindow periodWindow(SalesPeriod period, int offset) {
  final today = _kDateOnly(DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));
  DateTime clampTo(DateTime end) => end.isAfter(yesterday) ? yesterday : end;

  switch (period) {
    case SalesPeriod.week:
      final thisMon = today.subtract(Duration(days: today.weekday - 1));
      final mon = thisMon.subtract(Duration(days: 7 * offset));
      final sun = mon.add(const Duration(days: 6));
      final label = offset == 0
          ? 'This Week'
          : offset == 1
              ? 'Last Week'
              : '${mon.day} ${_kMonthsShort[mon.month]} – ${sun.day} ${_kMonthsShort[sun.month]}';
      return PeriodWindow(_kIso(mon), _kIso(clampTo(sun)), label);
    case SalesPeriod.month:
      final base = DateTime(today.year, today.month - offset, 1);
      final end = DateTime(base.year, base.month + 1, 0);
      final label = offset == 0
          ? 'This Month'
          : offset == 1
              ? 'Last Month'
              : '${_kMonthsLong[base.month]} ${base.year}';
      return PeriodWindow(_kIso(base), _kIso(clampTo(end)), label);
    case SalesPeriod.year:
      final y = today.year - offset;
      final label = offset == 0 ? 'This Year' : offset == 1 ? 'Last Year' : '$y';
      return PeriodWindow(_kIso(DateTime(y, 1, 1)), _kIso(clampTo(DateTime(y, 12, 31))), label);
    case SalesPeriod.yesterday:
    case SalesPeriod.custom:
      return PeriodWindow(_kIso(yesterday), _kIso(yesterday), 'Yesterday');
  }
}

/// Label for a custom single-day / range selection.
String customRangeLabel(String? from, String? to) {
  if (from == null) return 'Custom';
  final f = DateTime.parse(from);
  if (to == null || to == from) {
    return '${f.day} ${_kMonthsShort[f.month]} ${f.year}';
  }
  final t = DateTime.parse(to);
  if (f.year == t.year && f.month == t.month) {
    return '${f.day}–${t.day} ${_kMonthsShort[f.month]} ${f.year}';
  }
  return '${f.day} ${_kMonthsShort[f.month]} – ${t.day} ${_kMonthsShort[t.month]} ${t.year}';
}

class SalesState {
  final SalesLoadStatus status;
  final SalesSummary? summary;
  final SalesTrend? trend;
  final String? error;
  final int? selectedCourtId;
  final SalesPeriod period;
  final int periodOffset; // 0 = this, 1 = previous, …
  final String? customDateFrom;
  final String? customDateTo;
  final String? rangeLabel; // shown in the clickable date pill

  const SalesState({
    this.status = SalesLoadStatus.idle,
    this.summary,
    this.trend,
    this.error,
    this.selectedCourtId,
    this.period = SalesPeriod.yesterday,
    this.periodOffset = 0,
    this.customDateFrom,
    this.customDateTo,
    this.rangeLabel,
  });
}

class _CachedSales {
  final SalesSummary summary;
  final SalesTrend? trend;
  const _CachedSales(this.summary, this.trend);
}

class SalesNotifier extends Notifier<SalesState> {
  // Stale-while-revalidate cache so switching period/court is instant on
  // revisit. Sales data only changes a few times a day (sync), so serving the
  // cached view immediately and refreshing in the background is safe + fast.
  final Map<String, _CachedSales> _cache = {};
  // Guards against out-of-order responses when the user taps chips quickly:
  // only the latest request is allowed to update state.
  int _reqCounter = 0;

  @override
  SalesState build() {
    Future.microtask(
      () => fetchSummary(allCourts: true, period: SalesPeriod.yesterday),
    );
    return const SalesState(status: SalesLoadStatus.loading);
  }

  String _periodStr(SalesPeriod p) {
    switch (p) {
      case SalesPeriod.yesterday:
        return 'yesterday';
      case SalesPeriod.week:
        return 'this_week';
      case SalesPeriod.month:
        return 'this_month';
      case SalesPeriod.year:
        return 'this_year';
      case SalesPeriod.custom:
        return 'custom';
    }
  }

  Future<void> fetchSummary({
    int? courtId,
    int? outletId, // ✅ P0-3: outlet users pass their own outlet id
    bool allCourts = false,
    SalesPeriod period = SalesPeriod.yesterday,
    int periodOffset = 0, // 0 = this, 1 = previous week/month/year, …
    String? customDateFrom,
    String? customDateTo,
  }) async {
    final nextCourtId = allCourts ? null : courtId;
    final periodStr = _periodStr(period);

    // Resolve the effective window (explicit from/to) + the pill label.
    // - custom            → use the picked dates (single day or range)
    // - week/month/year @ offset>0 → compute that previous window
    // - week/month/year @ offset 0 → no dates (backend preset "…up to yesterday")
    // - yesterday         → no dates, no label (pill shows the date)
    String? df = customDateFrom;
    String? dt = customDateTo;
    String? label;
    if (period == SalesPeriod.custom) {
      label = customRangeLabel(customDateFrom, customDateTo);
    } else if (period != SalesPeriod.yesterday && periodOffset > 0) {
      final w = periodWindow(period, periodOffset);
      df = w.from;
      dt = w.to;
      label = w.label;
    } else if (period != SalesPeriod.yesterday) {
      label = periodWindow(period, 0).label; // "This Week/Month/Year"
    }

    final key =
        '$periodStr|$periodOffset|${nextCourtId ?? 'all'}|o${outletId ?? 'all'}|${df ?? ''}|${dt ?? ''}';
    final reqId = ++_reqCounter;

    SalesState base({
      required SalesLoadStatus status,
      SalesSummary? summary,
      SalesTrend? trend,
      String? error,
    }) => SalesState(
      status: status,
      summary: summary,
      trend: trend,
      error: error,
      selectedCourtId: nextCourtId,
      period: period,
      periodOffset: periodOffset,
      customDateFrom: customDateFrom,
      customDateTo: customDateTo,
      rangeLabel: label,
    );

    // 1) Instant paint: cached view if we have it, else keep current data
    //    visible (no blank flash) while the fresh data loads.
    final cached = _cache[key];
    if (cached != null) {
      state = base(
        status: SalesLoadStatus.loaded,
        summary: cached.summary,
        trend: cached.trend,
      );
    } else {
      state = base(
        status: SalesLoadStatus.loading,
        summary: state.summary,
        trend: state.trend,
      );
    }

    final repo = ref.read(salesRepositoryProvider);

    // 2) Fire summary + trend in parallel. Trend is best-effort. Both use the
    //    same effective window (df/dt), so the chart matches the selection —
    //    including custom ranges and previous periods.
    final summaryFut = repo.getSalesSummary(
      courtId: nextCourtId,
      outletId: outletId,
      period: periodStr,
      dateFrom: df,
      dateTo: dt,
    );
    final bool hasRange = df != null && dt != null;
    final Future<SalesTrend?> trendFut = repo
        .getSalesTrend(
          courtId: nextCourtId,
          outletId: outletId,
          period: periodStr,
          dateFrom: hasRange ? df : null,
          dateTo: hasRange ? dt : null,
        )
        .then<SalesTrend?>((t) => t)
        .catchError((_) => null);

    // 3) Show the numbers as soon as the summary lands (chart keeps the old/
    //    cached view for the split-second the trend is still in flight).
    SalesSummary summary;
    try {
      summary = await summaryFut;
    } catch (e) {
      if (reqId != _reqCounter) return; // superseded
      if (cached != null) return; // keep the cached view silently
      state = base(status: SalesLoadStatus.error, error: e.toString(), trend: state.trend);
      return;
    }
    if (reqId != _reqCounter) return;

    state = base(
      status: SalesLoadStatus.loaded,
      summary: summary,
      trend: cached?.trend ?? state.trend,
    );

    // 4) Patch in the fresh trend + refresh cache.
    final trend = await trendFut;
    if (reqId != _reqCounter) return;
    state = base(status: SalesLoadStatus.loaded, summary: summary, trend: trend);
    _cache[key] = _CachedSales(summary, trend);
  }
}

final salesNotifierProvider = NotifierProvider<SalesNotifier, SalesState>(
  SalesNotifier.new,
);
