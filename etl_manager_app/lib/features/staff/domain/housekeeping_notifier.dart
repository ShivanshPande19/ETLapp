// lib/features/staff/domain/housekeeping_notifier.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/housekeeping_repository.dart';
import '../../../core/utils/token_storage.dart';
import '../../../core/cloudinary/cloudinary_service.dart';
import 'housekeeping_models.dart' as hk;

// ─── State ────────────────────────────────────────────────────────────────────

class HousekeepingState {
  final int? courtId;
  final String courtName;
  final hk.Shift shift;
  final String date;
  final bool isInitialized;
  final String? error;

  // All maps are keyed as "${shift.name}_${taskId}" (e.g. "night_floorclean").
  // This lets all shifts coexist in the same state — switching shifts just
  // changes which slice is visible, nothing is ever wiped mid-session.
  final Map<String, bool> taskDoneMap;
  final Map<String, File?> taskPhotoMap;
  final Map<String, String?> photoUrlMap;
  final Set<String> lockedTasks;
  final Set<String> loadingTasks;

  const HousekeepingState({
    this.courtId,
    this.courtName = '',
    required this.shift,
    required this.date,
    this.isInitialized = false,
    this.error,
    this.taskDoneMap = const <String, bool>{},
    this.taskPhotoMap = const <String, File?>{},
    this.photoUrlMap = const <String, String?>{},
    this.lockedTasks = const <String>{},
    this.loadingTasks = const <String>{},
  });

  // ── Internal key: "shift_taskId" ──────────────────────────────────────────
  String _k(String taskId) => '${shift.name}_$taskId';

  // ── Per-task helpers called by the checklist screen ───────────────────────
  bool isTaskDone(String taskId) => taskDoneMap[_k(taskId)] == true;
  bool isTaskLocked(String taskId) => lockedTasks.contains(_k(taskId));
  bool isTaskLoading(String taskId) => loadingTasks.contains(_k(taskId));
  File? taskPhoto(String taskId) => taskPhotoMap[_k(taskId)];

  /// Count of locked tasks for the CURRENT shift only.
  int get lockedDoneCount =>
      lockedTasks.where((k) => k.startsWith('${shift.name}_')).length;

