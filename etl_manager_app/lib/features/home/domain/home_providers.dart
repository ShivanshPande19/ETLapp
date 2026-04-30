// lib/features/home/domain/home_providers.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../complaints/data/complaints_repository.dart';
import '../../staff/data/housekeeping_repository.dart';

class HkHomeSummary {
  final int done;
  final int total;
  const HkHomeSummary({required this.done, required this.total});
  double get pct => total == 0 ? 0.0 : done / total;
  int get pending => total - done;
}

final homeComplaintsProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final complaints = await ref
        .read(complaintsRepoProvider)
        .getComplaints(status: 'open');
    return complaints.length;
  } catch (_) {
    return 0;
  }
});

final homeMaintenanceProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final dio = ref.read(dioProvider);
    final res = await dio.get<dynamic>(
      '/maintenance',
      queryParameters: {'status': 'open'},
    );
    final data = res.data;
    if (data is List) return data.length;
    if (data is Map && data.containsKey('issues')) {
      return (data['issues'] as List).length;
    }
    return 0;
  } on DioException {
    return 0;
  } catch (_) {
    return 0;
  }
});

final homeHousekeepingProvider = FutureProvider.autoDispose<HkHomeSummary>((
  ref,
) async {
  try {
    final status = await ref.read(housekeepingRepoProvider).getFullStatus();
    if (status == null) return const HkHomeSummary(done: 0, total: 0);
    int done = 0, total = 0;
    for (final court in status.courts) {
      for (final shift in court.shifts) {
        done += shift.done;
        total += shift.total;
      }
    }
    return HkHomeSummary(done: done, total: total);
  } catch (_) {
    return const HkHomeSummary(done: 0, total: 0);
  }
});
