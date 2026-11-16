// Contract tests for the attendance card's state (attendance_notifier.dart)
// and the per-person saved shift (attendance_cache.dart).
//
// The bug these pin: on a cold start the status call fails on a weak signal,
// `today` is still empty, and empty used to read as "not checked in" — so a
// staff member halfway through a shift was shown "Check In". To them that is
// the shift being logged out.
//
// And the constraint that shaped the fix: staff SHARE PHONES. Someone without a
// phone logs in on a colleague's, punches, and logs out. So the most important
// tests below are the ones proving one person's shift can never be shown to
// another — not from the phone's saved copy, not from memory, and not from a
// request that was still in flight when they swapped.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:etl_manager_app/core/network/api_client.dart';
import 'package:etl_manager_app/features/auth/domain/auth_notifier.dart';
import 'package:etl_manager_app/features/staff/data/attendance_cache.dart';
import 'package:etl_manager_app/features/staff/domain/attendance_notifier.dart';
import 'package:etl_manager_app/features/staff/presentation/attendance_status_widgets.dart';

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._email);
  final String? _email;

  static AuthState _for(String? email) => AuthState(
        status: email == null ? AuthStatus.idle : AuthStatus.success,
        managerEmail: email,
      );

  @override
  AuthState build() => _for(_email); // no session restore, no secure storage

  /// The phone changes hands.
  void signInAs(String? email) => state = _for(email);
}

typedef _Handler = Future<ResponseBody> Function(RequestOptions o);

class _Adapter implements HttpClientAdapter {
  final calls = <String>[];
  _Handler handler = (_) async => _json({'checked_in': false});

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls.add('${o.method} ${o.path}');
    return handler(o);
  }

  @override
  void close({bool force = false}) {}

  int count(String path) => calls.where((c) => c.endsWith(path)).length;
}

ResponseBody _json(Map<String, dynamic> body, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Future<ResponseBody> _offline(RequestOptions _) async =>
    throw const SocketException('offline');

Map<String, dynamic> _openShift({DateTime? checkIn, String address = 'Gate 2'}) => {
      'attendance_id': 7,
      'checked_in': true,
      'check_in_time':
          (checkIn ?? DateTime.now().subtract(const Duration(hours: 2)))
              .toUtc()
              .toIso8601String(),
      'check_in_address': address,
      'checked_out': false,
    };

Map<String, dynamic> _doneShift() => {
      ..._openShift(),
      'checked_out': true,
      'check_out_time': DateTime.now().toUtc().toIso8601String(),
      'work_duration_minutes': 120,
    };

const _a = 'manjeet@etl.com';
const _b = 'vansh@etl.com';

// ─── Harness ─────────────────────────────────────────────────────────────────

class _Rig {
  _Rig({String? email = _a}) {
    adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuth(email)),
        dioProvider.overrideWithValue(dio),
      ],
    );
    // Keep the provider active, as a mounted home screen would.
    container.listen(attendanceNotifierProvider, (_, _) {});
  }

  late final _Adapter adapter;
  late final ProviderContainer container;

  AttendanceState get state => container.read(attendanceNotifierProvider);

  /// Re-read every time: on Riverpod 3 an identity change makes a NEW notifier.
  AttendanceNotifier get notifier =>
      container.read(attendanceNotifierProvider.notifier);

  void signInAs(String? email) =>
      (container.read(authNotifierProvider.notifier) as _FakeAuth).signInAs(email);

  void dispose() => container.dispose();
}

