import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dashboard_repository.dart';

enum LoadStatus { idle, loading, loaded, error }

class DashboardState {
  final LoadStatus status;
  final DashboardSummaryModel? summary;
  final String? error;

  const DashboardState({
    this.status = LoadStatus.idle,
    this.summary,
    this.error,
  });

  DashboardState copyWith({
    LoadStatus? status,
    DashboardSummaryModel? summary,
    String? error,
  }) {
    return DashboardState(
      status: status ?? this.status,
      summary: summary ?? this.summary,
      error: error ?? this.error,
    );
  }
}

class DashboardNotifier extends Notifier<DashboardState> {
  @override
  DashboardState build() {
    fetchSummary();
    return const DashboardState(status: LoadStatus.loading);
  }

  Future<void> fetchSummary() async {
    state = state.copyWith(status: LoadStatus.loading);
    try {
      final summary = await ref.read(dashboardRepositoryProvider).getSummary();
      state = state.copyWith(status: LoadStatus.loaded, summary: summary);
    } catch (e) {
      state = state.copyWith(status: LoadStatus.error, error: e.toString());
    }
  }
}

final dashboardNotifierProvider =
    NotifierProvider<DashboardNotifier, DashboardState>(() {
  return DashboardNotifier();
});