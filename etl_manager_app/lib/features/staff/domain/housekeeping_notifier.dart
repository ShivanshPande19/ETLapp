// lib/features/staff/domain/housekeeping_notifier.dart
//
// Config-driven housekeeping state for staff (Phase 3b).
//
// Shifts, their timings, daily tasks and the weekly/monthly recurring tasks are
// all loaded dynamically from the backend (/housekeeping/status) for the
// staff's court. Nothing is hardcoded — a court can have any number of shifts
// (with any names/timings) and any number of weekly/monthly tasks.

import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../data/housekeeping_repository.dart';
import '../../../core/utils/token_storage.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/photo_upload_service.dart';
import 'housekeeping_models.dart' as hk;

// ─── State ────────────────────────────────────────────────────────────────────

class HousekeepingState {
  final int? courtId;
  final String courtName;
  final String date;
  final bool isInitialized;
  final String? error;
  final String userName;

  // Dynamic config + status (from /housekeeping/status for this court).
  final List<hk.ShiftStatus> shifts;
  final String? currentShiftKey;
  final List<hk.RecurringTaskStatus> weekly;
  final List<hk.RecurringTaskStatus> monthly;

  // Per daily-task local state, keyed '${shiftKey}_$taskId'.
  final Map<String, bool> taskDoneMap;
  final Map<String, File?> taskPhotoMap;
  final Map<String, String?> photoUrlMap;
  final Map<String, String?> doneByMap;
  final Set<String> lockedTasks;
  final Set<String> loadingTasks;

  // Per recurring-task loading, keyed by task id.
  final Set<String> loadingRecurring;

  const HousekeepingState({
    this.courtId,
    this.courtName = '',
    required this.date,
    this.isInitialized = false,
    this.error,
    this.userName = '',
    this.shifts = const [],
    this.currentShiftKey,
    this.weekly = const [],
    this.monthly = const [],
    this.taskDoneMap = const <String, bool>{},
    this.taskPhotoMap = const <String, File?>{},
    this.photoUrlMap = const <String, String?>{},
    this.doneByMap = const <String, String?>{},
    this.lockedTasks = const <String>{},
    this.loadingTasks = const <String>{},
    this.loadingRecurring = const <String>{},
  });

  // ── Current shift ──────────────────────────────────────────────────────────
  hk.ShiftStatus? get currentShift =>
      shifts.firstWhereOrNull((s) => s.shiftKey == currentShiftKey);

  bool get currentShiftActive => currentShift?.isActiveNow ?? false;

  String _k(String taskId) => '${currentShiftKey ?? ''}_$taskId';

  // ── Per daily-task helpers (for the current shift) ──────────────────────────
  bool isTaskDone(String taskId) => taskDoneMap[_k(taskId)] == true;
  bool isTaskLocked(String taskId) => lockedTasks.contains(_k(taskId));
  bool isTaskLoading(String taskId) => loadingTasks.contains(_k(taskId));
  File? taskPhoto(String taskId) => taskPhotoMap[_k(taskId)];
  String? taskPhotoUrl(String taskId) => photoUrlMap[_k(taskId)];
  String? taskDoneBy(String taskId) => doneByMap[_k(taskId)];

  // ── Recurring helpers ────────────────────────────────────────────────────
  bool isRecurringLoading(String taskId) => loadingRecurring.contains(taskId);

  hk.RecurringTaskStatus? recurringById(String taskId) =>
      weekly.firstWhereOrNull((w) => w.taskId == taskId) ??
      monthly.firstWhereOrNull((m) => m.taskId == taskId);

  int get lockedDoneCount {
    final prefix = '${currentShiftKey ?? ''}_';
    return lockedTasks.where((k) => k.startsWith(prefix)).length;
  }

