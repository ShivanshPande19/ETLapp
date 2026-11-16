// Widget tests for the team-task screens, at phone size (360 x 740) so an
// overflow would fail the test.
//
// What they pin:
//   • the list never says "no tasks" for a load that failed or is still running;
//   • the buttons on a task follow the server's `can*` flags and nothing else;
//   • proof of work is ON by default, can be switched off by the assigner, and
//     a task that needs proof cannot be finished without a photo;
//   • a photo that was already uploaded is not uploaded again on retry.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:etl_manager_app/features/auth/domain/auth_notifier.dart';
import 'package:etl_manager_app/features/courts/data/courts_repository.dart';
import 'package:etl_manager_app/features/tasks/data/team_task_models.dart';
import 'package:etl_manager_app/features/tasks/data/team_tasks_repository.dart';
import 'package:etl_manager_app/features/tasks/domain/team_tasks_notifier.dart';
import 'package:etl_manager_app/features/tasks/presentation/assign_task_screen.dart';
import 'package:etl_manager_app/features/tasks/presentation/task_detail_screen.dart';
import 'package:etl_manager_app/features/tasks/presentation/tasks_entry.dart';
import 'package:etl_manager_app/features/tasks/presentation/tasks_screen.dart';

// ─── Fixtures ────────────────────────────────────────────────────────────────

const _head = TaskPerson(key: 'manager:1', name: 'Asha Head', roleLabel: 'Crownest Head');
const _ops = TaskPerson(key: 'manager:2', name: 'Omar Ops', roleLabel: 'Crownest Ops Head');
const _staff = TaskPerson(
  key: 'staff:1',
  name: 'Manu Staff',
  roleLabel: 'ETL Staff',
  zone: 'Bennett University',
);

/// A task as the ASSIGNEE (Manu) sees it, unless [mine] is false.
TeamTask _task({
  int id = 5,
  String title = 'Check the freezer',
  TaskStatus status = TaskStatus.assigned,
  bool mine = true,
  bool overdue = false,
  bool proof = true,
  DateTime? dueAt,
  List<TaskEvent> events = const [],
}) {
  final open = status == TaskStatus.assigned || status == TaskStatus.inProgress;
  return TeamTask(
    id: id,
    title: title,
    priority: TaskPriority.high,
    courtName: 'Bennett University',
    dueAt: dueAt,
    isOverdue: overdue,
    proofRequired: proof,
    status: status,
    assigner: _head,
    assignee: _staff,
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    completedAt: status == TaskStatus.done ? DateTime.now() : null,
    iAmAssigner: !mine,
    iAmAssignee: mine,
    canStart: mine && status == TaskStatus.assigned,
    canComplete: mine && open,
    canReopen: !mine && status == TaskStatus.done,
    canCancel: !mine && open,
    canComment: status != TaskStatus.cancelled,
    events: events,
  );
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._role);
  final String _role;

  @override
  AuthState build() => AuthState(
        status: AuthStatus.success,
        managerEmail: 'me@etl.com',
        role: _role,
      );
}

class _FakeTasks extends TeamTasksNotifier {
  _FakeTasks(this._initial);
  final TeamTasksState _initial;

  final calls = <String>[];
  final drafts = <NewTaskDraft>[];
  final uploads = <String>[];
  List<String>? completedWith;
  String? completedNote;

  /// What every action answers with.
  TeamTask answer = _task();

  /// When set, the next upload fails (returns null) and clears itself.
  bool failNextUpload = false;
  Object? completeError;

  @override
  TeamTasksState build() => _initial; // no auth, no network, no timers

  @override
  Future<void> refresh() async => calls.add('refresh');

  @override
  Future<void> show({TaskBox? box, TaskFilter? filter}) async =>
      calls.add('show:${box?.name}:${filter?.name}');

  @override
  Future<void> loadMore() async {}

  @override
  Future<TeamTask> create(NewTaskDraft draft) async {
    drafts.add(draft);
    return answer;
  }

  @override
  Future<TeamTask> start(int id) async {
    calls.add('start:$id');
    return answer;
  }

