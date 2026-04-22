import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/sales_repository.dart';

enum SalesLoadStatus { idle, loading, loaded, error }

class SalesState {
  final SalesLoadStatus status;
  final SalesSummary? summary;
  final String? error;
  final int? selectedCourtId;

  const SalesState({
    this.status = SalesLoadStatus.idle,
    this.summary,
    this.error,
    this.selectedCourtId,
  });
}

class SalesNotifier extends Notifier<SalesState> {
  @override
  SalesState build() {
    fetchSummary(allCourts: true);
    return const SalesState(status: SalesLoadStatus.loading);
  }

  Future<void> fetchSummary({int? courtId, bool allCourts = false}) async {
    // Build the next selectedCourtId before the async call
    final nextCourtId = allCourts ? null : courtId;

    state = SalesState(
      status: SalesLoadStatus.loading,
      summary: state.summary,         // keep old data visible while loading
      selectedCourtId: nextCourtId,
    );

    try {
      final summary = await ref
          .read(salesRepositoryProvider)
          .getSalesSummary(courtId: nextCourtId);

      state = SalesState(
        status: SalesLoadStatus.loaded,
        summary: summary,
        selectedCourtId: nextCourtId,
      );
    } catch (e) {
      state = SalesState(
        status: SalesLoadStatus.error,
        error: e.toString(),
        selectedCourtId: nextCourtId,
      );
    }
  }
}

final salesNotifierProvider =
    NotifierProvider<SalesNotifier, SalesState>(() {
  return SalesNotifier();
});