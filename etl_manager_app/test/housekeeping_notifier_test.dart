// Contract tests for the staff checklist's state (housekeeping_notifier.dart)
// and the logout/login hand-over on a shared phone (auth_notifier.dart).
//
// The live report: an ETL staff member on a new phone saw "No checklist yet —
// This court has no housekeeping checklist configured." His court (Bennett
// University) had 3 shifts x 6 tasks, the server returned all of it, and the
// app's own parser read it fine. The app simply never loaded it:
//
//   • the court came ONLY from the id stored on the phone at login, and a
//     missing one meant no request at all;
//   • any failure was swallowed and shown as "nothing configured";
//   • and nothing could recover it — the screen had no refresh, and the state
//     survived logout/login, so only killing the app helped.
//
// Staff also SHARE PHONES, so the account-switch tests matter as much as the
// bug itself.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:etl_manager_app/core/network/api_client.dart';
import 'package:etl_manager_app/core/services/push_service.dart';
import 'package:etl_manager_app/core/utils/token_storage.dart';
import 'package:etl_manager_app/features/auth/domain/auth_notifier.dart';
import 'package:etl_manager_app/features/staff/data/housekeeping_repository.dart';
import 'package:etl_manager_app/features/staff/domain/housekeeping_notifier.dart';

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._email);
  final String? _email;

  static AuthState _for(String? email) => AuthState(
        status: email == null ? AuthStatus.idle : AuthStatus.success,
        managerEmail: email,
      );

  @override
  AuthState build() => _for(_email); // no session restore

  void signInAs(String? email) => state = _for(email);
}

typedef _Handler = Future<ResponseBody> Function(RequestOptions o);

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  _Handler handler = (_) async => _json(_status());

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}

  int count(String path) => requests.where((r) => r.path == path).length;
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

/// The shape `GET /housekeeping/status` really returns (taken from the live
/// response for the reported staff member).
Map<String, dynamic> _status({
  int courtId = 4,
  String courtName = 'Bennett University',
  int shifts = 3,
}) =>
    {
      'date': '2026-11-14',
      'courts': [
        {
          'court_id': courtId,
          'court_name': courtName,
          'date': '2026-11-14',
          'shifts': [
            for (var i = 0; i < shifts; i++)
              {
                'shift': 'shift$i',
                'shift_name': 'Shift $i',
                'start_time': '00:00',
                'end_time': '23:59',
                'total': 2,
                'done': 0,
                'submitted': false,
                'tasks': [
                  for (final t in ['mop', 'bins'])
                    {
                      'task_id': t,
                      'task_title': t,
                      'icon': 'cleaning_services',
                      'is_done': false,
                      'photo_url': null,
                      'done_at': null,
                      'done_by_name': null,
                    },
                ],
              },
          ],
        },
      ],
      'weekly_tasks': [],
      'monthly_tasks': [],
    };

const _a = 'kuldeep@etl.com'; // Central 50
const _b = 'manjeet@etl.com'; // Bennett University

/// What TokenStorage holds after a login (see auth_repository.dart).
Map<String, String> _stored({String? zone, String name = 'Manjeet kumar'}) => {
      'manager_name': name,
      'user_zone': ?zone,
    };

class _Rig {
  _Rig({String? email = _b, Map<String, String>? storage}) {
    FlutterSecureStorage.setMockInitialValues(storage ?? _stored(zone: '4'));
    adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuth(email)),
        dioProvider.overrideWithValue(dio),
      ],
    );
    container.listen(housekeepingNotifierProvider, (_, _) {});
  }

  late final _Adapter adapter;
  late final ProviderContainer container;

  HousekeepingState get state => container.read(housekeepingNotifierProvider);
  HousekeepingNotifier get notifier =>
      container.read(housekeepingNotifierProvider.notifier);

  void signInAs(String? email) =>
      (container.read(authNotifierProvider.notifier) as _FakeAuth).signInAs(email);

  void dispose() => container.dispose();
}

Future<void> _until(bool Function() done, {String? reason}) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: reason ?? 'condition never became true');
}