  @override
  Future<TeamTask> complete(int id, {String? note, List<String> photos = const []}) async {
    calls.add('complete:$id');
    final err = completeError;
    if (err != null) {
      completeError = null;
      throw err;
    }
    completedWith = photos;
    completedNote = note;
    return answer;
  }

  @override
  Future<TeamTask> reopen(int id, String note) async {
    calls.add('reopen:$id:$note');
    return answer;
  }

  @override
  Future<TeamTask> cancel(int id, {String? note}) async {
    calls.add('cancel:$id:${note ?? ''}');
    return answer;
  }

  @override
  Future<TeamTask> comment(int id, String note) async {
    calls.add('comment:$id:$note');
    return answer;
  }

  @override
  Future<TeamTask?> markSeen(int id) async {
    calls.add('seen:$id');
    return null;
  }

  @override
  Future<String?> uploadPhoto(File photo) async {
    if (failNextUpload) {
      failNextUpload = false;
      return null;
    }
    uploads.add(photo.path);
    return 'uploads/team_tasks/${uploads.length}.jpg';
  }
}

class _FakeRepo extends TeamTasksRepository {
  _FakeRepo({this.task}) : super(Dio());
  final TeamTask? task;

  @override
  Future<TeamTask> detail(int id) async => task ?? (throw StateError('none'));

  @override
  Future<List<TaskPerson>> people() async => const [_head, _ops, _staff];
}

class _FakeCourts extends CourtsRepository {
  _FakeCourts() : super(Dio());

  @override
  Future<List<Court>> getCourts() async => [
        Court(id: 4, name: 'Bennett University', location: '', isActive: true),
      ];
}

TeamTasksState _state({
  List<TeamTask> tasks = const [],
  bool loaded = true,
  bool loadFailed = false,
  bool loading = false,
  String? loadError,
  TaskBox box = TaskBox.mine,
  TaskFilter filter = TaskFilter.open,
  TaskSummary summary = const TaskSummary(),
}) =>
    TeamTasksState(
      box: box,
      filter: filter,
      tasks: tasks,
      summary: summary,
      loaded: loaded,
      loadFailed: loadFailed,
      loading: loading,
      loadError: loadError,
      // As in the app: the counts are known once the server has answered.
      summaryKnown: loaded,
    );

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(360, 740);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<_FakeTasks> _pump(
  WidgetTester t,
  Widget home, {
  TeamTasksState? state,
  TeamTask? detail,
  String role = 'crownest_zone_manager',
  File? pickedPhoto,
}) async {
  _phone(t);
  final fake = _FakeTasks(state ?? _state());
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/tasks/:id',
        builder: (_, s) => Scaffold(body: Text('opened task ${s.pathParameters['id']}')),
      ),
      GoRoute(path: '/tasks', builder: (_, _) => const Scaffold(body: Text('tasks page'))),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuth(role)),
        teamTasksNotifierProvider.overrideWith(() => fake),
        teamTasksRepositoryProvider.overrideWithValue(_FakeRepo(task: detail)),
        courtsRepositoryProvider.overrideWithValue(_FakeCourts()),
        taskPhotoPickerProvider.overrideWithValue(
          (ImageSource _) async => pickedPhoto ?? File('/nonexistent/proof.jpg'),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
  return fake;
}

/// Opens the assign screen the way the app does — pushed on top of a page —
/// so that closing it after a successful send has somewhere to return to.
class _AssignHost extends StatefulWidget {
  const _AssignHost();

  @override
  State<_AssignHost> createState() => _AssignHostState();
}

