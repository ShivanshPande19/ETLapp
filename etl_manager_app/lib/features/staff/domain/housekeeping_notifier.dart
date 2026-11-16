// lib/features/staff/domain/housekeeping_notifier.dart
//
// Config-driven housekeeping state for staff (Phase 3b).
//
// Shifts, their timings, daily tasks and the weekly/monthly recurring tasks are
// all loaded dynamically from the backend (/housekeeping/status) for the
// staff's court. Nothing is hardcoded — a court can have any number of shifts
// (with any names/timings) and any number of weekly/monthly tasks.

import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../data/housekeeping_repository.dart';
import '../../auth/domain/auth_notifier.dart';
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

  /// A status load is in flight (first open, refresh, retry).
  final bool loading;

  /// The last status load failed. NOT the same as an empty checklist: the
  /// screen says "couldn't load" for this, and "no checklist yet" only when
  /// the server actually returned no shifts.
  final bool loadFailed;

  /// What to tell staff when [loadFailed] — the server's own reason when it
  /// gave one (e.g. "No court assigned to your account."). Only meaningful
  /// while [loadFailed] is true.
  final String? loadError;

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
    this.loading = false,
    this.loadFailed = false,
    this.loadError,
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
    bool? loading,
    bool? loadFailed,
    String? loadError,
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
      loading: loading ?? this.loading,
      loadFailed: loadFailed ?? this.loadFailed,
      loadError: loadError ?? this.loadError,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class HousekeepingNotifier extends Notifier<HousekeepingState> {
  /// Gaps between automatic retries of a failed load. A blip on the court's
  /// signal heals itself; a real outage stops after the last one and leaves
  /// pull-to-refresh and the Retry button.
  @visibleForTesting
  static const retryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  /// Who this state belongs to.
  String? _owner;

  /// Bumped on every [build] — every account switch, and every SSE
  /// invalidate. Async work remembers the generation it started in and drops
  /// its result if that has moved on.
  int _generation = 0;

  Future<void>? _inFlight;
  Timer? _retryTimer;
  int _retryAttempt = 0;

  @override
  HousekeepingState build() {
    // SHARED PHONES: staff without a phone log in on a colleague's. Watching
    // the signed-in identity re-runs this build when it changes, so each
    // person starts clean. Before, this state lived for the whole app process:
    // a logout/login did not reset it, so the next person could see the
    // previous person's court, and a checklist that failed to load once stayed
    // broken until the app was killed.
    //
    // On the Riverpod in use (3.2.1) a rebuild re-runs build on the SAME
    // instance with `ref.mounted` still true (verified for AttendanceNotifier,
    // same mechanism). The generation bump and resets below are what actually
    // stop the previous build's requests from writing into this one — which
    // also covers the SSE `invalidate` that used to race a running load.
    _owner = ref.watch(authNotifierProvider.select((s) => s.managerEmail));
    _generation++;
    _inFlight = null;
    _retryTimer?.cancel();
    _retryAttempt = 0;

    final lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.onDispose(() {
      _retryTimer?.cancel();
      lifecycle.dispose();
    });

    // Signed out: there is no checklist to load (the screen isn't reachable).
    if (_owner != null) Future.microtask(_init);
    return HousekeepingState(date: _today);
  }

  bool _stale(int generation) => !ref.mounted || generation != _generation;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    final gen = _generation;
    String? zone;
    String? name;
    try {
      zone = await TokenStorage.getZone();
      name = await TokenStorage.getManagerName();
    } catch (_) {
      // Secure storage hiccup: carry on — the court comes from the server.
    }
    if (_stale(gen)) return;

    state = state.copyWith(
      courtId: _parseZone(zone),
      courtName: name ?? 'Staff',
      userName: name ?? 'Staff',
    );

    await _load();
  }

  /// Reload config + today's completions. Never throws; the outcome lands in
  /// state ([HousekeepingState.loadFailed]). Concurrent calls share one load.
  Future<void> refresh() => _load();

  void _onResume() {
    if (!ref.mounted || _owner == null) return;
    // Only when stuck. Every task photo goes through the system camera, which
    // pauses and resumes the app — reloading on each of those would be waste.
    if (state.loadFailed) _load();
  }

  Future<void> _load() {
    final existing = _inFlight;
    if (existing != null) return existing;
    late final Future<void> mine;
    mine = _doLoad().whenComplete(() {
      // Only clear our own slot: by now it may belong to the next person.
      if (identical(_inFlight, mine)) _inFlight = null;
    });
    return _inFlight = mine;
  }

  Future<void> _doLoad() async {
    _retryTimer?.cancel();
    final gen = _generation;
    state = state.copyWith(loading: true);
    try {
      await _rehydrateFromBackend(gen);
      if (_stale(gen)) return;
      _retryAttempt = 0;
      state = state.copyWith(
        loading: false,
        loadFailed: false,
        isInitialized: true,
      );
    } catch (e) {
      debugPrint('_rehydrateFromBackend error: $e');
      if (_stale(gen)) return;
      // Keep whatever was already on screen; just say the refresh failed.
      state = state.copyWith(
        loading: false,
        loadFailed: true,
        loadError: _loadErrorMessage(e),
        isInitialized: true,
      );
      _scheduleRetry(e, gen);
    }
  }

  void _scheduleRetry(Object error, int gen) {
    // A 4xx is an answer, not an outage (e.g. "No court assigned"): retrying
    // won't change it. Same for a response we couldn't parse.
    if (error is! DioException) return;
    final code = error.response?.statusCode;
    if (code != null && code < 500) return;
    if (_retryAttempt >= retryDelays.length) return;
    final delay = retryDelays[_retryAttempt++];
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!_stale(gen)) _load();
    });
  }

  String _loadErrorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
      if (e.response == null) return 'Check your internet and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  // ── Rehydrate from backend (config + completions) ───────────────────────────

  /// Throws on failure, leaving state untouched — [_doLoad] decides what the
  /// staff sees.
  Future<void> _rehydrateFromBackend(int gen) async {
    final status = await ref
        .read(housekeepingRepoProvider)
        .fetchFullStatus(date: _today, courtId: state.courtId);
    if (_stale(gen)) return;

    final court = _courtFor(status, state.courtId);
    final courtId = court?.courtId ?? state.courtId;
    final shifts = court?.shifts ?? const <hk.ShiftStatus>[];
    final weekly = courtId == null
        ? const <hk.RecurringTaskStatus>[]
        : status.weeklyFor(courtId);
    final monthly = courtId == null
        ? const <hk.RecurringTaskStatus>[]
        : status.monthlyFor(courtId);

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
      courtId: courtId,
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
  }

  /// The staff member's court in [status].
  ///
  /// The SERVER is the authority here, not the court id the phone stored at
  /// login: for ETL staff it ignores the requested court and returns exactly
  /// their own (see `GET /housekeeping/status`). So when the stored id is
  /// missing or doesn't match, the single court returned is the right one.
  /// Relying on the stored id alone is how a phone with no saved court showed
  /// "no checklist" for a court that had one.
  hk.CourtDayStatus? _courtFor(hk.FullStatusResponse status, int? storedId) {
    if (storedId != null) {
      final match = status.courtById(storedId);
      if (match != null) return match;
    }
    return status.courts.length == 1 ? status.courts.single : null;
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
    // If the phone changes hands mid-upload, this task belongs to the person
    // who started it — never write it into the next person's checklist.
    final gen = _generation;

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
      if (_stale(gen)) return false;

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
        if (_stale(gen)) return false;
        _applyRecurringDone(taskId, photoUrl, isWeekly: true);
        return true;
      }

      if (kind == hk.HkTaskKind.monthly) {
        await repo.markMonthlyDone(
          courtId: courtId,
          taskId: taskId,
          photoUrl: photoUrl,
        );
        if (_stale(gen)) return false;
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
      if (_stale(gen)) return false;

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
      if (_stale(gen)) return false;
      _clearLoading(taskId, kind);

      // Backend cooldown — re-fetch to surface the accurate countdown.
      if (_isCooldownError(e)) {
        await _load();
        if (_stale(gen)) return false;
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
