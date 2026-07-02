import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sales_repository.dart';

enum SalesLoadStatus { idle, loading, loaded, error }

enum SalesPeriod { yesterday, week, month, year, custom }

class SalesState {
  final SalesLoadStatus status;
  final SalesSummary? summary;
  final SalesTrend? trend;
  final String? error;
  final int? selectedCourtId;
  final SalesPeriod period;
  final String? customDateFrom;
  final String? customDateTo;

  const SalesState({
    this.status = SalesLoadStatus.idle,
    this.summary,
    this.trend,
    this.error,
    this.selectedCourtId,
    this.period = SalesPeriod.yesterday,
    this.customDateFrom,
    this.customDateTo,
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
    bool allCourts = false,
    SalesPeriod period = SalesPeriod.yesterday,
    String? customDateFrom,
    String? customDateTo,
  }) async {
    final nextCourtId = allCourts ? null : courtId;
    final periodStr = _periodStr(period);
    final key =
        '$periodStr|${nextCourtId ?? 'all'}|${customDateFrom ?? ''}|${customDateTo ?? ''}';
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
      customDateFrom: customDateFrom,
      customDateTo: customDateTo,
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

    // 2) Fire summary + trend in parallel. Trend is best-effort.
    final summaryFut = repo.getSalesSummary(
      courtId: nextCourtId,
      period: periodStr,
      dateFrom: customDateFrom,
      dateTo: customDateTo,
    );
    final Future<SalesTrend?> trendFut = period == SalesPeriod.custom
        ? Future.value(null)
        : repo
            .getSalesTrend(courtId: nextCourtId, period: periodStr)
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
