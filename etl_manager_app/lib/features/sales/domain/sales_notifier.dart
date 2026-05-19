import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sales_repository.dart';

enum SalesLoadStatus { idle, loading, loaded, error }

enum SalesPeriod { yesterday, week, month, year, custom }

class SalesState {
  final SalesLoadStatus status;
  final SalesSummary? summary;
  final String? error;
  final int? selectedCourtId;
  final SalesPeriod period;
  final String? customDateFrom;
  final String? customDateTo;

  const SalesState({
    this.status = SalesLoadStatus.idle,
    this.summary,
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

      final summary = await ref
          .read(salesRepositoryProvider)
          .getSalesSummary(
            courtId: nextCourtId,
            period: periodStr,
            dateFrom: customDateFrom,
            dateTo: customDateTo,
          );

      state = SalesState(
        status: SalesLoadStatus.loaded,
        summary: summary,
        selectedCourtId: nextCourtId,
        period: period,
        customDateFrom: customDateFrom,
        customDateTo: customDateTo,
      );
    } catch (e) {
      state = SalesState(
        status: SalesLoadStatus.error,
        error: e.toString(),
        selectedCourtId: nextCourtId,
        period: period,
      );
    }
  }
}

final salesNotifierProvider = NotifierProvider<SalesNotifier, SalesState>(
  SalesNotifier.new,
);
