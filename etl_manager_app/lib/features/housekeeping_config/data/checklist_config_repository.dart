import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'checklist_config_models.dart';

class ChecklistConfigRepository {
  final Dio _dio;
  ChecklistConfigRepository(this._dio);

  /// Full config for a court (backend seeds the legacy default if none yet).
  Future<ChecklistDraft> getConfig(int courtId) async {
    final res = await _dio.get('/housekeeping/config',
        queryParameters: {'court_id': courtId});
    return ChecklistDraft.fromJson(res.data as Map<String, dynamic>);
  }

  /// A fresh editable template (for pre-filling a brand-new court).
  Future<ChecklistDraft> getTemplate() async {
    final res = await _dio.get('/housekeeping/config/template');
    return ChecklistDraft.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ChecklistDraft> saveConfig(int courtId, ChecklistDraft draft) async {
    final res = await _dio.put(
      '/housekeeping/config',
      queryParameters: {'court_id': courtId},
      data: draft.toJson(),
    );
    return ChecklistDraft.fromJson(res.data as Map<String, dynamic>);
  }
}

final checklistConfigRepositoryProvider =
    Provider<ChecklistConfigRepository>((ref) {
  return ChecklistConfigRepository(ref.watch(dioProvider));
});
