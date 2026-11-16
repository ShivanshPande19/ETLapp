import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ✅ JWT wala dio (pehle app/dio_provider.dart tha jo token nahi bhejta)
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_notifier.dart';
import '../data/attendance_cache.dart';

enum AttendanceStatus { idle, loading, success, error }

// ─── Today's attendance snapshot (from backend) ──────────────────────────────

class AttendanceToday {
  final int? attendanceId;
  final bool checkedIn;
  final DateTime? checkInTime;
  final String? checkInAddress;
  final String? checkInPhotoUrl;
  final bool checkedOut;
  final DateTime? checkOutTime;
  final String? checkOutAddress;
  final int? workDurationMinutes;

  /// Checked out before the scheduled shift end (a notice was raised).
  final bool earlyCheckout;

  /// The hourly sweep closed a forgotten check-out. The API has always sent
  /// these two flags; the client used to drop them, so staff could never see
  /// why yesterday showed up orange on their calendar.
  final bool autoClosed;

  const AttendanceToday({
    this.attendanceId,
    this.checkedIn = false,
    this.checkInTime,
    this.checkInAddress,
    this.checkInPhotoUrl,
    this.checkedOut = false,
    this.checkOutTime,
    this.checkOutAddress,
    this.workDurationMinutes,
    this.earlyCheckout = false,
    this.autoClosed = false,
  });

  const AttendanceToday.empty()
    : attendanceId = null,
      checkedIn = false,
      checkInTime = null,
      checkInAddress = null,
      checkInPhotoUrl = null,
      checkedOut = false,
      checkOutTime = null,
      checkOutAddress = null,
      workDurationMinutes = null,
      earlyCheckout = false,
      autoClosed = false;

  factory AttendanceToday.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? s) {
      if (s == null || s.isEmpty) return null;
      try {
        return DateTime.parse(s).toLocal();
      } catch (_) {
        return null;
      }
    }

    return AttendanceToday(
      attendanceId: json['attendance_id'],
      checkedIn: json['checked_in'] ?? false,
      checkInTime: parse(json['check_in_time']?.toString()),
      checkInAddress: json['check_in_address'],
      checkInPhotoUrl: json['check_in_photo_url'],
      checkedOut: json['checked_out'] ?? false,
      checkOutTime: parse(json['check_out_time']?.toString()),
      checkOutAddress: json['check_out_address'],
      workDurationMinutes: json['work_duration_minutes'],
      earlyCheckout: json['early_checkout'] == true,
      autoClosed: json['auto_closed'] == true,
    );
  }
}

// ─── State ───────────────────────────────────────────────────────────────────

/// Where [AttendanceState.today] came from.
enum AttendanceSource {
  /// Nothing known yet this session.
  none,

  /// A shift saved on the phone, shown while the server can't be reached.
  cache,

  /// The server's own answer.
  server,
}

/// What the attendance card should show. Every home screen maps this to its
/// own widgets, so they all make the same call.
enum AttendanceView {
  /// Finding out, or a punch is uploading.
  busy,

  /// A shift exists for today — running, or done.
  shift,

  /// The server confirmed there is no shift yet.
  checkIn,

  /// We couldn't find out. NOT the same as [checkIn]: see [AttendanceState.view].
  unknown,
}

class AttendanceState {
  final AttendanceStatus status; // tracks the latest check-in/out action
  final String? errorMessage;
  final bool loadingToday; // initial "am I checked in?" fetch
  final AttendanceToday today;
  final AttendanceSource source;

  /// The last attempt to load today's status failed.
  final bool loadFailed;

  const AttendanceState({
    this.status = AttendanceStatus.idle,
    this.errorMessage,
    this.loadingToday = false,
    this.today = const AttendanceToday.empty(),
    this.source = AttendanceSource.none,
    this.loadFailed = false,
  });

  // Convenience getters for the UI.
  bool get isCheckedIn => today.checkedIn;
  bool get isCheckedOut => today.checkedOut;
  bool get isShiftActive => today.checkedIn && !today.checkedOut;

  /// A saved shift is on screen because the server couldn't be reached.
  bool get showingSavedShift => isCheckedIn && source == AttendanceSource.cache;

