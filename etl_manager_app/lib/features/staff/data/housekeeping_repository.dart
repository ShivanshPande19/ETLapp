// lib/features/staff/data/housekeeping_repository.dart

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/cloudinary/cloudinary_service.dart';
import '../domain/housekeeping_models.dart';

class HousekeepingRepository {
  final Dio dio;
  HousekeepingRepository(this.dio);

  // ── Confirm a single task (upload already done, just POST) ────────────────
  // Used by staff checklist — one task at a time, immediately locked.

  Future<bool> confirmSingleTask({
    required int courtId,
    required Shift shift,
    required String date,
    required String taskId,
    required String taskTitle,
    String? photoUrl,
    int? submittedBy,
  }) async {
    try {
      final req = ShiftSubmitRequest(
        courtId: courtId,
        shift: shift,
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

  // ── Mark flags washing done (weekly) — accepts already-uploaded URL ────────

  Future<bool> markWeeklyDone({
    required int courtId,
    String? photoUrl, // pass URL after uploading via HousekeepingStorageService
    int? doneBy,
  }) async {
    try {
      await dio.patch(
        '/housekeeping/weekly',
        data: {'court_id': courtId, 'photo_url': photoUrl, 'done_by': doneBy},
      );
      return true;
    } catch (e) {
      debugPrint('markWeeklyDone error: $e');
      return false;
    }
  }

  // ── Mark fire safety audit done (monthly) — accepts already-uploaded URL ──

  Future<bool> markMonthlyDone({
    required int courtId,
    String? photoUrl, // pass URL after uploading via HousekeepingStorageService
    int? doneBy,
  }) async {
    try {
      await dio.patch(
        '/housekeeping/monthly',
        data: {'court_id': courtId, 'photo_url': photoUrl, 'done_by': doneBy},
      );
      return true;
    } catch (e) {
      debugPrint('markMonthlyDone error: $e');
      return false;
    }
  }

  // ── Full status for manager screen ────────────────────────────────────────
  // FIX: named parameter {String? date} so manager screen can call
  //      getFullStatus(date: dateStr) without error.

  Future<FullStatusResponse?> getFullStatus({String? date}) async {
    try {
      final today = date ?? DateTime.now().toIso8601String().substring(0, 10);
      final res = await dio.get(
        '/housekeeping/status',
        queryParameters: {'date': today},
      );
      return FullStatusResponse.fromJson(res.data);
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
