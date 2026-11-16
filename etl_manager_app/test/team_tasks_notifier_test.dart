// Contract tests for team tasks: the wire format, the notifier's state rules,
// and what happens on a phone that changes hands.
//
// The rules under test:
//   • a failed load is never shown as "you have no tasks";
//   • the signed-in account owns the state — staff share phones, so nothing
//     loaded (or still loading) for one account may land on the next;
//   • the app sends exactly what the assign screen collected, and reports the
//     server's own reason when something is refused.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:etl_manager_app/core/network/api_client.dart';
import 'package:etl_manager_app/features/auth/domain/auth_notifier.dart';
import 'package:etl_manager_app/features/notices/domain/notice_model.dart';
import 'package:etl_manager_app/features/tasks/data/team_task_models.dart';
import 'package:etl_manager_app/features/tasks/data/team_tasks_repository.dart';
import 'package:etl_manager_app/features/tasks/domain/team_tasks_notifier.dart';

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._email, this._role);
  final String? _email;
  final String _role;

  static AuthState _for(String? email, String role) => AuthState(
        status: email == null ? AuthStatus.idle : AuthStatus.success,
        managerEmail: email,
        role: email == null ? null : role,
      );

  @override
  AuthState build() => _for(_email, _role); // no session restore

  void signInAs(String? email, {String role = 'crownest_head'}) =>
      state = _for(email, role);
}

typedef _Handler = Future<ResponseBody> Function(RequestOptions o);

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  _Handler handler = (_) async => _json(_page([_task(1)]));

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

  List<RequestOptions> lists() =>
      requests.where((r) => r.method == 'GET' && r.path == '/tasks/').toList();
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Future<ResponseBody> _offline(RequestOptions _) async =>
    throw const SocketException('offline');

Map<String, dynamic> _person(String key, String name, String label) =>
    {'key': key, 'name': name, 'role': 'x', 'role_label': label, 'zone': null};

/// The shape `/tasks` really returns for one task.
Map<String, dynamic> _task(
  int id, {
  String title = 'Check the freezer',
  String status = 'ASSIGNED',
  bool mine = true,
  bool overdue = false,
  String? dueAt,
}) =>
    {
      'id': id,
      'title': title,
      'description': null,
      'priority': 'high',
      'court_id': 4,
      'court_name': 'Bennett University',
      'due_at': dueAt,
      'is_overdue': overdue,
      'proof_required': true,
      'status': status,
      'assigner': _person('manager:1', 'Asha Head', 'Crownest Head'),
      'assignee': _person('staff:1', 'Manu Staff', 'ETL Staff'),
      'seen_at': null,
      'started_at': null,
      'completed_at': null,
      'cancelled_at': null,
      'created_at': '2026-11-15T06:30:00Z',
      'updated_at': '2026-11-15T06:30:00Z',
      'completion_note': null,
      'proof_photos': <String>[],
      'reopen_count': 0,
      'i_am_assigner': !mine,
      'i_am_assignee': mine,
      'can_start': mine && status == 'ASSIGNED',
      'can_complete': mine && (status == 'ASSIGNED' || status == 'IN_PROGRESS'),
      'can_reopen': !mine && status == 'DONE',
      'can_cancel': !mine && status != 'DONE',
      'can_comment': true,
    };

Map<String, dynamic> _page(
  List<Map<String, dynamic>> tasks, {
  bool hasMore = false,
  int mineOpen = 1,
  int mineOverdue = 0,
  int sentOpen = 0,
}) =>
    {
      'tasks': tasks,
      'has_more': hasMore,
      'summary': {
        'mine_open': mineOpen,
        'mine_overdue': mineOverdue,
        'sent_open': sentOpen,
        'sent_overdue': 0,
      },
    };

const _a = 'kuldeep@etl.com';
const _b = 'manjeet@etl.com';

class _Rig {
  _Rig({String? email = _a, String role = 'crownest_zone_manager'}) {
    adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuth(email, role)),
        dioProvider.overrideWithValue(dio),
      ],
    );
    container.listen(teamTasksNotifierProvider, (_, _) {});
  }

  late final _Adapter adapter;
  late final ProviderContainer container;

  TeamTasksState get state => container.read(teamTasksNotifierProvider);
  TeamTasksNotifier get notifier =>
      container.read(teamTasksNotifierProvider.notifier);

  void signInAs(String? email, {String role = 'crownest_zone_manager'}) =>
      (container.read(authNotifierProvider.notifier) as _FakeAuth)
          .signInAs(email, role: role);

  void dispose() => container.dispose();
}