  HousekeepingState copyWith({
    int? courtId,
    String? courtName,
    hk.Shift? shift,
    String? date,
    bool? isInitialized,
    String? error,
    Map<String, bool>? taskDoneMap,
    Map<String, File?>? taskPhotoMap,
    Map<String, String?>? photoUrlMap,
    Set<String>? lockedTasks,
    Set<String>? loadingTasks,
  }) {
    return HousekeepingState(
      courtId: courtId ?? this.courtId,
      courtName: courtName ?? this.courtName,
      shift: shift ?? this.shift,
      date: date ?? this.date,
      isInitialized: isInitialized ?? this.isInitialized,
      error: error, // null intentionally clears error
      taskDoneMap: taskDoneMap ?? this.taskDoneMap,
      taskPhotoMap: taskPhotoMap ?? this.taskPhotoMap,
      photoUrlMap: photoUrlMap ?? this.photoUrlMap,
      lockedTasks: lockedTasks ?? this.lockedTasks,
      loadingTasks: loadingTasks ?? this.loadingTasks,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class HousekeepingNotifier extends Notifier<HousekeepingState> {
  @override
  HousekeepingState build() {
    Future.microtask(_init);
    return HousekeepingState(shift: _autoShift, date: _today);
  }

  // ── Init: load courtId from token storage ─────────────────────────────────

  Future<void> _init() async {
    final zone = await TokenStorage.getZone();
    final name = await TokenStorage.getManagerName();
    state = state.copyWith(
      courtId: _parseZone(zone),
      courtName: name ?? 'Staff',
      isInitialized: true,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _today => DateTime.now().toIso8601String().substring(0, 10);

  hk.Shift get _autoShift {
    final h = DateTime.now().hour;
    if (h >= 6 && h < 12) return hk.Shift.morning;
    if (h >= 12 && h < 17) return hk.Shift.day;
    return hk.Shift.night;
  }

  int? _parseZone(String? zone) {
    if (zone == null) return null;
    final z = zone.trim().toUpperCase();

    // Direct number: "1", "2", "3"
    final direct = int.tryParse(z);
    if (direct != null && direct >= 1 && direct <= 3) return direct;

    // Letter-based: "Zone A" → 1, "Zone B" → 2, "Zone C" → 3
    final letter = RegExp(r'[ABC]').firstMatch(z)?.group(0);
    if (letter != null) {
      return const {'A': 1, 'B': 2, 'C': 3}[letter];
    }

    // Digit in string: "Zone 1", "court-2"
    final match = RegExp(r'(\d)').firstMatch(z);
    if (match != null) {
      final n = int.tryParse(match.group(1)!);
      if (n != null && n >= 1 && n <= 3) return n;
    }

    return null;
  }

  // ── Public mutations ──────────────────────────────────────────────────────

  /// Switch shift — state for ALL shifts is preserved in the same maps.
  /// Switching back to night after visiting day still shows night completions.
  void changeShift(hk.Shift shift) {
    if (state.shift == shift) return;
    state = state.copyWith(shift: shift, error: null);
  }

  void clearError() => state = state.copyWith(error: null);

  // ── confirmTask ───────────────────────────────────────────────────────────
  // flow: mark loading → upload photo to Cloudinary → POST backend → lock.

  Future<bool> confirmTask({
    required String taskId,
    required String taskTitle,
    required File photo,
  }) async {
    if (state.courtId == null) {
      state = state.copyWith(error: 'Court ID not configured. Contact admin.');
      return false;
    }

    final key = state._k(taskId); // e.g. "night_floorclean"

    // Step 1: mark loading
    state = state.copyWith(
      loadingTasks: Set<String>.from(state.loadingTasks)..add(key),
      error: null,
    );

    try {
      final date = state.date;
      final courtId = state.courtId!;

      // Step 2: upload photo to Cloudinary
      String? photoUrl;
      if (taskId == 'flagswash') {
        photoUrl = await HousekeepingStorageService.uploadWeeklyPhoto(
          photo: photo,
          courtId: courtId,
          date: date,
        );
      } else if (taskId == 'fireaudit') {
        photoUrl = await HousekeepingStorageService.uploadMonthlyPhoto(
          photo: photo,
          courtId: courtId,
          date: date,
        );
      } else {
        photoUrl = await HousekeepingStorageService.uploadTaskPhoto(
          photo: photo,
          courtId: courtId,
          shift: state.shift.name,
          date: date,
          taskId: taskId,
        );
      }

      // Step 3: POST to backend
      bool success;
      if (taskId == 'flagswash') {
        success = await ref
            .read(housekeepingRepoProvider)
            .markWeeklyDone(courtId: courtId, photoUrl: photoUrl);
      } else if (taskId == 'fireaudit') {
        success = await ref
            .read(housekeepingRepoProvider)
            .markMonthlyDone(courtId: courtId, photoUrl: photoUrl);
      } else {
        success = await ref
            .read(housekeepingRepoProvider)
            .confirmSingleTask(
              courtId: courtId,
              shift: state.shift,
              date: date,
              taskId: taskId,
              taskTitle: taskTitle,
              photoUrl: photoUrl,
            );
      }

      // Step 4: update state with shift-prefixed key
      final newLoading = Set<String>.from(state.loadingTasks)..remove(key);

      if (success) {
        state = state.copyWith(
          loadingTasks: newLoading,
          lockedTasks: Set<String>.from(state.lockedTasks)..add(key),
          taskDoneMap: Map<String, bool>.from(state.taskDoneMap)..[key] = true,
          taskPhotoMap: Map<String, File?>.from(state.taskPhotoMap)
            ..[key] = photo,
          photoUrlMap: Map<String, String?>.from(state.photoUrlMap)
            ..[key] = photoUrl,
          error: null,
        );
        return true;
      } else {
        state = state.copyWith(
          loadingTasks: newLoading,
          error: 'Failed to save. Please try again.',
        );
        return false;
      }
    } catch (e) {
      debugPrint('confirmTask error: $e');
      state = state.copyWith(
        loadingTasks: Set<String>.from(state.loadingTasks)..remove(key),
        error: 'Network error. Check your connection.',
      );
      return false;
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final housekeepingNotifierProvider =
    NotifierProvider<HousekeepingNotifier, HousekeepingState>(
      HousekeepingNotifier.new,
    );
