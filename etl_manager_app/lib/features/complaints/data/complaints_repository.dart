// lib/features/complaints/data/complaints_repository.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../domain/complaint_model.dart';

// ─── Repository ───────────────────────────────────────────────────────────────

class ComplaintsRepository {
  const ComplaintsRepository(this._dio);
  final Dio _dio;

  /// Fetch all complaints. Optional filters: courtId, status.
  Future<List<ComplaintModel>> getComplaints({
    int? courtId,
    String? status,
  }) async {
    final Map<String, dynamic> params = {};
    if (courtId != null) params['court_id'] = courtId;
    if (status != null) params['status'] = status;

    final res = await _dio.get('/complaints', queryParameters: params);
    return (res.data as List)
        .map((j) => ComplaintModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Update the status of a single complaint.
  Future<ComplaintModel> updateStatus(int id, String newStatus) async {
    final res = await _dio.patch(
      '/complaints/$id',
      data: {'status': newStatus},
    );
    return ComplaintModel.fromJson(res.data as Map<String, dynamic>);
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final complaintsRepoProvider = Provider<ComplaintsRepository>((ref) {
  return ComplaintsRepository(ref.read(dioProvider));
});

final complaintsProvider = FutureProvider.autoDispose<List<ComplaintModel>>((
  ref,
) async {
  return ref.read(complaintsRepoProvider).getComplaints();
});