Future<void> _until(bool Function() done, {String? reason}) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: reason ?? 'condition never became true');
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => TeamTasksNotifier.clock = DateTime.now);

  // ── Loading ────────────────────────────────────────────────────────────────

  group('loading', () {
    test('opens on the tasks waiting on me', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);

      final q = r.adapter.lists().single.queryParameters;
      expect(q['box'], 'mine');
      expect(q['status'], 'open');
      expect(r.state.tasks.single.title, 'Check the freezer');
      expect(r.state.summary.mineOpen, 1);
      expect(r.state.showSkeleton, isFalse);
      expect(r.state.showEmpty, isFalse);
    });

    test('a failed load is NOT an empty list', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.adapter.handler = _offline;
      await _until(() => r.state.loadFailed);

      expect(r.state.showFailure, isTrue);
      expect(r.state.showEmpty, isFalse,
          reason: '"you have no tasks" must only follow a real answer');
      expect(r.state.summaryKnown, isFalse,
          reason: 'the zero counts are "unknown", not "none"');
      expect(r.state.loadError, 'Check your internet and try again.');

      r.adapter.handler = (_) async => _json(_page([_task(1)]));
      await r.notifier.refresh();
      expect(r.state.loadFailed, isFalse);
      expect(r.state.tasks, hasLength(1));
    });

    test('an answer of "none" is the empty state', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.adapter.handler = (_) async => _json(_page([], mineOpen: 0));
      await _until(() => r.state.loaded);

      expect(r.state.showEmpty, isTrue);
      expect(r.state.showFailure, isFalse);
    });

    test("shows the server's own reason when it refused", () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.adapter.handler = (_) async => _json(
            {'detail': 'Team tasks are not available for your account.'},
            403,
          );
      await _until(() => r.state.loadFailed);
      expect(r.state.loadError, 'Team tasks are not available for your account.');
    });

    test('a failed refresh keeps the list that was already showing', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);

      r.adapter.handler = _offline;
      await r.notifier.refresh();

      expect(r.state.tasks, hasLength(1));
      expect(r.state.loadFailed, isTrue);
      expect(r.state.showFailure, isFalse,
          reason: 'old data stays on screen; only a banner says it is stale');
    });

    test('callers asking at the same moment share one request', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);
      final before = r.adapter.lists().length;

      await Future.wait([r.notifier.refresh(), r.notifier.refresh(), r.notifier.refresh()]);
      expect(r.adapter.lists().length, before + 1);
    });

    test('load more appends the next page and never repeats a task', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.adapter.handler = (o) async {
        final offset = o.queryParameters['offset'] as int;
        return _json(
          offset == 0
              ? _page([_task(1), _task(2)], hasMore: true)
              : _page([_task(2), _task(3)]),
        );
      };
      await _until(() => r.state.loaded);
      expect(r.state.hasMore, isTrue);

      await r.notifier.loadMore();
      expect(r.state.tasks.map((t) => t.id), [1, 2, 3]);
      expect(r.state.hasMore, isFalse);
      expect(r.adapter.lists().last.queryParameters['offset'], 2);
    });
  });

  // ── Switching view ─────────────────────────────────────────────────────────

  group('switching between "for me" and "by me"', () {
    test('asks for the other box and filter', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);

      expect(r.state.summaryKnown, isTrue);
      await r.notifier.show(box: TaskBox.sent, filter: TaskFilter.done);
      expect(r.state.summaryKnown, isTrue,
          reason: 'the counts are about the account, not the view');
      final q = r.adapter.lists().last.queryParameters;
      expect(q['box'], 'sent');
      expect(q['status'], 'done');
      expect(r.state.box, TaskBox.sent);
    });

    test('a slow answer for the view I left cannot overwrite the one I am on',
        () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);

      final slowMine = Completer<ResponseBody>();
      r.adapter.handler = (o) => o.queryParameters['box'] == 'mine'
          ? slowMine.future
          : Future.value(_json(_page([_task(9, title: 'sent one', mine: false)])));

      final reloadMine = r.notifier.refresh(); // in flight, for "mine"
      await r.notifier.show(box: TaskBox.sent);
      expect(r.state.tasks.single.title, 'sent one');

      slowMine.complete(_json(_page([_task(1, title: 'STALE mine')])));
      await reloadMine;
      await _settle();
      expect(r.state.box, TaskBox.sent);
      expect(r.state.tasks.single.title, 'sent one');
    });
  });

  // ── Shared phones ──────────────────────────────────────────────────────────

  group('a phone that changes hands', () {
    test("the next person never sees the previous person's tasks", () async {
      final r = _Rig(email: _a);
      addTearDown(r.dispose);
      r.adapter.handler = (_) async => _json(_page([_task(1, title: "A's task")], mineOpen: 5));
      await _until(() => r.state.loaded);
      expect(r.state.summary.mineOpen, 5);

      r.adapter.handler = (_) async => _json(_page([_task(2, title: "B's task")], mineOpen: 1));
      r.signInAs(_b);
      // Reset at once — before B's own answer arrives.
      expect(r.state.tasks, isEmpty);
      expect(r.state.summary.mineOpen, 0);
      expect(r.state.loaded, isFalse);
      expect(r.state.summaryKnown, isFalse);

      await _until(() => r.state.loaded);
      expect(r.state.tasks.single.title, "B's task");
    });

    test("A's request still in the air cannot land on B", () async {
      final r = _Rig(email: _a);
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);

      final slowA = Completer<ResponseBody>();
      r.adapter.handler = (_) => slowA.future;
      final aLoad = r.notifier.refresh();

      r.adapter.handler = (_) async => _json(_page([_task(2, title: "B's task")]));
      r.signInAs(_b);
      await _until(() => r.state.loaded);

      slowA.complete(_json(_page([_task(1, title: "A's task")], mineOpen: 7)));
      await aLoad;
      await _settle();

      expect(r.state.tasks.single.title, "B's task");
      expect(r.state.summary.mineOpen, isNot(7));
    });

    test("A's action finishing after the hand-over does not touch B's session",
        () async {
      final r = _Rig(email: _a);
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);

      final slowAction = Completer<ResponseBody>();
      r.adapter.handler = (o) => o.method == 'POST'
          ? slowAction.future
          : Future.value(_json(_page([_task(2, title: "B's task")])));
      final aAction = r.notifier.start(1); // A taps Start; the reply is slow

      r.signInAs(_b);
      await _until(() => r.state.loaded);
      final listsForB = r.adapter.lists().length;

      slowAction.complete(_json(_task(1, title: "A's task")));
      await aAction;
      await _settle();

      expect(r.adapter.lists().length, listsForB,
          reason: "A's finished action must not trigger anything in B's session");
      expect(r.state.tasks.single.title, "B's task");
    });

    test('signing out clears everything and asks for nothing', () async {
      final r = _Rig(email: _a);
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);
      final before = r.adapter.requests.length;

      r.signInAs(null);
      await _settle();
      expect(r.state.tasks, isEmpty);
      expect(r.adapter.requests.length, before);
      await r.notifier.refresh();
      expect(r.adapter.requests.length, before);
    });

    for (final role in ['outlet_manager', 'outlet_staff', 'etl_staff']) {
      test('a $role account never calls the tasks API', () async {
        final r = _Rig(email: 'someone@etl.com', role: role);
        addTearDown(r.dispose);
        await _settle();
        await r.notifier.refresh();
        expect(r.adapter.requests, isEmpty);
        expect(r.state.loaded, isFalse);
      });
    }
  });

  // ── Coming back to the app ─────────────────────────────────────────────────

  group('returning to the app', () {
    testWidgets('re-reads when the last answer is old', (tester) async {
      await tester.runAsync(() async {
        var now = DateTime(2026, 11, 16, 10);
        TeamTasksNotifier.clock = () => now;
        final r = _Rig();
        addTearDown(r.dispose);
        await _until(() => r.state.loaded);
        final before = r.adapter.lists().length;

        now = now.add(const Duration(minutes: 5));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await _until(() => r.adapter.lists().length == before + 1);
      });
    });

    testWidgets('a quick trip to the camera does not', (tester) async {
      await tester.runAsync(() async {
        var now = DateTime(2026, 11, 16, 10);
        TeamTasksNotifier.clock = () => now;
        final r = _Rig();
        addTearDown(r.dispose);
        await _until(() => r.state.loaded);
        final before = r.adapter.lists().length;

        now = now.add(const Duration(seconds: 20));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await _settle();
        expect(r.adapter.lists().length, before);
      });
    });

    testWidgets('always retries after a failed load', (tester) async {
      await tester.runAsync(() async {
        final now = DateTime(2026, 11, 16, 10);
        TeamTasksNotifier.clock = () => now;
        final r = _Rig();
        addTearDown(r.dispose);
        await _until(() => r.state.loaded);
        r.adapter.handler = _offline;
        await r.notifier.refresh();
        expect(r.state.loadFailed, isTrue);

        r.adapter.handler = (_) async => _json(_page([_task(1)]));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await _until(() => !r.state.loadFailed);
      });
    });
  });

  // ── Actions ────────────────────────────────────────────────────────────────

  group('actions', () {
    test('assigning sends exactly what was chosen, then re-reads the list',
        () async {
      final r = _Rig(role: 'crownest_head');
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);
      final listsBefore = r.adapter.lists().length;
      r.adapter.handler = (o) async => o.method == 'POST'
          ? _json(_task(7, mine: false), 201)
          : _json(_page([_task(7, mine: false)]));

      final due = DateTime(2026, 11, 20, 18, 30); // local
      final created = await r.notifier.create(
        NewTaskDraft(
          title: 'Fix the sign',
          description: '  near gate 2 ',
          assigneeKey: 'staff:1',
          priority: TaskPriority.urgent,
          courtId: 4,
          dueAt: due,
          proofRequired: false,
        ),
      );
      expect(created.id, 7);

      final post = r.adapter.requests.singleWhere((x) => x.method == 'POST');
      expect(post.path, '/tasks/');
      expect(post.data, {
        'title': 'Fix the sign',
        'description': 'near gate 2',
        'assignee': 'staff:1',
        'priority': 'urgent',
        'court_id': 4,
        'due_at': due.toUtc().toIso8601String(),
        'proof_required': false,
      });
      expect((post.data['due_at'] as String).endsWith('Z'), isTrue,
          reason: 'the deadline goes out as UTC, never as bare local time');

      await _until(() => r.adapter.lists().length == listsBefore + 1);
    });

    test('proof is on unless switched off, and optional fields are omitted',
        () {
      const draft = NewTaskDraft(title: 'T', assigneeKey: 'manager:2');
      expect(draft.toJson(), {
        'title': 'T',
        'assignee': 'manager:2',
        'priority': 'normal',
        'proof_required': true,
      });
    });

    test('each action hits its own endpoint', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);
      r.adapter.handler = (o) async =>
          o.method == 'POST' ? _json(_task(3)) : _json(_page([_task(3)]));

      await r.notifier.start(3);
      await r.notifier.complete(3, note: ' ok ', photos: ['uploads/team_tasks/a.jpg']);
      await r.notifier.reopen(3, 'redo');
      await r.notifier.cancel(3);
      await r.notifier.comment(3, 'hi');
      await r.notifier.markSeen(3);

      final posts = r.adapter.requests.where((x) => x.method == 'POST').toList();
      expect(posts.map((p) => p.path), [
        '/tasks/3/start',
        '/tasks/3/complete',
        '/tasks/3/reopen',
        '/tasks/3/cancel',
        '/tasks/3/comments',
        '/tasks/3/seen',
      ]);
      expect(posts[1].data, {'note': 'ok', 'photos': ['uploads/team_tasks/a.jpg']});
      expect(posts[2].data, {'note': 'redo'});
      expect(posts[3].data, <String, dynamic>{});
    });

    test("a refused action throws, and the reason is the server's", () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);
      r.adapter.handler = (o) async => o.method == 'POST'
          ? _json({'detail': 'A proof photo is required to complete this task.'}, 400)
          : _json(_page([_task(3)]));

      Object? caught;
      try {
        await r.notifier.complete(3);
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(taskErrorMessage(caught!),
          'A proof photo is required to complete this task.');
    });

    test('marking seen never throws, even offline', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await _until(() => r.state.loaded);
      r.adapter.handler = _offline;
      expect(await r.notifier.markSeen(3), isNull);
    });
  });

  // ── Wire format ────────────────────────────────────────────────────────────

  group('wire format', () {
    test('reads a task exactly as the server sent it', () {
      final t = TeamTask.fromJson({
        ..._task(5, status: 'IN_PROGRESS', overdue: true, dueAt: '2026-11-15T12:00:00Z'),
        'events': [
          {
            'id': 1,
            'kind': 'completed',
            'actor_name': 'Manu Staff',
            'actor_role_label': 'ETL Staff',
            'mine': true,
            'note': 'done',
            'photos': ['uploads/team_tasks/a.jpg'],
            'created_at': '2026-11-15T12:30:00Z',
          },
        ],
      });
      expect(t.status, TaskStatus.inProgress);
      expect(t.priority, TaskPriority.high);
      expect(t.isOverdue, isTrue);
      expect(t.isOpen, isTrue);
      expect(t.dueAt, DateTime.utc(2026, 11, 15, 12).toLocal());
      expect(t.dueAt!.isUtc, isFalse, reason: 'times are shown in local time');
      expect(t.counterpart.name, 'Asha Head', reason: 'I am the assignee');
      expect(t.canComplete, isTrue);
      expect(t.canReopen, isFalse);
      expect(t.events.single.photos, ['uploads/team_tasks/a.jpg']);
      expect(t.events.single.mine, isTrue);
    });

    test('unknown or missing values fall back safely', () {
      final t = TeamTask.fromJson({
        'id': 1,
        'title': 'x',
        'status': 'SOMETHING_NEW',
        'priority': null,
        'assigner': {'key': 'manager:1', 'name': ''},
        'assignee': {'key': 'staff:2', 'name': 'Single'},
      });
      expect(t.status, TaskStatus.assigned);
      expect(t.priority, TaskPriority.normal);
      expect(t.proofRequired, isTrue, reason: 'proof defaults ON');
      expect(t.canComplete, isFalse, reason: 'no permission unless the server grants it');
      expect(t.assigner.initials, '?');
      expect(t.assignee.initials, 'S');
      expect(const TaskPerson(key: 'k', name: 'Asha  Rani Head').initials, 'AH');
    });

    test('error messages are ones a person can act on', () {
      DioException ex(Object? data, [int? code]) => DioException(
            requestOptions: RequestOptions(path: '/'),
            response: code == null
                ? null
                : Response(requestOptions: RequestOptions(path: '/'), statusCode: code, data: data),
          );
      expect(taskErrorMessage(ex(null)), 'Check your internet and try again.');
      expect(taskErrorMessage(ex({'detail': 'Task not found.'}, 404)), 'Task not found.');
      expect(
        taskErrorMessage(ex({
          'detail': [
            {'msg': 'Value error, Give the task a title.'},
          ],
        }, 422)),
        'Give the task a title.',
      );
      expect(taskErrorMessage(ex('<html>', 502)), 'Something went wrong. Please try again.');
      expect(taskErrorMessage(StateError('x')), 'Something went wrong. Please try again.');
    });

    test('team tasks are for the heads and the field tier only', () {
      bool can(String? role) => AuthState(
            status: AuthStatus.success,
            managerEmail: 'x@etl.com',
            role: role,
          ).canUseTeamTasks;

      for (final role in [
        'crownest_head',
        'operations_office',
        'crownest_ops_head',
        'azimuth_management',
        'etl_manager',
        'manager',
        'crownest_zone_manager',
        'crownest_maintenance_head',
        'azimuth_maintenance',
      ]) {
        expect(can(role), isTrue, reason: role);
      }
      for (final role in [
        'etl_staff',
        'staff',
        'outlet_manager',
        'outlet_staff',
        null,
        'something_new',
      ]) {
        expect(can(role), isFalse, reason: '$role');
      }
    });

    test('"Operations - Office" is Crownest Head under another name', () {
      AuthState as(String role) => AuthState(
            status: AuthStatus.success,
            managerEmail: 'x@etl.com',
            role: role,
          );
      final a = as('operations_office');
      final b = as('crownest_head');
      expect(a.isOperationsOffice, isTrue);
      expect(a.isManagement, isTrue);
      for (final pair in [
        (a.isManagement, b.isManagement),
        (a.isEtlManager, b.isEtlManager),
        (a.isManager, b.isManager),
        (a.isReadOnly, b.isReadOnly),
        (a.isOpsHead, b.isOpsHead),
        (a.isMaintenanceWorker, b.isMaintenanceWorker),
        (a.isStaff, b.isStaff),
        (a.isOutletManager, b.isOutletManager),
        (a.canUseTeamTasks, b.canUseTeamTasks),
        (a.canMarkOwnAttendance, b.canMarkOwnAttendance),
      ]) {
        expect(pair.$1, pair.$2);
      }
      expect(a.landingRoute, b.landingRoute);
    });

    test('a notice only opens a task link, nothing else', () {
      NoticeModel n(String? route) => NoticeModel.fromJson({
            'id': 1,
            'audience': 'role',
            'type': 'task_assigned',
            'title': 't',
            'is_read': false,
            'route': route,
          });
      expect(n('/tasks/42').openableRoute, '/tasks/42');
      expect(n(null).openableRoute, isNull);
      expect(n('/notices').openableRoute, isNull);
      expect(n('/tasks/42/../../settings').openableRoute, isNull);
      expect(n('https://evil.example/tasks/1').openableRoute, isNull);
      expect(n('/tasks/abc').openableRoute, isNull);
    });
  });
}