  /// The one rule every attendance card follows: **"Check In" is shown only
  /// when the server has confirmed there is no shift.**
  ///
  /// `today` starts empty on every cold start, and empty reads as "not checked
  /// in". The cards used to treat it that way, so a failed status call showed
  /// "Check In" to someone halfway through their shift — the "my shift got
  /// logged out" report. Not knowing is now its own state.
  ///
  /// A known shift stays on screen during a refresh rather than dropping back
  /// to a skeleton, so pulling to refresh no longer makes it flicker away. The
  /// same goes for [AttendanceView.unknown]: a retry keeps that card up (it
  /// shows its own "Checking…") instead of jumping to a skeleton and back.
  AttendanceView get view {
    if (status == AttendanceStatus.loading) return AttendanceView.busy;
    if (isCheckedIn) return AttendanceView.shift;
    if (source == AttendanceSource.server) return AttendanceView.checkIn;
    if (loadFailed) return AttendanceView.unknown;
    return AttendanceView.busy;
  }

  AttendanceState copyWith({
    AttendanceStatus? status,
    String? errorMessage,
    bool? loadingToday,
    AttendanceToday? today,
    AttendanceSource? source,
    bool? loadFailed,
  }) {
    return AttendanceState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      loadingToday: loadingToday ?? this.loadingToday,
      today: today ?? this.today,
      source: source ?? this.source,
      loadFailed: loadFailed ?? this.loadFailed,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class AttendanceNotifier extends Notifier<AttendanceState> {
  /// A photo upload needs a longer leash than a JSON call: the global 30 s
  /// send timeout used to abort a half-finished selfie on a weak 4G cell and
  /// report "failed to check in" even though the punch was still in flight.
  /// (The selfie is compressed before it gets here — see
  /// PhotoUploadService.compressForUpload — so this is headroom, not the norm.)
  static final Options _uploadOptions = Options(
    sendTimeout: const Duration(seconds: 90),
    receiveTimeout: const Duration(seconds: 60),
  );

  /// Gaps between automatic retries of a failed status load. A blip on the
  /// court's signal at app-open heals itself; a real outage stops after the
  /// last one and leaves the Retry button.
  @visibleForTesting
  static const retryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  /// Who this state belongs to.
  String? _owner;

  /// Bumped every time [build] runs — i.e. every time the signed-in person
  /// changes. Each request remembers the generation it started in and drops
  /// its result if that has moved on. See [build] for why `ref.mounted` alone
  /// is not enough.
  int _generation = 0;

  Future<void>? _inFlight;
  Timer? _retryTimer;
  int _retryAttempt = 0;

  /// Bumped on every accepted punch, so a status load that was already in
  /// flight can tell that its answer is older than the punch and discard it.
  int _punchSeq = 0;

  /// Only screens that show attendance call [loadToday]. Until one has, a
  /// resume must not fetch — a manager's home screen watches this provider
  /// too, and has no attendance to load.
  bool _used = false;

  @override
  AttendanceState build() {
    // SHARED PHONES: staff without a phone log in on a colleague's, punch, and
    // log out. Watching the signed-in identity re-runs this build whenever it
    // changes, so each person starts from a clean slate. Previously the state
    // outlived logout: if the next person's status load failed, they were
    // shown the previous person's shift as their own.
    //
    // A rebuild does NOT give a fresh notifier. On the Riverpod in use
    // (3.2.1) it re-runs build on the SAME instance and `ref.mounted` stays
    // true — verified, not assumed. So a request the previous person left in
    // flight would still pass a mounted check and write their shift onto the
    // new person, and the fields below would carry over. The generation bump
    // and the resets are what actually isolate one person from the next.
    _owner = ref.watch(authNotifierProvider.select((s) => s.managerEmail));
    _generation++;
    _inFlight = null;
    _retryTimer?.cancel();
    _retryAttempt = 0;
    _used = false;

    // Reopening the app is when a stale card does damage, so recheck then.
    final lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.onDispose(() {
      _retryTimer?.cancel();
      lifecycle.dispose();
    });

    return const AttendanceState();
  }

  void _onResume() {
    if (!ref.mounted || !_used || _owner == null) return;
    if (state.status == AttendanceStatus.loading) return; // a punch is uploading
    loadToday();
  }

  /// True once the person this work started for is no longer signed in.
  bool _stale(int generation) => !ref.mounted || generation != _generation;

  /// Fetch today's status so the home screen survives app restarts.
  ///
  /// Concurrent calls share one request.
  Future<void> loadToday() {
    final existing = _inFlight;
    if (existing != null) return existing;
    late final Future<void> mine;
    mine = _loadToday().whenComplete(() {
      // Only clear our own slot: by now it may belong to the next person.
      if (identical(_inFlight, mine)) _inFlight = null;
    });
    return _inFlight = mine;
  }

  Future<void> _loadToday() async {
    _used = true;
    _retryTimer?.cancel();
    final owner = _owner;
    final gen = _generation;

    // Cold start: show this person's saved open shift right away, before the
    // network answers — or in place of it, if the network never does.
    if (state.source == AttendanceSource.none && owner != null) {
      final saved = await AttendanceCache.read(owner);
      if (_stale(gen)) return;
      if (saved != null && state.source == AttendanceSource.none) {
        state = state.copyWith(today: saved, source: AttendanceSource.cache);
      }
    }

    final seqAtStart = _punchSeq;
    state = state.copyWith(loadingToday: true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/attendance/today');
      if (_stale(gen)) return;
      if (_punchSeq != seqAtStart) {
        // A check-in/out landed while this was in flight; its answer is the
        // newer one. Keep it.
        state = state.copyWith(loadingToday: false);
        return;
      }
      final today = AttendanceToday.fromJson(res.data as Map<String, dynamic>);
      state = state.copyWith(
        loadingToday: false,
        today: today,
        source: AttendanceSource.server,
        loadFailed: false,
      );
      _retryAttempt = 0;
      if (owner != null) await AttendanceCache.write(owner, today);
    } catch (e) {
      if (_stale(gen)) return;
      // Keep whatever we had — a saved shift stays on screen — and say so.
      state = state.copyWith(loadingToday: false, loadFailed: true);
      _scheduleRetry(e, gen);
    }
  }

  void _scheduleRetry(Object error, int gen) {
    // A 4xx is an answer, not an outage: retrying won't change it. (A 401
    // never gets here as a live session — the network layer signs out.)
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code != null && code < 500) return;
    }
    if (_retryAttempt >= retryDelays.length) return;
    final delay = retryDelays[_retryAttempt++];
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!_stale(gen)) loadToday();
    });
  }

  /// A punch the server accepted: its response is the newest truth.
  /// Callers check [_stale] first, so [_owner] is still the person who punched.
  Future<void> _acceptPunch(Map<String, dynamic> json) async {
    _punchSeq++;
    _retryAttempt = 0;
    final today = AttendanceToday.fromJson(json);
    state = state.copyWith(
      status: AttendanceStatus.success,
      today: today,
      source: AttendanceSource.server,
      loadFailed: false,
    );
    final owner = _owner;
    if (owner != null) await AttendanceCache.write(owner, today);
  }

  Future<void> markAttendance({
    required double lat,
    required double lng,
    required String imagePath,
    double? accuracy,
    bool? isMocked,
  }) async {
    final gen = _generation;
    state = state.copyWith(status: AttendanceStatus.loading);
    try {
      final dio = ref.read(dioProvider);
      final formData = FormData.fromMap({
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        if (isMocked != null) 'is_mocked': isMocked,
        'photo': await MultipartFile.fromFile(imagePath, filename: 'checkin.jpg'),
      });

      final res = await dio.post(
        '/attendance/check-in',
        data: formData,
        options: _uploadOptions,
      );
      if (_stale(gen)) return;
      await _acceptPunch(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (_stale(gen)) return;
      state = state.copyWith(
        status: AttendanceStatus.error,
        errorMessage: _friendlyError(e, fallback: 'Failed to check in.'),
      );
    } catch (_) {
      if (_stale(gen)) return;
      state = state.copyWith(
        status: AttendanceStatus.error,
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> checkOut({
    required double lat,
    required double lng,
    String? imagePath,
    double? accuracy,
    bool? isMocked,
  }) async {
    final gen = _generation;
    state = state.copyWith(status: AttendanceStatus.loading);
    try {
      final dio = ref.read(dioProvider);
      final map = <String, dynamic>{'lat': lat, 'lng': lng};
      if (accuracy != null) map['accuracy'] = accuracy;
      if (isMocked != null) map['is_mocked'] = isMocked;
      if (imagePath != null) {
        map['photo'] = await MultipartFile.fromFile(
          imagePath,
          filename: 'checkout.jpg',
        );
      }
      final res = await dio.post(
        '/attendance/check-out',
        data: FormData.fromMap(map),
        options: _uploadOptions,
      );
      if (_stale(gen)) return;
      await _acceptPunch(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (_stale(gen)) return;
      state = state.copyWith(
        status: AttendanceStatus.error,
        errorMessage: _friendlyError(e, fallback: 'Failed to check out.'),
      );
    } catch (_) {
      if (_stale(gen)) return;
      state = state.copyWith(
        status: AttendanceStatus.error,
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  String _friendlyError(DioException e, {required String fallback}) {
    // Backend sends a clear "detail" message for 409/400/403 — surface it.
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (e.response?.statusCode == 401) {
      return 'Session expired. Please log in again.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot reach server. Check your internet.';
    }
    return fallback;
  }
}

final attendanceNotifierProvider =
    NotifierProvider<AttendanceNotifier, AttendanceState>(() {
      return AttendanceNotifier();
    });
