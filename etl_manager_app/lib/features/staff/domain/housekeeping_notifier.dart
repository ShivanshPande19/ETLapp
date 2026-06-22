// lib/features/staff/domain/housekeeping_notifier.dart

import 'dart:io';
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
  final hk.Shift shift;
  final String date;
  final bool isInitialized;
  final String? error;

  final Map<String, bool> taskDoneMap;
  final Map<String, File?> taskPhotoMap;
  final Map<String, String?> photoUrlMap;
  final Set<String> lockedTasks;
  final Set<String> loadingTasks;

  // ✅ Cooldown fields
  final int weeklyRemainingDays;
  final int monthlyRemainingDays;
  final DateTime? weeklyNextDue;
  final DateTime? monthlyNextDue;

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
    this.weeklyRemainingDays = 0,
    this.monthlyRemainingDays = 0,
    this.weeklyNextDue,
    this.monthlyNextDue,
  });

  // ── Internal key ──────────────────────────────────────────────────────────
  String _k(String taskId) => '${shift.name}_$taskId';

  // ── Per-task helpers ──────────────────────────────────────────────────────
  bool isTaskDone(String taskId) => taskDoneMap[_k(taskId)] == true;
  bool isTaskLocked(String taskId) => lockedTasks.contains(_k(taskId));
  bool isTaskLoading(String taskId) => loadingTasks.contains(_k(taskId));
  File? taskPhoto(String taskId) => taskPhotoMap[_k(taskId)];
  String? taskPhotoUrl(String taskId) => photoUrlMap[_k(taskId)];

  // ✅ Cooldown helpers
  bool get isWeeklyCooldown => weeklyRemainingDays > 0;
  bool get isMonthlyCooldown => monthlyRemainingDays > 0;

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
    int? weeklyRemainingDays,
    int? monthlyRemainingDays,
    DateTime? weeklyNextDue,
    DateTime? monthlyNextDue,
  }) {
    return HousekeepingState(
      courtId: courtId ?? this.courtId,
      courtName: courtName ?? this.courtName,
      shift: shift ?? this.shift,
      date: date ?? this.date,
      isInitialized: isInitialized ?? this.isInitialized,
      error: error,
      taskDoneMap: taskDoneMap ?? this.taskDoneMap,
      taskPhotoMap: taskPhotoMap ?? this.taskPhotoMap,
      photoUrlMap: photoUrlMap ?? this.photoUrlMap,
      lockedTasks: lockedTasks ?? this.lockedTasks,
      loadingTasks: loadingTasks ?? this.loadingTasks,
      weeklyRemainingDays: weeklyRemainingDays ?? this.weeklyRemainingDays,
      monthlyRemainingDays: monthlyRemainingDays ?? this.monthlyRemainingDays,
      weeklyNextDue: weeklyNextDue ?? this.weeklyNextDue,
      monthlyNextDue: monthlyNextDue ?? this.monthlyNextDue,
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

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    final zone = await TokenStorage.getZone();
    final name = await TokenStorage.getManagerName();
    final courtId = _parseZone(zone);

    state = state.copyWith(courtId: courtId, courtName: name ?? 'Staff');

    if (courtId != null) {
      await _rehydrateFromBackend(courtId);
    }

    state = state.copyWith(isInitialized: true);
  }

  // ── Rehydrate ─────────────────────────────────────────────────────────────

  Future<void> _rehydrateFromBackend(int courtId) async {
    try {
      final status = await ref
          .read(housekeepingRepoProvider)
          .getFullStatus(date: _today);

      if (status == null) return;

      final newDoneMap = Map<String, bool>.from(state.taskDoneMap);
      final newLocked = Set<String>.from(state.lockedTasks);
      final newPhotoUrls = Map<String, String?>.from(state.photoUrlMap);

      // ── 1. Daily shift tasks ─────────────────────────────────────────────
      final courtData = status.courts
          .where((c) => c.courtId == courtId)
          .firstOrNull;

      if (courtData != null) {
        for (final shiftStatus in courtData.shifts) {
          final shiftName = shiftStatus.shift.name;
          for (final task in shiftStatus.tasks) {
            if (task.isDone) {
              final key = '${shiftName}_${task.taskId}';
              newDoneMap[key] = true;
              newLocked.add(key);
              if (task.photoUrl != null) newPhotoUrls[key] = task.photoUrl;
            }
          }
        }
      }

      // ── 2. Weekly — cooldown logic ───────────────────────────────────────
      final weeklyEntry = status.weeklyTasks
          .where((w) => w.courtId == courtId)
          .firstOrNull;

      int weeklyRemaining = 0;
      DateTime? weeklyNextDue;

      if (weeklyEntry != null) {
        if (weeklyEntry.isCooldownActive) {
          // ✅ Still in 7-day cooldown — lock + show countdown
          weeklyRemaining = weeklyEntry.remainingDays;
          weeklyNextDue = weeklyEntry.nextDueAt;
          for (final s in ['morning', 'day', 'night']) {
            final key = '${s}_flagswash';
            newDoneMap[key] = true;
            newLocked.add(key);
            if (weeklyEntry.photoUrl != null) {
              newPhotoUrls[key] = weeklyEntry.photoUrl;
            }
          }
        } else if (_isDoneThisWeek(weeklyEntry.lastDoneAt)) {
          // Done this week but cooldown expired — still show as done/locked
          for (final s in ['morning', 'day', 'night']) {
            final key = '${s}_flagswash';
            newDoneMap[key] = true;
            newLocked.add(key);
            if (weeklyEntry.photoUrl != null) {
              newPhotoUrls[key] = weeklyEntry.photoUrl;
            }
          }
        }
      }

      // ── 3. Monthly — cooldown logic ──────────────────────────────────────
      final monthlyEntry = status.monthlyTasks
          .where((m) => m.courtId == courtId)
          .firstOrNull;

      int monthlyRemaining = 0;
      DateTime? monthlyNextDue;

      if (monthlyEntry != null) {
        if (monthlyEntry.isCooldownActive) {
          // ✅ Still in 30-day cooldown — lock + show countdown
          monthlyRemaining = monthlyEntry.remainingDays;
          monthlyNextDue = monthlyEntry.nextDueAt;
          for (final s in ['morning', 'day', 'night']) {
            final key = '${s}_fireaudit';
            newDoneMap[key] = true;
            newLocked.add(key);
            if (monthlyEntry.photoUrl != null) {
              newPhotoUrls[key] = monthlyEntry.photoUrl;
            }
          }
        } else if (_isDoneThisMonth(monthlyEntry.lastDoneAt)) {
          // Done this month but cooldown expired
          for (final s in ['morning', 'day', 'night']) {
            final key = '${s}_fireaudit';
            newDoneMap[key] = true;
            newLocked.add(key);
            if (monthlyEntry.photoUrl != null) {
              newPhotoUrls[key] = monthlyEntry.photoUrl;
            }
          }
        }
      }

      state = state.copyWith(
        taskDoneMap: newDoneMap,
        lockedTasks: newLocked,
        photoUrlMap: newPhotoUrls,
        weeklyRemainingDays: weeklyRemaining,
        monthlyRemainingDays: monthlyRemaining,
        weeklyNextDue: weeklyNextDue,
        monthlyNextDue: monthlyNextDue,
      );
    } catch (e) {
      debugPrint('_rehydrateFromBackend error: $e');
    }
  }

  // ── Date helpers ──────────────────────────────────────────────────────────

  bool _isDoneThisWeek(DateTime? lastDoneAt) {
    if (lastDoneAt == null) return false;
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1),
    );
    final done = DateTime(lastDoneAt.year, lastDoneAt.month, lastDoneAt.day);
    return !done.isBefore(weekStart);
  }

  bool _isDoneThisMonth(DateTime? lastDoneAt) {
    if (lastDoneAt == null) return false;
    final now = DateTime.now();
    return lastDoneAt.year == now.year && lastDoneAt.month == now.month;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _today => DateTime.now().toIso8601String().substring(0, 10);

  // Best-effort current position — never throws, returns null on any failure
  // (permissions denied, services off, timeout). Watermark falls back to a
  // time-only stamp in that case.
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

  hk.Shift get _autoShift {
    final h = DateTime.now().hour;
    if (h >= 6 && h < 12) return hk.Shift.morning;
    if (h >= 12 && h < 17) return hk.Shift.day;
    return hk.Shift.night;
  }

  int? _parseZone(String? zone) {
    if (zone == null) return null;
    final z = zone.trim().toUpperCase();

    final direct = int.tryParse(z);
    if (direct != null && direct >= 1 && direct <= 3) return direct;

    final letter = RegExp(r'[ABC]').firstMatch(z)?.group(0);
    if (letter != null) return const {'A': 1, 'B': 2, 'C': 3}[letter];

    final match = RegExp(r'(\d)').firstMatch(z);
    if (match != null) {
      final n = int.tryParse(match.group(1)!);
      if (n != null && n >= 1 && n <= 3) return n;
    }
    return null;
  }

  // ── Public mutations ──────────────────────────────────────────────────────

  void changeShift(hk.Shift shift) {
    if (state.shift == shift) return;
    state = state.copyWith(shift: shift, error: null);
  }

  void clearError() => state = state.copyWith(error: null);

  // ── confirmTask ───────────────────────────────────────────────────────────

  Future<bool> confirmTask({
    required String taskId,
    required String taskTitle,
    required File photo,
  }) async {
    if (state.courtId == null) {
      state = state.copyWith(error: 'Court ID not configured. Contact admin.');
      return false;
    }

    final key = state._k(taskId);

    state = state.copyWith(
      loadingTasks: Set<String>.from(state.loadingTasks)..add(key),
      error: null,
    );

    try {
      final date = state.date;
      final courtId = state.courtId!;

      // ── Capture location for the watermark (best-effort, non-blocking) ───
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

      // ── Compress + watermark + upload to Railway volume ──────────────────
      final photoUrl = await PhotoUploadService.uploadHousekeepingPhoto(
        dio: ref.read(dioProvider),
        photo: photo,
        addressLine: addressLine,
        lat: lat,
        lng: lng,
      );

      if (photoUrl == null) {
        final newLoading = Set<String>.from(state.loadingTasks)..remove(key);
        state = state.copyWith(
          loadingTasks: newLoading,
          error: 'Photo upload failed. Check your connection.',
        );
        return false;
      }

      // ── POST to backend ──────────────────────────────────────────────────
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

      final newLoading = Set<String>.from(state.loadingTasks)..remove(key);

      if (success) {
        // ✅ Weekly — set 7-day cooldown immediately in state
        if (taskId == 'flagswash') {
          final nextDue = DateTime.now().add(const Duration(days: 7));
          final newLocked = Set<String>.from(state.lockedTasks);
          final newDoneMap = Map<String, bool>.from(state.taskDoneMap);
          final newPhotoMap = Map<String, String?>.from(state.photoUrlMap);

          for (final s in ['morning', 'day', 'night']) {
            newLocked.add('${s}_flagswash');
            newDoneMap['${s}_flagswash'] = true;
            newPhotoMap['${s}_flagswash'] = photoUrl;
          }

          state = state.copyWith(
            loadingTasks: newLoading,
            lockedTasks: newLocked,
            taskDoneMap: newDoneMap,
            photoUrlMap: newPhotoMap,
            taskPhotoMap: Map<String, File?>.from(state.taskPhotoMap)
              ..[key] = photo,
            weeklyRemainingDays: 7,
            weeklyNextDue: nextDue,
            error: null,
          );
          return true;
        }

        // ✅ Monthly — set 30-day cooldown immediately in state
        if (taskId == 'fireaudit') {
          final nextDue = DateTime.now().add(const Duration(days: 30));
          final newLocked = Set<String>.from(state.lockedTasks);
          final newDoneMap = Map<String, bool>.from(state.taskDoneMap);
          final newPhotoMap = Map<String, String?>.from(state.photoUrlMap);

          for (final s in ['morning', 'day', 'night']) {
            newLocked.add('${s}_fireaudit');
            newDoneMap['${s}_fireaudit'] = true;
            newPhotoMap['${s}_fireaudit'] = photoUrl;
          }

          state = state.copyWith(
            loadingTasks: newLoading,
            lockedTasks: newLocked,
            taskDoneMap: newDoneMap,
            photoUrlMap: newPhotoMap,
            taskPhotoMap: Map<String, File?>.from(state.taskPhotoMap)
              ..[key] = photo,
            monthlyRemainingDays: 30,
            monthlyNextDue: nextDue,
            error: null,
          );
          return true;
        }

        // ── Regular daily task ───────────────────────────────────────────
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

      final newLoading = Set<String>.from(state.loadingTasks)..remove(key);

      // ✅ Backend cooldown error — re-fetch to get updated days
      if (e.toString().contains('COOLDOWN_ACTIVE') && state.courtId != null) {
        await _rehydrateFromBackend(state.courtId!);
        state = state.copyWith(loadingTasks: newLoading, error: null);
        return false;
      }

      state = state.copyWith(
        loadingTasks: newLoading,
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