  HousekeepingState copyWith({
    int? courtId,
    String? courtName,
    String? date,
    bool? isInitialized,
    String? error,
    String? userName,
    List<hk.ShiftStatus>? shifts,
    String? currentShiftKey,
    List<hk.RecurringTaskStatus>? weekly,
    List<hk.RecurringTaskStatus>? monthly,
    Map<String, bool>? taskDoneMap,
    Map<String, File?>? taskPhotoMap,
    Map<String, String?>? photoUrlMap,
    Map<String, String?>? doneByMap,
    Set<String>? lockedTasks,
    Set<String>? loadingTasks,
    Set<String>? loadingRecurring,
  }) {
    return HousekeepingState(
      courtId: courtId ?? this.courtId,
      courtName: courtName ?? this.courtName,
      date: date ?? this.date,
      isInitialized: isInitialized ?? this.isInitialized,
      error: error,
      userName: userName ?? this.userName,
      shifts: shifts ?? this.shifts,
      currentShiftKey: currentShiftKey ?? this.currentShiftKey,
      weekly: weekly ?? this.weekly,
      monthly: monthly ?? this.monthly,
      taskDoneMap: taskDoneMap ?? this.taskDoneMap,
      taskPhotoMap: taskPhotoMap ?? this.taskPhotoMap,
      photoUrlMap: photoUrlMap ?? this.photoUrlMap,
      doneByMap: doneByMap ?? this.doneByMap,
      lockedTasks: lockedTasks ?? this.lockedTasks,
      loadingTasks: loadingTasks ?? this.loadingTasks,
      loadingRecurring: loadingRecurring ?? this.loadingRecurring,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class HousekeepingNotifier extends Notifier<HousekeepingState> {
  @override
  HousekeepingState build() {
    Future.microtask(_init);
    return HousekeepingState(date: _today);
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    final zone = await TokenStorage.getZone();
    final name = await TokenStorage.getManagerName();
    final courtId = _parseZone(zone);

    state = state.copyWith(
      courtId: courtId,
      courtName: name ?? 'Staff',
      userName: name ?? 'Staff',
    );

    if (courtId != null) {
      await _rehydrateFromBackend(courtId);
    }

    state = state.copyWith(isInitialized: true);
  }

  Future<void> refresh() async {
    if (state.courtId != null) {
      await _rehydrateFromBackend(state.courtId!);
    }
  }

  // ── Rehydrate from backend (config + completions) ───────────────────────────

  Future<void> _rehydrateFromBackend(int courtId) async {
    try {
      final status = await ref
          .read(housekeepingRepoProvider)
          .getFullStatus(date: _today, courtId: courtId);
      if (status == null) return;

      final court = status.courtById(courtId);
      final shifts = court?.shifts ?? const <hk.ShiftStatus>[];
      final weekly = status.weeklyFor(courtId);
      final monthly = status.monthlyFor(courtId);

      // Build daily completion maps from the configured tasks.
      final doneMap = <String, bool>{};
      final lockedSet = <String>{};
      final photoUrls = <String, String?>{};
      final doneBy = <String, String?>{};

      for (final sh in shifts) {
        for (final t in sh.tasks) {
          if (t.isDone) {
            final key = '${sh.shiftKey}_${t.taskId}';
            doneMap[key] = true;
            lockedSet.add(key);
            if (t.photoUrl != null) photoUrls[key] = t.photoUrl;
            if (t.doneByName != null) doneBy[key] = t.doneByName;
          }
        }
      }

      // Keep the current shift if still valid, else auto-select by timings.
      final shiftKey = _pickShift(shifts, keep: state.currentShiftKey);

      state = state.copyWith(
        shifts: shifts,
        currentShiftKey: shiftKey,
        weekly: weekly,
        monthly: monthly,
        courtName: (court?.courtName.isNotEmpty ?? false)
            ? court!.courtName
            : state.courtName,
        taskDoneMap: doneMap,
        lockedTasks: lockedSet,
        photoUrlMap: photoUrls,
        doneByMap: doneBy,
      );
    } catch (e) {
      debugPrint('_rehydrateFromBackend error: $e');
    }
  }

  // ── Shift auto-selection ────────────────────────────────────────────────────

  String? _pickShift(List<hk.ShiftStatus> shifts, {String? keep}) {
    if (shifts.isEmpty) return null;
    if (keep != null && shifts.any((s) => s.shiftKey == keep)) return keep;
    final active = shifts.firstWhereOrNull((s) => s.isActiveNow);
    return (active ?? shifts.first).shiftKey;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _today => DateTime.now().toIso8601String().substring(0, 10);

  // Best-effort current position — never throws. Watermark falls back to a
  // time-only stamp on failure.
  Future<Position?> _safePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      return null;
    }
  }

  // Court id from the stored "zone". Accepts a raw integer id, or an A/B/C
  // letter (legacy courts 1/2/3), or a digit embedded in the string.
  int? _parseZone(String? zone) {
    if (zone == null) return null;
    final z = zone.trim().toUpperCase();

    final direct = int.tryParse(z);
    if (direct != null && direct >= 1) return direct;

    final letter = RegExp(r'[ABC]').firstMatch(z)?.group(0);
    if (letter != null) return const {'A': 1, 'B': 2, 'C': 3}[letter];

    final match = RegExp(r'(\d+)').firstMatch(z);
    if (match != null) {
      final n = int.tryParse(match.group(1)!);
      if (n != null && n >= 1) return n;
    }
    return null;
  }

  // ── Public mutations ──────────────────────────────────────────────────────

  void changeShift(String shiftKey) {
    if (state.currentShiftKey == shiftKey) return;
    state = state.copyWith(currentShiftKey: shiftKey, error: null);
  }

  void clearError() => state = state.copyWith(error: null);

  bool _isCooldownError(Object e) {
    final s = e.toString();
    return s.contains('COOLDOWN_ACTIVE') || s.contains('400');
  }

  // ── confirmTask ───────────────────────────────────────────────────────────

  Future<bool> confirmTask({
    required String taskId,
    required String taskTitle,
    required File photo,
    hk.HkTaskKind kind = hk.HkTaskKind.daily,
  }) async {
    if (state.courtId == null) {
      state = state.copyWith(error: 'Court not configured. Contact admin.');
      return false;
    }
    final courtId = state.courtId!;

    if (kind == hk.HkTaskKind.daily && state.currentShiftKey == null) {
      state = state.copyWith(error: 'No shift selected.');
      return false;
    }

    // Loading flag.
    if (kind == hk.HkTaskKind.daily) {
      final key = state._k(taskId);
      state = state.copyWith(
        loadingTasks: Set<String>.from(state.loadingTasks)..add(key),
        error: null,
      );
    } else {
      state = state.copyWith(
        loadingRecurring: Set<String>.from(state.loadingRecurring)..add(taskId),
        error: null,
      );
    }

    try {
      // ── Capture location for the watermark (best-effort, non-blocking) ────
      double? lat;
      double? lng;
      String? addressLine;
      try {
        final pos = await _safePosition();
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
          addressLine = await PhotoUploadService.reverseGeocode(lat, lng);
        }
      } catch (e) {
        debugPrint('housekeeping location capture failed: $e');
      }

      // ── Compress + watermark + upload ─────────────────────────────────────
      final photoUrl = await PhotoUploadService.uploadHousekeepingPhoto(
        dio: ref.read(dioProvider),
        photo: photo,
        addressLine: addressLine,
        lat: lat,
        lng: lng,
      );

      if (photoUrl == null) {
        _clearLoading(taskId, kind);
        state = state.copyWith(
          error: 'Photo upload failed. Check your connection.',
        );
        return false;
      }

      final repo = ref.read(housekeepingRepoProvider);

      if (kind == hk.HkTaskKind.weekly) {
        await repo.markWeeklyDone(
          courtId: courtId,
          taskId: taskId,
          photoUrl: photoUrl,
        );
        _applyRecurringDone(taskId, photoUrl, isWeekly: true);
        return true;
      }

      if (kind == hk.HkTaskKind.monthly) {
        await repo.markMonthlyDone(
          courtId: courtId,
          taskId: taskId,
          photoUrl: photoUrl,
        );
        _applyRecurringDone(taskId, photoUrl, isWeekly: false);
        return true;
      }

      // ── Daily task ────────────────────────────────────────────────────────
      final ok = await repo.confirmSingleTask(
        courtId: courtId,
        shiftKey: state.currentShiftKey!,
        date: state.date,
        taskId: taskId,
        taskTitle: taskTitle,
        photoUrl: photoUrl,
      );

      final key = state._k(taskId);
      if (ok) {
        state = state.copyWith(
          loadingTasks: Set<String>.from(state.loadingTasks)..remove(key),
          lockedTasks: Set<String>.from(state.lockedTasks)..add(key),
          taskDoneMap: Map<String, bool>.from(state.taskDoneMap)..[key] = true,
          taskPhotoMap: Map<String, File?>.from(state.taskPhotoMap)
            ..[key] = photo,
          photoUrlMap: Map<String, String?>.from(state.photoUrlMap)
            ..[key] = photoUrl,
          doneByMap: Map<String, String?>.from(state.doneByMap)
            ..[key] = state.userName,
          error: null,
        );
        return true;
      } else {
        _clearLoading(taskId, kind);
        state = state.copyWith(error: 'Failed to save. Please try again.');
        return false;
      }
    } catch (e) {
      debugPrint('confirmTask error: $e');
      _clearLoading(taskId, kind);

      // Backend cooldown — re-fetch to surface the accurate countdown.
      if (_isCooldownError(e)) {
        await _rehydrateFromBackend(courtId);
        state = state.copyWith(error: null);
        return false;
      }

      state = state.copyWith(error: 'Network error. Check your connection.');
      return false;
    }
  }

  void _clearLoading(String taskId, hk.HkTaskKind kind) {
    if (kind == hk.HkTaskKind.daily) {
      final key = state._k(taskId);
      state = state.copyWith(
        loadingTasks: Set<String>.from(state.loadingTasks)..remove(key),
      );
    } else {
      state = state.copyWith(
        loadingRecurring: Set<String>.from(state.loadingRecurring)
          ..remove(taskId),
      );
    }
  }

  // Optimistically mark a recurring task done with a fresh cooldown.
  void _applyRecurringDone(
    String taskId,
    String photoUrl, {
    required bool isWeekly,
  }) {
    final now = DateTime.now();
    final list = isWeekly ? state.weekly : state.monthly;
    final updated = list.map((r) {
      if (r.taskId != taskId) return r;
      return r.copyWith(
        lastDoneAt: now,
        nextDueAt: now.add(Duration(days: r.intervalDays)),
        photoUrl: photoUrl,
        doneByName: state.userName,
        isOverdue: false,
      );
    }).toList();

    state = state.copyWith(
      loadingRecurring: Set<String>.from(state.loadingRecurring)
        ..remove(taskId),
      weekly: isWeekly ? updated : null,
      monthly: isWeekly ? null : updated,
      error: null,
    );
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final housekeepingNotifierProvider =
    NotifierProvider<HousekeepingNotifier, HousekeepingState>(
      HousekeepingNotifier.new,
    );
