// lib/features/tasks/data/team_tasks_repository.dart

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/photo_upload_service.dart';
import 'team_task_models.dart';

/// Talks to `/tasks`. Every method THROWS on failure — the notifier decides
/// what the user sees. (A null-on-failure contract is exactly what once made a
/// failed checklist load look like "nothing configured".)
class TeamTasksRepository {
  final Dio _dio;
  TeamTasksRepository(this._dio);

  Future<TaskPage> list({
    required TaskBox box,
    required TaskFilter filter,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/tasks/',
      queryParameters: {
        'box': box == TaskBox.mine ? 'mine' : 'sent',
        'status': filter.name,
        'limit': limit,
        'offset': offset,
      },
    );
    return TaskPage.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<TaskSummary> summary() async {
    final res = await _dio.get('/tasks/summary');
    return TaskSummary.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<List<TaskPerson>> people() async {
    final res = await _dio.get('/tasks/people');
    return (res.data as List)
        .map((e) => TaskPerson.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TeamTask> detail(int id) async => _task(await _dio.get('/tasks/$id'));

  Future<TeamTask> create(NewTaskDraft draft) async =>
      _task(await _dio.post('/tasks/', data: draft.toJson()));

  Future<TeamTask> markSeen(int id) async =>
      _task(await _dio.post('/tasks/$id/seen'));

  Future<TeamTask> start(int id) async =>
      _task(await _dio.post('/tasks/$id/start'));

  Future<TeamTask> complete(
    int id, {
    String? note,
    List<String> photos = const [],
  }) async => _task(
    await _dio.post(
      '/tasks/$id/complete',
      data: {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'photos': photos,
      },
    ),
  );

  Future<TeamTask> reopen(int id, String note) async =>
      _task(await _dio.post('/tasks/$id/reopen', data: {'note': note}));

  Future<TeamTask> cancel(int id, {String? note}) async => _task(
    await _dio.post(
      '/tasks/$id/cancel',
      data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    ),
  );

  Future<TeamTask> comment(int id, String note) async =>
      _task(await _dio.post('/tasks/$id/comments', data: {'note': note}));

  /// Compress and upload one proof photo. Returns its server path, or null if
  /// the upload did not go through.
  Future<String?> uploadPhoto(File photo) =>
      PhotoUploadService.uploadTaskPhoto(dio: _dio, photo: photo);

  TeamTask _task(Response res) =>
      TeamTask.fromJson(Map<String, dynamic>.from(res.data as Map));
}

final teamTasksRepositoryProvider = Provider<TeamTasksRepository>(
  (ref) => TeamTasksRepository(ref.watch(dioProvider)),
);

/// Turns a failed call into one sentence a person can act on.
String taskErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (data is Map &&
        data['detail'] is List &&
        (data['detail'] as List).isNotEmpty) {
      // FastAPI validation errors: [{"msg": "Value error, Give the task a title."}]
      final first = (data['detail'] as List).first;
      if (first is Map && first['msg'] is String) {
        return (first['msg'] as String).replaceFirst('Value error, ', '');
      }
    }
    if (error.response == null) return 'Check your internet and try again.';
  }
  return 'Something went wrong. Please try again.';
}