class _AssignHostState extends State<_AssignHost> {
  String _result = 'nothing sent';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_result),
            TextButton(
              onPressed: () async {
                final t = await Navigator.of(context).push<TeamTask>(
                  MaterialPageRoute(builder: (_) => const AssignTaskScreen()),
                );
                setState(() => _result = t == null ? 'closed' : 'returned task ${t.id}');
              },
              child: const Text('open assign'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<_FakeTasks> _pumpAssign(WidgetTester t) async {
  final fake = await _pump(t, const _AssignHost(), role: 'crownest_head');
  await t.tap(find.text('open assign'));
  await t.pumpAndSettle();
  return fake;
}

const _allClear = "You're all clear";
const _couldNotLoad = "Couldn't load tasks";

void main() {
  // A tap that lands on something else must FAIL the test, not just warn: a
  // missed tap on a form chip once hit the Send bar underneath and the test
  // carried on against a screen that had already closed.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  // ── The list ───────────────────────────────────────────────────────────────

  group('tasks list', () {
    testWidgets('still loading: no "all clear" yet', (t) async {
      await _pump(t, const TasksScreen(), state: _state(loaded: false));
      expect(find.text(_allClear), findsNothing);
      expect(find.text(_couldNotLoad), findsNothing);
    });

    testWidgets('a failed load says so, offers Retry, and never says "all clear"',
        (t) async {
      final fake = await _pump(
        t,
        const TasksScreen(),
        state: _state(
          loaded: false,
          loadFailed: true,
          loadError: 'Check your internet and try again.',
        ),
      );
      expect(find.text(_couldNotLoad), findsOneWidget);
      expect(find.text('Check your internet and try again.'), findsOneWidget);
      expect(find.text(_allClear), findsNothing);
      // The header must not claim a count it never received either.
      expect(find.text('Nothing waiting on you'), findsNothing);

      final before = fake.calls.where((c) => c == 'refresh').length;
      await t.tap(find.text('Retry'));
      await t.pump();
      expect(fake.calls.where((c) => c == 'refresh').length, before + 1);
    });

    testWidgets('a real "none" is the friendly empty state', (t) async {
      await _pump(t, const TasksScreen(), state: _state());
      expect(find.text(_allClear), findsOneWidget);
      expect(find.text(_couldNotLoad), findsNothing);
      expect(find.text('Nothing waiting on you'), findsOneWidget);
    });

    testWidgets('"by me" has its own empty copy', (t) async {
      await _pump(t, const TasksScreen(), state: _state(box: TaskBox.sent));
      expect(find.text('Nothing pending'), findsOneWidget);
    });

    testWidgets('shows who it is from, the deadline, and that it is overdue',
        (t) async {
      await _pump(
        t,
        const TasksScreen(),
        state: _state(
          tasks: [
            _task(
              overdue: true,
              dueAt: DateTime.now().subtract(const Duration(hours: 3)),
            ),
          ],
          summary: const TaskSummary(mineOpen: 1, mineOverdue: 1),
        ),
      );
      expect(find.text('Check the freezer'), findsOneWidget);
      expect(find.textContaining('Asha Head', findRichText: true), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('Was due'), findsOneWidget);
      expect(find.text('Photo proof'), findsOneWidget);
      expect(find.text('1 waiting on you  ·  1 overdue'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a task I gave reads "To <them>"', (t) async {
      await _pump(
        t,
        const TasksScreen(),
        state: _state(box: TaskBox.sent, tasks: [_task(mine: false)]),
        role: 'crownest_head',
      );
      expect(find.textContaining('To Manu Staff', findRichText: true), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('the switch and the filters ask for the other view', (t) async {
      final fake = await _pump(t, const TasksScreen(), state: _state(tasks: [_task()]));
      await t.tap(find.byKey(const Key('tasks-box-sent')));
      await t.pump();
      await t.tap(find.byKey(const Key('tasks-filter-done')));
      await t.pump();
      expect(fake.calls, containsAllInOrder(['show:sent:null', 'show:null:done']));
    });

    testWidgets('old data that could not be refreshed is marked as stale',
        (t) async {
      await _pump(
        t,
        const TasksScreen(),
        state: _state(tasks: [_task()], loadFailed: true),
      );
      expect(find.text('Check the freezer'), findsOneWidget);
      expect(find.textContaining("Couldn't refresh"), findsOneWidget);
      expect(find.text(_couldNotLoad), findsNothing);
    });

    testWidgets('pull-to-refresh reloads, from the empty state too', (t) async {
      final fake = await _pump(t, const TasksScreen(), state: _state());
      final before = fake.calls.where((c) => c == 'refresh').length;
      await t.fling(find.text(_allClear), const Offset(0, 400), 1200);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(fake.calls.where((c) => c == 'refresh').length, before + 1);
    });

    testWidgets('tapping a task opens that task', (t) async {
      await _pump(t, const TasksScreen(), state: _state(tasks: [_task(id: 42)]));
      await t.tap(find.text('Check the freezer'));
      await t.pumpAndSettle();
      expect(find.text('opened task 42'), findsOneWidget);
    });

  });

  // ── Entry points ───────────────────────────────────────────────────────────

  group('entry points', () {
    testWidgets('the header icon shows how many tasks are waiting on me',
        (t) async {
      await _pump(
        t,
        const Scaffold(backgroundColor: Colors.black, body: Center(child: TasksBell())),
        state: _state(summary: const TaskSummary(mineOpen: 3)),
        role: 'crownest_head',
      );
      expect(find.text('3'), findsOneWidget);
      await t.tap(find.byType(TasksBell));
      await t.pumpAndSettle();
      expect(find.text('tasks page'), findsOneWidget);
    });

    testWidgets('the home card says what is waiting, and opens Tasks', (t) async {
      await _pump(
        t,
        const Scaffold(body: Center(child: TasksHomeCard())),
        state: _state(summary: const TaskSummary(mineOpen: 2, mineOverdue: 1, sentOpen: 4)),
        role: 'crownest_ops_head',
      );
      expect(find.text('2 for you  ·  1 overdue'), findsOneWidget);
      expect(find.text('4 pending from others'), findsOneWidget);
      await t.tap(find.byType(TasksHomeCard));
      await t.pumpAndSettle();
      expect(find.text('tasks page'), findsOneWidget);
    });

    testWidgets('ETL staff get no entry point either', (t) async {
      await _pump(
        t,
        const Scaffold(body: Column(children: [TasksBell(), TasksHomeCard()])),
        state: _state(summary: const TaskSummary(mineOpen: 3)),
        role: 'etl_staff',
      );
      expect(find.text('Team Tasks'), findsNothing);
      expect(find.byIcon(Icons.assignment_turned_in_outlined), findsNothing);
    });

    testWidgets('the home card never claims "nothing" before it knows', (t) async {
      await _pump(
        t,
        const Scaffold(body: Center(child: TasksHomeCard())),
        state: _state(loaded: false, loadFailed: true),
        role: 'crownest_head',
      );
      expect(find.text('Tap to open your tasks'), findsOneWidget);
      expect(find.textContaining('Nothing'), findsNothing);
    });

    testWidgets('outlet accounts get no entry point at all', (t) async {
      await _pump(
        t,
        const Scaffold(body: Column(children: [TasksBell(), TasksHomeCard()])),
        state: _state(summary: const TaskSummary(mineOpen: 3)),
        role: 'outlet_manager',
      );
      expect(find.text('Team Tasks'), findsNothing);
      expect(find.byIcon(Icons.assignment_turned_in_outlined), findsNothing);
    });
  });

  // ── Assigning ──────────────────────────────────────────────────────────────

  group('assign a task', () {
    /// Bring a field of the form on screen. The form is a lazy list on a
    /// phone-sized screen: lower fields are not built until scrolled near, and
    /// `scrollUntilVisible` stops as soon as one is BUILT — which can still be
    /// under the pinned Send bar. `ensureVisible` then puts it in the viewport,
    /// so a tap lands on the field and not on Send.
    Future<void> reveal(WidgetTester t, Finder field) async {
      await t.scrollUntilVisible(
        field,
        200,
        scrollable: find
            .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
            .first,
      );
      await t.ensureVisible(field);
      await t.pump();
    }

    Future<void> scrollToProof(WidgetTester t) =>
        reveal(t, find.byKey(const Key('assign-proof')));

    Future<void> pickManu(WidgetTester t) async {
      await t.tap(find.byKey(const Key('assign-person')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('person-staff:1')));
      await t.pumpAndSettle();
    }

    testWidgets('needs a title and a person before it can be sent', (t) async {
      final fake = await _pumpAssign(t);

      await t.tap(find.byKey(const Key('assign-send')));
      await t.pump();
      expect(fake.drafts, isEmpty, reason: 'nothing chosen yet');

      await t.enterText(find.byKey(const Key('assign-title')), 'Fix the sign');
      await t.pump();
      await t.tap(find.byKey(const Key('assign-send')));
      await t.pump();
      expect(fake.drafts, isEmpty, reason: 'still nobody to give it to');

      await pickManu(t);
      expect(find.text('Assign to Manu'), findsOneWidget);
      await t.tap(find.byKey(const Key('assign-send')));
      await t.pumpAndSettle();
      expect(fake.drafts, hasLength(1));
      expect(find.text('returned task 5'), findsOneWidget,
          reason: 'the screen closes and hands the new task back');
    });

    testWidgets('proof of work is ON by default', (t) async {
      final fake = await _pumpAssign(t);
      await t.enterText(find.byKey(const Key('assign-title')), 'Fix the sign');
      await pickManu(t);
      await scrollToProof(t);
      expect(t.widget<Switch>(find.byKey(const Key('assign-proof'))).value, isTrue);
      expect(find.text('They must attach a photo to mark it done.'), findsOneWidget);

      await t.tap(find.byKey(const Key('assign-send')));
      await t.pumpAndSettle();
      final d = fake.drafts.single;
      expect(d.proofRequired, isTrue);
      expect(d.title, 'Fix the sign');
      expect(d.assigneeKey, 'staff:1');
      expect(d.priority, TaskPriority.normal);
      expect(d.dueAt, isNull);
      expect(d.courtId, isNull);
    });

    testWidgets('the assigner can switch proof off, and set priority and zone',
        (t) async {
      final fake = await _pumpAssign(t);
      await t.enterText(find.byKey(const Key('assign-title')), 'Fix the sign');
      await pickManu(t);

      await reveal(t, find.text('Urgent'));
      await t.tap(find.text('Urgent'));
      await t.pump();
      await reveal(t, find.text('Bennett University').last);
      await t.tap(find.text('Bennett University').last);
      await t.pump();
      await scrollToProof(t);
      await t.tap(find.byKey(const Key('assign-proof')));
      await t.pump();
      expect(find.text('They can mark it done without a photo.'), findsOneWidget);

      await t.tap(find.byKey(const Key('assign-send')));
      await t.pumpAndSettle();
      final d = fake.drafts.single;
      expect(d.proofRequired, isFalse);
      expect(d.priority, TaskPriority.urgent);
      expect(d.courtId, 4);
    });

    testWidgets('a quick deadline is a real time in the future', (t) async {
      final fake = await _pumpAssign(t);
      await t.enterText(find.byKey(const Key('assign-title')), 'Fix the sign');
      await pickManu(t);
      await reveal(t, find.text('Tomorrow 10 AM'));
      await t.tap(find.text('Tomorrow 10 AM'));
      await t.pump();
      await t.tap(find.byKey(const Key('assign-send')));
      await t.pumpAndSettle();

      final due = fake.drafts.single.dueAt!;
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect((due.day, due.hour, due.minute), (tomorrow.day, 10, 0));
      expect(due.isAfter(DateTime.now()), isTrue);
    });

    testWidgets('the person picker groups by team and can be searched', (t) async {
      await _pumpAssign(t);
      await t.tap(find.byKey(const Key('assign-person')));
      await t.pumpAndSettle();
      expect(find.text('CROWNEST HEAD'), findsOneWidget);
      expect(find.text('ETL STAFF'), findsOneWidget);
      expect(find.text('Bennett University'), findsWidgets); // Manu's zone

      await t.enterText(find.byKey(const Key('people-search')), 'omar');
      await t.pump();
      expect(find.text('Omar Ops'), findsOneWidget);
      expect(find.text('Manu Staff'), findsNothing);

      await t.enterText(find.byKey(const Key('people-search')), 'zzz');
      await t.pump();
      expect(find.text('No match'), findsOneWidget);
    });
  });

  // ── One task ───────────────────────────────────────────────────────────────

  group('task detail', () {
    testWidgets('the doer sees Start and Mark as done — and nothing else',
        (t) async {
      final fake = await _pump(t, const TaskDetailScreen(taskId: 5), detail: _task());
      expect(find.byKey(const Key('task-start')), findsOneWidget);
      expect(find.byKey(const Key('task-complete')), findsOneWidget);
      expect(find.byKey(const Key('task-cancel')), findsNothing);
      expect(find.byKey(const Key('task-reopen')), findsNothing);
      expect(fake.calls, contains('seen:5'), reason: 'opening it tells the giver');
      expect(t.takeException(), isNull);
    });

    testWidgets('the giver sees Cancel only, and opening it is not "seen"',
        (t) async {
      final fake = await _pump(
        t,
        const TaskDetailScreen(taskId: 5),
        detail: _task(mine: false),
        role: 'crownest_head',
      );
      expect(find.byKey(const Key('task-cancel')), findsOneWidget);
      expect(find.byKey(const Key('task-start')), findsNothing);
      expect(find.byKey(const Key('task-complete')), findsNothing);
      expect(fake.calls.where((c) => c.startsWith('seen')), isEmpty);
    });

    testWidgets('a finished task: the giver can send it back, with a reason',
        (t) async {
      final fake = await _pump(
        t,
        const TaskDetailScreen(taskId: 5),
        detail: _task(mine: false, status: TaskStatus.done),
        role: 'crownest_head',
      );
      expect(find.text('PROOF OF WORK'), findsOneWidget);
      expect(find.byKey(const Key('task-cancel')), findsNothing);

      await t.tap(find.byKey(const Key('task-reopen')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('note-submit')));
      await t.pumpAndSettle();
      expect(fake.calls.where((c) => c.startsWith('reopen')), isEmpty,
          reason: 'a reason is required');

      await t.enterText(find.byKey(const Key('note-field')), 'Shelf still dirty');
      await t.pump();
      await t.tap(find.byKey(const Key('note-submit')));
      await t.pumpAndSettle();
      expect(fake.calls, contains('reopen:5:Shelf still dirty'));
    });

    testWidgets('a finished task shows the doer no buttons', (t) async {
      await _pump(
        t,
        const TaskDetailScreen(taskId: 5),
        detail: _task(status: TaskStatus.done),
      );
      for (final k in ['task-start', 'task-complete', 'task-cancel', 'task-reopen']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });

    testWidgets('cancelling asks first, and the reason is optional', (t) async {
      final fake = await _pump(
        t,
        const TaskDetailScreen(taskId: 5),
        detail: _task(mine: false),
        role: 'crownest_head',
      );
      await t.tap(find.byKey(const Key('task-cancel')));
      await t.pumpAndSettle();
      expect(find.text('Cancel this task?'), findsOneWidget);
      await t.tap(find.text('Keep the task'));
      await t.pumpAndSettle();
      expect(fake.calls.where((c) => c.startsWith('cancel')), isEmpty);

      await t.tap(find.byKey(const Key('task-cancel')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('note-submit')));
      await t.pumpAndSettle();
      expect(fake.calls, contains('cancel:5:'));
    });

    testWidgets('Start and comments reach the server', (t) async {
      final fake = await _pump(t, const TaskDetailScreen(taskId: 5), detail: _task());
      await t.tap(find.byKey(const Key('task-start')));
      await t.pumpAndSettle();
      expect(fake.calls, contains('start:5'));

      await t.ensureVisible(find.byKey(const Key('task-comment')));
      await t.enterText(find.byKey(const Key('task-comment')), 'Which freezer?');
      await t.pump();
      await t.tap(find.byKey(const Key('task-comment-send')));
      await t.pumpAndSettle();
      expect(fake.calls, contains('comment:5:Which freezer?'));
    });

    testWidgets('the history reads as sentences', (t) async {
      await _pump(
        t,
        const TaskDetailScreen(taskId: 5),
        detail: _task(
          events: [
            const TaskEvent(id: 1, kind: 'created', actorName: 'Asha Head'),
            const TaskEvent(id: 2, kind: 'seen', actorName: 'Manu Staff', mine: true),
            const TaskEvent(
              id: 3,
              kind: 'reopened',
              actorName: 'Asha Head',
              note: 'Shelf still dirty',
            ),
          ],
        ),
      );
      await t.ensureVisible(find.text('Shelf still dirty'));
      expect(find.text('Asha Head gave this task'), findsOneWidget);
      expect(find.text('You saw it'), findsOneWidget);
      expect(find.text('Asha Head sent it back'), findsOneWidget);
    });

    testWidgets('a task that cannot be opened says why', (t) async {
      await _pump(t, const TaskDetailScreen(taskId: 5)); // repo throws
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text("Couldn't open this task"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  // ── Finishing, with proof ──────────────────────────────────────────────────

  group('mark as done', () {
    Future<_FakeTasks> open(WidgetTester t, {bool proof = true}) async {
      final fake = await _pump(
        t,
        const TaskDetailScreen(taskId: 5),
        detail: _task(proof: proof),
      );
      await t.tap(find.byKey(const Key('task-complete')));
      await t.pumpAndSettle();
      return fake;
    }

    testWidgets('proof required: cannot finish until a photo is added',
        (t) async {
      final fake = await open(t);
      expect(find.text('Add a photo to finish'), findsOneWidget);
      await t.tap(find.byKey(const Key('complete-submit')));
      await t.pump();
      expect(fake.calls.where((c) => c.startsWith('complete')), isEmpty);

      await t.tap(find.byKey(const Key('complete-camera')));
      await t.pumpAndSettle();
      expect(find.text('Add a photo to finish'), findsNothing);

      await t.enterText(find.byKey(const Key('complete-note')), 'all clean');
      await t.tap(find.byKey(const Key('complete-submit')));
      await t.pumpAndSettle();
      expect(fake.uploads, ['/nonexistent/proof.jpg']);
      expect(fake.completedWith, ['uploads/team_tasks/1.jpg']);
      expect(fake.completedNote, 'all clean');
      expect(find.byKey(const Key('complete-submit')), findsNothing,
          reason: 'the sheet closed');
    });

    testWidgets('proof switched off: can finish straight away', (t) async {
      final fake = await open(t, proof: false);
      expect(find.text('A photo is optional for this task.'), findsOneWidget);
      await t.tap(find.byKey(const Key('complete-submit')));
      await t.pumpAndSettle();
      expect(fake.completedWith, isEmpty);
      expect(fake.uploads, isEmpty);
    });

    testWidgets('a failed upload keeps the photo and does not finish the task',
        (t) async {
      final fake = await open(t);
      await t.tap(find.byKey(const Key('complete-gallery')));
      await t.pumpAndSettle();
      fake.failNextUpload = true;
      await t.tap(find.byKey(const Key('complete-submit')));
      await t.pumpAndSettle();

      expect(find.textContaining("didn't upload"), findsOneWidget);
      expect(fake.calls.where((c) => c.startsWith('complete')), isEmpty);

      await t.tap(find.byKey(const Key('complete-submit')));
      await t.pumpAndSettle();
      expect(fake.completedWith, ['uploads/team_tasks/1.jpg']);
    });

    testWidgets('retrying after the server refused does not upload the photo again',
        (t) async {
      final fake = await open(t);
      await t.tap(find.byKey(const Key('complete-camera')));
      await t.pumpAndSettle();
      fake.completeError = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 409,
          data: {'detail': 'This task has already changed. Refresh and try again.'},
        ),
      );
      await t.tap(find.byKey(const Key('complete-submit')));
      await t.pumpAndSettle();
      expect(find.text('This task has already changed. Refresh and try again.'), findsOneWidget);
      expect(fake.uploads, hasLength(1));

      await t.tap(find.byKey(const Key('complete-submit')));
      await t.pumpAndSettle();
      expect(fake.uploads, hasLength(1), reason: 'the same photo is not sent twice');
      expect(fake.completedWith, ['uploads/team_tasks/1.jpg']);
    });
  });
}
