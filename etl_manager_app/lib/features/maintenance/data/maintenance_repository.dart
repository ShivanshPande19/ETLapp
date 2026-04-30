// lib/features/maintenance/data/maintenance_repository.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../domain/maintenance_model.dart';

class MaintenanceRepository {
  const MaintenanceRepository(this._dio);
  final Dio _dio;

  Future<List<MaintenanceIssue>> getIssues({
    int? courtId,
    String? status,
  }) async {
    final Map<String, dynamic> params = {};
    if (courtId != null) params['court_id'] = courtId;
    if (status != null) params['status'] = status;

    final res = await _dio.get('/maintenance', queryParameters: params);
    return (res.data as List)
        .map((j) => MaintenanceIssue.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<MaintenanceIssue> updateStatus(int id, String newStatus) async {
    final res = await _dio.patch(
      '/maintenance/$id',
      data: {'status': newStatus},
    );
    return MaintenanceIssue.fromJson(res.data as Map<String, dynamic>);
  }
}

final maintenanceRepoProvider = Provider<MaintenanceRepository>((ref) {
  return MaintenanceRepository(ref.read(dioProvider));
});

final maintenanceProvider = FutureProvider.autoDispose<List<MaintenanceIssue>>((
  ref,
) async {
  return ref.read(maintenanceRepoProvider).getIssues();
});
