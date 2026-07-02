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

class SalesNotifier extends Notifier<SalesState> {
  @override
  SalesState build() {
    Future.microtask(
      () => fetchSummary(allCourts: true, period: SalesPeriod.yesterday),
    );
    return const SalesState(status: SalesLoadStatus.loading);
  }

  Future<void> fetchSummary({
    int? courtId,
    bool allCourts = false,
    SalesPeriod period = SalesPeriod.yesterday,
    String? customDateFrom,
    String? customDateTo,
  }) async {
    final nextCourtId = allCourts ? null : courtId;

    state = SalesState(
      status: SalesLoadStatus.loading,
      summary: state.summary,
      trend: state.trend,
      selectedCourtId: nextCourtId,
      period: period,
      customDateFrom: customDateFrom,
      customDateTo: customDateTo,
    );

    try {
      // API string convertor
      String periodStr;
      switch (period) {
        case SalesPeriod.yesterday:
          periodStr = 'yesterday';
          break;
        case SalesPeriod.week:
          periodStr = 'this_week';
          break;
        case SalesPeriod.month:
          periodStr = 'this_month';
          break;
        case SalesPeriod.year:
          periodStr = 'this_year';
          break;
        case SalesPeriod.custom:
          periodStr = 'custom';
          break;
      }

      final repo = ref.read(salesRepositoryProvider);

      // Summary is the primary payload; the trend chart is best-effort so a
      // trend failure never blocks the numbers. Custom (single date) has no
      // meaningful series, so skip it.
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

      final results = await Future.wait([summaryFut, trendFut]);
      final summary = results[0] as SalesSummary;
      final trend = results[1] as SalesTrend?;

      state = SalesState(
        status: SalesLoadStatus.loaded,
        summary: summary,
        trend: trend,
        selectedCourtId: nextCourtId,
        period: period,
        customDateFrom: customDateFrom,
        customDateTo: customDateTo,
      );
    } catch (e) {
      state = SalesState(
        status: SalesLoadStatus.error,
        error: e.toString(),
        trend: state.trend,
        selectedCourtId: nextCourtId,
        period: period,
      );
    }
  }
}

final salesNotifierProvider = NotifierProvider<SalesNotifier, SalesState>(
  SalesNotifier.new,
);