/// Real-time wait, for code paths with real delays (the login splash).
Future<void> _waitFor(bool Function() done, {Duration max = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(max);
  while (!done() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: 'timed out');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── The reported bug ───────────────────────────────────────────────────────

  group('a full checklist must never read as "not configured"', () {
    test('no court saved on the phone: loads it from the server anyway',
        () async {
      final r = _Rig(storage: _stored()); // no user_zone at all
      addTearDown(r.dispose);

      await _until(() => r.state.isInitialized);

      expect(r.adapter.count('/housekeeping/status'), 1,
          reason: 'used to send no request when no court was stored');
      expect(r.state.courtId, 4);
      expect(r.state.courtName, 'Bennett University');
      expect(r.state.shifts, hasLength(3));
      expect(r.state.loadFailed, isFalse);
    });

    test("a stale saved court loses to the server's answer", () async {
      // Server always returns the staff member's real court (4).
      final r = _Rig(storage: _stored(zone: '1'));
      addTearDown(r.dispose);

      await _until(() => r.state.isInitialized);

      expect(r.state.courtId, 4);
      expect(r.state.shifts, hasLength(3));
    });

    test('a failed load is a failure, not an empty checklist', () async {
      final r = _Rig()..adapter.handler = _offline;
      addTearDown(r.dispose);

      await _until(() => r.state.isInitialized);

      expect(r.state.loadFailed, isTrue);
      expect(r.state.shifts, isEmpty);
      expect(r.state.loadError, 'Check your internet and try again.');
    });

    test('a court with genuinely no shifts IS an empty checklist', () async {
      final r = _Rig()..adapter.handler = (_) async => _json(_status(shifts: 0));
      addTearDown(r.dispose);

      await _until(() => r.state.isInitialized);

      expect(r.state.loadFailed, isFalse);
      expect(r.state.shifts, isEmpty);
    });
  });

  // ── Recovery ───────────────────────────────────────────────────────────────

  group('recovers instead of staying stuck until the app is killed', () {
    test('refresh() after a failed first load brings it back', () async {
      final r = _Rig()..adapter.handler = _offline;
      addTearDown(r.dispose);
      await _until(() => r.state.isInitialized);
      expect(r.state.loadFailed, isTrue);

      r.adapter.handler = (_) async => _json(_status());
      await r.notifier.refresh();

      expect(r.state.loadFailed, isFalse);
      expect(r.state.shifts, hasLength(3));
    });

    test('refresh() works even when no court was ever known', () async {
      // The old refresh() was a no-op without a court id.
      final r = _Rig(storage: _stored())..adapter.handler = _offline;
      addTearDown(r.dispose);
      await _until(() => r.state.isInitialized);

      r.adapter.handler = (_) async => _json(_status());
      await r.notifier.refresh();

      expect(r.state.courtId, 4);
      expect(r.state.shifts, hasLength(3));
    });

    test('a failed refresh keeps the checklist already on screen', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.isInitialized);

      r.adapter.handler = _offline;
      await r.notifier.refresh();

      expect(r.state.shifts, hasLength(3), reason: 'a blip wiped the list');
      expect(r.state.loadFailed, isTrue);
    });

    test('overlapping loads share one request', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.isInitialized);

      final pending = Completer<ResponseBody>();
      r.adapter.handler = (_) => pending.future;
      final before = r.adapter.count('/housekeeping/status');
      final a = r.notifier.refresh();
      final b = r.notifier.refresh();
      pending.complete(_json(_status()));
      await Future.wait([a, b]);

      expect(r.adapter.count('/housekeeping/status'), before + 1);
    });
  });

  group('automatic retry and app resume', () {
    // Fake clock; Dio needs a sliver of elapsed time, hence 1 ms steps.
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 1));
      }
    }

    testWidgets('a blip at first open heals itself', (tester) async {
      final r = _Rig()..adapter.handler = _offline;
      addTearDown(r.dispose);
      await settle(tester);
      expect(r.state.loadFailed, isTrue);

      r.adapter.handler = (_) async => _json(_status());
      await tester.pump(HousekeepingNotifier.retryDelays.first);
      await settle(tester);

      expect(r.state.loadFailed, isFalse);
      expect(r.state.shifts, hasLength(3));
    });

    testWidgets('stops after the last retry', (tester) async {
      final r = _Rig()..adapter.handler = _offline;
      addTearDown(r.dispose);
      await settle(tester);
      for (final d in HousekeepingNotifier.retryDelays) {
        await tester.pump(d);
        await settle(tester);
      }
      await tester.pump(const Duration(minutes: 5));
      await settle(tester);

      expect(r.adapter.count('/housekeeping/status'),
          1 + HousekeepingNotifier.retryDelays.length);
    });

    testWidgets("a 4xx shows the server's reason and is not retried",
        (tester) async {
      final r = _Rig()
        ..adapter.handler = (_) async =>
            _json({'detail': 'No court assigned to your account.'}, 403);
      addTearDown(r.dispose);
      await settle(tester);
      await tester.pump(const Duration(minutes: 5));
      await settle(tester);

      expect(r.state.loadError, 'No court assigned to your account.');
      expect(r.adapter.count('/housekeeping/status'), 1);
    });

    testWidgets('returning to the app retries a failed load', (tester) async {
      final r = _Rig()
        ..adapter.handler = (_) async => _json({'detail': 'down'}, 403);
      addTearDown(r.dispose);
      await settle(tester);
      expect(r.state.loadFailed, isTrue); // 4xx: no timer retry pending

      r.adapter.handler = (_) async => _json(_status());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(r.state.loadFailed, isFalse);
      expect(r.state.shifts, hasLength(3));
    });

    testWidgets('returning to the app does NOT reload a healthy checklist',
        (tester) async {
      // Every task photo goes through the system camera (pause → resume).
      final r = _Rig();
      addTearDown(r.dispose);
      await settle(tester);
      final before = r.adapter.count('/housekeeping/status');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(r.adapter.count('/housekeeping/status'), before);
    });
  });

  // ── Shared phones ──────────────────────────────────────────────────────────

  group('shared phones', () {
    test("switching account shows the new person's court, not the old one",
        () async {
      final r = _Rig(email: _a, storage: _stored(zone: '1', name: 'Kuldeep'))
        ..adapter.handler =
            (_) async => _json(_status(courtId: 1, courtName: 'Central 50'));
      addTearDown(r.dispose);
      await _until(() => r.state.courtName == 'Central 50');

      // B's login writes B's details to storage, then flips the identity.
      FlutterSecureStorage.setMockInitialValues(_stored(zone: '4'));
      r.adapter.handler = (_) async => _json(_status());
      r.signInAs(_b);
      await _until(() => r.state.courtName == 'Bennett University');

      expect(r.state.courtId, 4);
    });

    test("a load A left in flight cannot land on B", () async {
      final r = _Rig(email: _a, storage: _stored(zone: '1'));
      addTearDown(r.dispose);
      final aPending = Completer<ResponseBody>();
      r.adapter.handler = (_) => aPending.future;
      await _until(() => r.adapter.count('/housekeeping/status') == 1);
      // Hold A's load itself (concurrent calls share it), so the test can
      // wait for A's late answer to be fully processed — not just hope.
      final aLoad = r.notifier.refresh();

      FlutterSecureStorage.setMockInitialValues(_stored(zone: '4'));
      r.adapter.handler = (_) async => _json(_status());
      r.signInAs(_b);
      await _until(() => r.state.courtName == 'Bennett University');

      // A's answer arrives late.
      aPending.complete(_json(_status(courtId: 1, courtName: 'Central 50')));
      await aLoad;

      expect(r.state.courtName, 'Bennett University',
          reason: "A's court leaked onto B");
      expect(r.state.courtId, 4);
    });

    test('signed out: nothing is requested', () async {
      final r = _Rig(email: null);
      addTearDown(r.dispose);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(r.adapter.count('/housekeeping/status'), 0);
    });
  });

  // ── Repository contract the other screens rely on ─────────────────────────

  group('HousekeepingRepository', () {
    HousekeepingRepository repoWith(_Handler h) {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = (_Adapter()..handler = h);
      return HousekeepingRepository(dio);
    }

    test('getFullStatus still returns null on failure (home, manager, history)',
        () async {
      expect(await repoWith(_offline).getFullStatus(), isNull);
    });

    test('fetchFullStatus throws on failure', () async {
      expect(repoWith(_offline).fetchFullStatus(), throwsA(isA<DioException>()));
    });

    test('both return the same data on success', () async {
      final repo = repoWith((_) async => _json(_status()));
      expect((await repo.getFullStatus())?.courts.single.courtId, 4);
      expect((await repo.fetchFullStatus()).courts.single.courtId, 4);
    });
  });

  // ── Logout → login hand-over on a shared phone ────────────────────────────

  group('logout race', () {
    test("B signing in during A's logout keeps B's session", () async {
      FlutterSecureStorage.setMockInitialValues({});
      await TokenStorage.clearAll(); // reset the static token cache
      final unregisterGate = Completer<void>();
      final adapter = _Adapter()
        ..handler = (o) async {
          if (o.path == '/auth/login') {
            final email = (o.data as Map)['email'] as String;
            return _json({
              'access_token': 'tok-$email',
              'token_type': 'bearer',
              'manager_name': email,
              'manager_email': email,
              'role': 'etl_staff',
              'zone': email == _a ? 1 : 4,
              'outlet_id': null,
              'court_ids': null,
            });
          }
          return _json({});
        };
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;
      final c = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
          pushServiceProvider.overrideWith(
            (ref) => _GatedPush(ref, unregisterGate),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(authNotifierProvider, (_, _) {});
      AuthNotifier auth() => c.read(authNotifierProvider.notifier);

      // Let the cold-start session restore (with its splash delay) finish.
      await _waitFor(() => c.read(authNotifierProvider).status != AuthStatus.unknown);

      await auth().login(_a, 'pw');
      expect(await TokenStorage.getZone(), '1');

      auth().logout(); // instant; push unregister now hangs on the gate
      expect(c.read(authNotifierProvider).status, AuthStatus.idle);

      final bLogin = auth().login(_b, 'pw'); // phone handed over right away
      await Future<void>.delayed(const Duration(milliseconds: 50));
      unregisterGate.complete(); // A's teardown finishes, then wipes
      await bLogin;
      // Give any late teardown time to run, as it would have before the fix.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(c.read(authNotifierProvider).status, AuthStatus.success);
      expect(c.read(authNotifierProvider).managerEmail, _b);
      expect(await TokenStorage.getZone(), '4',
          reason: "A's late logout wiped B's fresh login");
    });
  });
}

class _GatedPush extends PushService {
  _GatedPush(super.ref, this.gate);
  final Completer<void> gate;

  @override
  Future<void> unregister() => gate.future;
}