/// Let pending microtasks run until [done] holds.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'condition never became true');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── The bug ────────────────────────────────────────────────────────────────

  group('never shows "Check In" without the server saying so', () {
    test('a failed load on a cold start is unknown, not checkIn', () async {
      final r = _Rig()..adapter.handler = _offline;
      addTearDown(r.dispose);

      await r.notifier.loadToday();

      expect(r.state.view, AttendanceView.unknown);
      expect(r.state.view, isNot(AttendanceView.checkIn));
    });

    test('before the first answer it is busy, not checkIn', () {
      final r = _Rig();
      addTearDown(r.dispose);
      expect(r.state.view, AttendanceView.busy);
    });

    test('the server saying "not checked in" does show checkIn', () async {
      final r = _Rig()..adapter.handler = (_) async => _json({'checked_in': false});
      addTearDown(r.dispose);

      await r.notifier.loadToday();

      expect(r.state.view, AttendanceView.checkIn);
    });

    test('a server answer survives a later failed refresh', () async {
      final r = _Rig()..adapter.handler = (_) async => _json({'checked_in': false});
      addTearDown(r.dispose);
      await r.notifier.loadToday();

      r.adapter.handler = _offline;
      await r.notifier.loadToday();

      // We already KNOW — a blip later must not take that away.
      expect(r.state.view, AttendanceView.checkIn);
    });
  });

  // ── The saved shift ────────────────────────────────────────────────────────

  group('a running shift survives a cold start with no signal', () {
    test('shown from the phone, flagged as saved', () async {
      // Earlier, online: the server confirms the shift.
      final online = _Rig()..adapter.handler = (_) async => _json(_openShift());
      await online.notifier.loadToday();
      online.dispose();

      // App killed in the background, reopened at the court with no signal.
      final cold = _Rig()..adapter.handler = _offline;
      addTearDown(cold.dispose);
      await cold.notifier.loadToday();

      expect(cold.state.view, AttendanceView.shift);
      expect(cold.state.isShiftActive, isTrue);
      expect(cold.state.showingSavedShift, isTrue);
      expect(cold.state.today.checkInAddress, 'Gate 2');
    });

    test('the server answer replaces the saved one when it arrives', () async {
      final online = _Rig()..adapter.handler = (_) async => _json(_openShift());
      await online.notifier.loadToday();
      online.dispose();

      final next = _Rig()
        ..adapter.handler = (_) async => _json(_openShift(address: 'Fresh'));
      addTearDown(next.dispose);
      await next.notifier.loadToday();

      expect(next.state.showingSavedShift, isFalse);
      expect(next.state.today.checkInAddress, 'Fresh');
    });

    test('checking out forgets the saved shift', () async {
      final r = _Rig()..adapter.handler = (o) async =>
          _json(o.path.endsWith('check-out') ? _doneShift() : _openShift());
      await r.notifier.loadToday();
      await r.notifier.checkOut(lat: 28.5, lng: 77.3);
      expect(r.state.isCheckedOut, isTrue);
      r.dispose();

      final cold = _Rig()..adapter.handler = _offline;
      addTearDown(cold.dispose);
      await cold.notifier.loadToday();

      // No stale "on shift" for someone who already went home.
      expect(cold.state.isShiftActive, isFalse);
      expect(cold.state.view, AttendanceView.unknown);
    });

    test('a saved shift too old to still be running is ignored', () async {
      final old = DateTime.now().subtract(const Duration(hours: 21));
      final online = _Rig()
        ..adapter.handler = (_) async => _json(_openShift(checkIn: old));
      await online.notifier.loadToday();
      online.dispose();

      final cold = _Rig()..adapter.handler = _offline;
      addTearDown(cold.dispose);
      await cold.notifier.loadToday();

      expect(cold.state.isCheckedIn, isFalse);
      expect(cold.state.view, AttendanceView.unknown);
    });
  });

  // ── Shared phones ──────────────────────────────────────────────────────────

  group('shared phones: nobody ever sees someone else\'s shift', () {
    test('B on A\'s phone, offline, does not get A\'s saved shift', () async {
      // A checks in on this phone and logs out.
      final a = _Rig(email: _a)..adapter.handler = (_) async => _json(_openShift());
      await a.notifier.loadToday();
      a.dispose();

      // B borrows the same phone (same storage) with no signal.
      final b = _Rig(email: _b)..adapter.handler = _offline;
      addTearDown(b.dispose);
      await b.notifier.loadToday();

      expect(b.state.isCheckedIn, isFalse);
      expect(b.state.view, AttendanceView.unknown);
    });

    test('A gets their own shift back after B used the phone', () async {
      final a = _Rig(email: _a)..adapter.handler = (_) async => _json(_openShift());
      await a.notifier.loadToday();
      a.dispose();

      final b = _Rig(email: _b)
        ..adapter.handler = (_) async => _json({'checked_in': false});
      await b.notifier.loadToday();
      b.dispose();

      final aAgain = _Rig(email: _a)..adapter.handler = _offline;
      addTearDown(aAgain.dispose);
      await aAgain.notifier.loadToday();

      expect(aAgain.state.isShiftActive, isTrue);
      expect(aAgain.state.showingSavedShift, isTrue);
    });

    test('switching account in the SAME session clears the screen', () async {
      final r = _Rig(email: _a)..adapter.handler = (_) async => _json(_openShift());
      addTearDown(r.dispose);
      await r.notifier.loadToday();
      expect(r.state.isShiftActive, isTrue);

      r.signInAs(null); // A logs out
      r.signInAs(_b); //   B logs in

      expect(r.state.isCheckedIn, isFalse);
      expect(r.state.source, AttendanceSource.none);
    });

    test('a request A left in flight cannot land on B, and does not throw',
        () async {
      final r = _Rig(email: _a);
      addTearDown(r.dispose);
      final pending = Completer<ResponseBody>();
      r.adapter.handler = (_) => pending.future;

      final aLoad = r.notifier.loadToday();
      await _until(() => r.adapter.count('/attendance/today') == 1);

      r.signInAs(_b); // phone handed over mid-request
      pending.complete(_json(_openShift())); // A's answer finally arrives

      await aLoad; // must complete cleanly, not throw at the disposed notifier
      expect(r.state.isCheckedIn, isFalse, reason: "A's shift leaked onto B");
      expect(r.state.source, AttendanceSource.none);
    });

    test("A's stuck request does not block B's own load", () async {
      final r = _Rig(email: _a);
      addTearDown(r.dispose);
      final aPending = Completer<ResponseBody>(); // A's request never returns
      r.adapter.handler = (_) => aPending.future;
      r.notifier.loadToday();
      await _until(() => r.adapter.count('/attendance/today') == 1);

      r.signInAs(_b);
      r.adapter.handler = (_) async => _json(_openShift(address: 'B gate'));
      await r.notifier.loadToday();

      // B's request was really sent, and B sees B's own shift.
      expect(r.adapter.count('/attendance/today'), 2);
      expect(r.state.today.checkInAddress, 'B gate');
    });

    test('email case does not split one person into two', () async {
      final online = _Rig(email: 'Manjeet@ETL.com')
        ..adapter.handler = (_) async => _json(_openShift());
      await online.notifier.loadToday();
      online.dispose();

      final cold = _Rig(email: 'manjeet@etl.com')..adapter.handler = _offline;
      addTearDown(cold.dispose);
      await cold.notifier.loadToday();

      expect(cold.state.isShiftActive, isTrue);
    });
  });

  // ── Races and request hygiene ──────────────────────────────────────────────

  group('races', () {
    test('a status load older than a check-out cannot undo it', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      final staleToday = Completer<ResponseBody>();
      r.adapter.handler = (o) => o.path.endsWith('check-out')
          ? Future.value(_json(_doneShift()))
          : staleToday.future;

      final load = r.notifier.loadToday();
      await _until(() => r.adapter.count('/attendance/today') == 1);

      await r.notifier.checkOut(lat: 28.5, lng: 77.3);
      expect(r.state.isCheckedOut, isTrue);

      // The load was sent before the check-out; it says "still on shift".
      staleToday.complete(_json(_openShift()));
      await load;

      expect(r.state.isCheckedOut, isTrue, reason: 'stale load reopened the shift');
    });

    test('overlapping loads share one request', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      final pending = Completer<ResponseBody>();
      r.adapter.handler = (_) => pending.future;

      final first = r.notifier.loadToday();
      final second = r.notifier.loadToday();
      await _until(() => r.adapter.count('/attendance/today') >= 1);
      pending.complete(_json({'checked_in': false}));
      await Future.wait([first, second]);

      expect(r.adapter.count('/attendance/today'), 1);
    });

    test('logging out mid-check-out does not throw', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      final pending = Completer<ResponseBody>();
      r.adapter.handler = (_) => pending.future;

      final out = r.notifier.checkOut(lat: 28.5, lng: 77.3);
      await _until(() => r.adapter.count('/attendance/check-out') == 1);
      r.signInAs(null);
      pending.complete(_json(_doneShift()));

      await out; // completes cleanly
    });
  });

  // ── Automatic retry ────────────────────────────────────────────────────────

  group('automatic retry', () {
    // Run in the test's fake clock (NOT `runAsync`): a retry Timer created in
    // the real zone never fires on `pump`, which once made "no retry" pass for
    // the wrong reason. Here a scheduled retry WILL fire if one exists.
    //
    // Dio needs a sliver of elapsed time to complete (an internal timer), so
    // settle in 1 ms steps: 10 ms in all, nowhere near the first 3 s retry.
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 1));
      }
    }

    testWidgets('a blip at app-open heals itself', (tester) async {
      final r = _Rig()..adapter.handler = _offline;
      addTearDown(r.dispose);

      r.notifier.loadToday();
      await settle(tester);
      expect(r.state.view, AttendanceView.unknown);

      r.adapter.handler = (_) async => _json(_openShift());
      await tester.pump(AttendanceNotifier.retryDelays.first);
      await settle(tester);

      expect(r.state.view, AttendanceView.shift);
      expect(r.state.isShiftActive, isTrue);
    });

    testWidgets('stops after the last retry', (tester) async {
      final r = _Rig()..adapter.handler = _offline;
      addTearDown(r.dispose);

      r.notifier.loadToday();
      await settle(tester);
      for (final d in AttendanceNotifier.retryDelays) {
        await tester.pump(d);
        await settle(tester);
      }
      await tester.pump(const Duration(minutes: 5));
      await settle(tester);

      expect(
        r.adapter.count('/attendance/today'),
        1 + AttendanceNotifier.retryDelays.length,
      );
      expect(r.state.view, AttendanceView.unknown);
    });

    testWidgets('a 4xx is an answer, not an outage — no retry', (tester) async {
      final r = _Rig()
        ..adapter.handler = (_) async => _json({'detail': 'nope'}, 403);
      addTearDown(r.dispose);

      r.notifier.loadToday();
      await settle(tester);
      await tester.pump(const Duration(minutes: 5));
      await settle(tester);

      expect(r.adapter.count('/attendance/today'), 1);
    });

    testWidgets('a pending retry dies with the person who caused it',
        (tester) async {
      final r = _Rig()..adapter.handler = _offline;
      addTearDown(r.dispose);

      r.notifier.loadToday(); // A, offline → retry scheduled for A
      await settle(tester);
      r.signInAs(_b); // phone handed over before the retry fires

      await tester.pump(const Duration(minutes: 5));
      await settle(tester);

      // A's retry must not have fired a request on B's session.
      expect(r.adapter.count('/attendance/today'), 1);
    });
  });

  // ── AttendanceCache on its own ─────────────────────────────────────────────

  group('AttendanceCache', () {
    final open = AttendanceToday.fromJson(_openShift());

    test('round-trips an open shift', () async {
      await AttendanceCache.write(_a, open);
      final back = await AttendanceCache.read(_a);
      expect(back?.isActiveShift, isTrue);
      expect(back?.checkInAddress, 'Gate 2');
    });

    test('stores no selfie URL on a shared phone', () async {
      await AttendanceCache.write(
        _a,
        AttendanceToday.fromJson({..._openShift(), 'check_in_photo_url': 'uploads/x.jpg'}),
      );
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getKeys().map(prefs.getString).join();
      expect(raw, isNot(contains('uploads/x.jpg')));
    });

    test('a finished shift is not kept', () async {
      await AttendanceCache.write(_a, open);
      await AttendanceCache.write(_a, AttendanceToday.fromJson(_doneShift()));
      expect(await AttendanceCache.read(_a), isNull);
    });

    test('is per person', () async {
      await AttendanceCache.write(_a, open);
      expect(await AttendanceCache.read(_b), isNull);
    });

    test('prunes anyone\'s aged-out entry on the next write', () async {
      final old = AttendanceToday.fromJson(
        _openShift(checkIn: DateTime.now().subtract(const Duration(hours: 30))),
      );
      await AttendanceCache.write(_b, old);
      await AttendanceCache.write(_a, open);

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('attendance_open_shift'));
      expect(keys, hasLength(1));
    });

    test('a corrupt entry reads as nothing, never throws', () async {
      SharedPreferences.setMockInitialValues({
        'attendance_open_shift_v1:$_a': '{not json',
      });
      expect(await AttendanceCache.read(_a), isNull);
    });
  });

  // ── The card shown instead of "Check In" ──────────────────────────────────

  group('AttendanceStatusUnknownCard', () {
    Future<void> pump(WidgetTester t, Widget w) =>
        t.pumpWidget(MaterialApp(home: Scaffold(body: w)));

    testWidgets('offers Retry, never Check In', (t) async {
      var taps = 0;
      await pump(t, AttendanceStatusUnknownCard(onRetry: () => taps++, retrying: false));

      expect(find.text("Couldn't load your shift"), findsOneWidget);
      expect(find.textContaining('Check In'), findsNothing);
      await t.tap(find.text('Retry'));
      expect(taps, 1);
    });

    testWidgets('is disabled while retrying', (t) async {
      var taps = 0;
      await pump(t, AttendanceStatusUnknownCard(onRetry: () => taps++, retrying: true));

      expect(find.text('Checking…'), findsOneWidget);
      await t.tap(find.text('Checking…'), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('renders in the dark style too', (t) async {
      await pump(
        t,
        AttendanceStatusUnknownCard(onRetry: () {}, retrying: false, dark: true),
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

extension on AttendanceToday {
  bool get isActiveShift => checkedIn && !checkedOut;
}
