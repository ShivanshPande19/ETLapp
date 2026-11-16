// lib/features/staff/data/housekeeping_repository.dart

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../domain/housekeeping_models.dart';

class HousekeepingRepository {
  final Dio dio;
  HousekeepingRepository(this.dio);

  // ── Confirm a single daily task (photo already uploaded, just POST) ───────
  // Used by the staff checklist — one task at a time, then locked.

  Future<bool> confirmSingleTask({
    required int courtId,
    required String shiftKey,
    required String date,
    required String taskId,
    required String taskTitle,
    String? photoUrl,
    int? submittedBy,
  }) async {
    try {
      final req = ShiftSubmitRequest(
        courtId: courtId,
        shiftKey: shiftKey,
        date: date,
        tasks: [
          TaskSubmitItem(
            taskId: taskId,
            taskTitle: taskTitle,
            isDone: true,
            photoUrl: photoUrl,
            doneAt: DateTime.now(),
          ),
        ],
        submittedBy: submittedBy,
      );
      final response = await dio.post(
        '/housekeeping/submit',
        data: req.toJson(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('confirmSingleTask error: $e');
      return false;
    }
  }

  // ── Mark a weekly recurring task done (accepts already-uploaded URL) ───────
  // [taskId] targets a specific configured weekly task. If null, the backend
  // resolves the court's first weekly task (legacy = flagswash).
  // Throws on COOLDOWN_ACTIVE so the notifier can surface the countdown.

  Future<bool> markWeeklyDone({
    required int courtId,
    String? taskId,
    String? photoUrl,
    int? doneBy,
  }) async {
    await dio.patch(
      '/housekeeping/weekly',
      data: {
        'court_id': courtId,
        'task_id': taskId,
        'photo_url': photoUrl,
        'done_by': doneBy,
      },
    );
    return true;
  }

  // ── Mark a monthly recurring task done (accepts already-uploaded URL) ──────

  Future<bool> markMonthlyDone({
    required int courtId,
    String? taskId,
    String? photoUrl,
    int? doneBy,
  }) async {
    await dio.patch(
      '/housekeeping/monthly',
      data: {
        'court_id': courtId,
        'task_id': taskId,
        'photo_url': photoUrl,
        'done_by': doneBy,
      },
    );
    return true;
  }

  // ── Full status for staff/manager screens (config-driven) ─────────────────

  /// Like [getFullStatus], but a failure THROWS instead of reading as null.
  ///
  /// The staff checklist needs to tell "couldn't load" from "nothing
  /// configured". Folding both into null is what made a failed load show
  /// "This court has no housekeeping checklist configured" to staff whose
  /// court had a full checklist.
  Future<FullStatusResponse> fetchFullStatus({String? date, int? courtId}) async {
    final today = date ?? DateTime.now().toIso8601String().substring(0, 10);
    final res = await dio.get(
      '/housekeeping/status',
      queryParameters: {
        'date': today,
        if (courtId != null) 'court_id': courtId,
      },
    );
    return FullStatusResponse.fromJson(res.data);
  }

  /// Null on any failure. Kept for the screens that only need best-effort
  /// data (home widgets, manager view, history); see [fetchFullStatus].
  Future<FullStatusResponse?> getFullStatus({String? date, int? courtId}) async {
    try {
      return await fetchFullStatus(date: date, courtId: courtId);
    } catch (e) {
      debugPrint('getFullStatus error: $e');
      return null;
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final housekeepingRepoProvider = Provider<HousekeepingRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return HousekeepingRepository(dio);
});
