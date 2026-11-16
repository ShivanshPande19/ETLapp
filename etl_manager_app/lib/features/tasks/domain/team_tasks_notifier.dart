// lib/features/tasks/domain/team_tasks_notifier.dart
//
// State for the Tasks screen: one box ("for me" / "by me") and one filter at a
// time, plus the counts that drive the badges.
//
// Three rules, each learned the hard way on the staff checklist:
//
//  1. THE SIGNED-IN ACCOUNT OWNS THE STATE. Staff share phones. Riverpod keeps
//     the SAME notifier instance across a rebuild and `ref.mounted` stays true,
//     so "is this response still for the current user?" is answered with a
//     generation counter that `build()` bumps on every account change. A
//     response that comes back for an older generation is dropped.
//
//  2. A FAILED LOAD IS NOT AN EMPTY LIST. "You have no tasks" is only ever
//     shown after the server actually said so.
//
//  3. NOTHING HERE DECIDES PERMISSIONS. The server sends `can*` flags with
//     every task and enforces them again when the action arrives.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/auth_notifier.dart';
import '../data/team_task_models.dart';
import '../data/team_tasks_repository.dart';

class TeamTasksState {
  final TaskBox box;
  final TaskFilter filter;
  final List<TeamTask> tasks;
  final TaskSummary summary;

  /// A load is in flight (the list may still be showing older data).
  final bool loading;

  /// The server has answered at least once for THIS box + filter.
  final bool loaded;
  final bool loadFailed;
  final String? loadError;
  final bool hasMore;
  final bool loadingMore;

  /// The counts in [summary] came from the server. False until the first
  /// successful load for this account — until then they are zeros that mean
  /// "not known yet", and nothing may present them as "you have none".
  /// Unlike [loaded] this survives switching box or filter: the counts are
  /// about the account, not about the view.
  final bool summaryKnown;

  const TeamTasksState({
    this.box = TaskBox.mine,
    this.filter = TaskFilter.open,
    this.tasks = const [],
    this.summary = const TaskSummary(),
    this.loading = false,
    this.loaded = false,
    this.loadFailed = false,
    this.loadError,
    this.hasMore = false,
    this.loadingMore = false,
    this.summaryKnown = false,
  });

  /// Nothing to show yet and nothing has failed: draw the skeleton.
  bool get showSkeleton => !loaded && !loadFailed;

  /// The load failed and there is no earlier list to fall back on.
  bool get showFailure => loadFailed && tasks.isEmpty;

  /// The server answered, and the answer was "none".
  bool get showEmpty => loaded && !loadFailed && tasks.isEmpty;

  TeamTasksState copyWith({
    TaskBox? box,
    TaskFilter? filter,
    List<TeamTask>? tasks,
    TaskSummary? summary,
    bool? loading,
    bool? loaded,
    bool? loadFailed,
    String? loadError,
    bool clearError = false,
    bool? hasMore,
    bool? loadingMore,
    bool? summaryKnown,
  }) => TeamTasksState(
    box: box ?? this.box,
    filter: filter ?? this.filter,
    tasks: tasks ?? this.tasks,
    summary: summary ?? this.summary,
    loading: loading ?? this.loading,
    loaded: loaded ?? this.loaded,
    loadFailed: loadFailed ?? this.loadFailed,
    loadError: clearError ? null : (loadError ?? this.loadError),
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    summaryKnown: summaryKnown ?? this.summaryKnown,
  );
}

class TeamTasksNotifier extends Notifier<TeamTasksState> {
  static const pageSize = 50;

  /// Coming back to the app re-reads the list only if the last good answer is
  /// older than this. Every proof photo sends the app to the camera and back,
  /// and that must not cost a request each time.
  static const resumeRefreshAfter = Duration(minutes: 1);

  /// The clock, replaceable in tests.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  DateTime? _lastLoadedAt;

  String? _owner;
  int _generation = 0;

  /// Bumped whenever the box or filter changes, so a response for the view the
  /// user has already left cannot overwrite the one they are looking at.
  int _viewSeq = 0;
  Future<void>? _inFlight;

  TeamTasksRepository get _repo => ref.read(teamTasksRepositoryProvider);

  @override
  TeamTasksState build() {
    _owner = ref.watch(authNotifierProvider.select((s) => s.managerEmail));
    final allowed = ref.watch(
      authNotifierProvider.select((s) => s.canUseTeamTasks),
    );
    // A new account (or sign-out): everything in flight belongs to the past.
    _generation++;
    _viewSeq++;
    _inFlight = null;
    _lastLoadedAt = null;

    final lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.onDispose(lifecycle.dispose);

    if (_owner != null && allowed) Future.microtask(_load);
    return const TeamTasksState();
  }

  bool get _active =>
      _owner != null && ref.read(authNotifierProvider).canUseTeamTasks;

  bool _stale(int generation) => !ref.mounted || generation != _generation;

  void _onResume() {
    if (!ref.mounted || !_active) return;
    // Coming back to the app is when tasks are most likely to have changed (a
    // notification was tapped, or hours have passed) — but a quick trip to the
    // camera and back is not a reason to ask again.
    final last = _lastLoadedAt;
    final fresh = last != null && clock().difference(last) < resumeRefreshAfter;
    if (state.loadFailed || !fresh) _load();
  }

  /// Reload the current view. Safe to call from anywhere, any number of times:
  /// concurrent callers share one request.
  Future<void> refresh() => _load();

  /// Switch box and/or filter.
  Future<void> show({TaskBox? box, TaskFilter? filter}) {
    final nextBox = box ?? state.box;
    final nextFilter = filter ?? state.filter;
    if (nextBox == state.box && nextFilter == state.filter) return _load();
    _viewSeq++;
    _inFlight = null;
    state = state.copyWith(
      box: nextBox,
      filter: nextFilter,
      tasks: const [],
      loaded: false,
      loadFailed: false,
      clearError: true,
      hasMore: false,
      loadingMore: false,
    );
    return _load();
  }

  Future<void> _load() {
    if (!_active) return Future.value();
    final running = _inFlight;
    if (running != null) return running;
    late final Future<void> mine;
    mine = _doLoad().whenComplete(() {
      if (identical(_inFlight, mine)) _inFlight = null;
    });
    _inFlight = mine;
    return mine;
  }

  Future<void> _doLoad() async {
    final gen = _generation;
    final view = _viewSeq;
    state = state.copyWith(loading: true);
    try {
      final page = await _repo.list(
        box: state.box,
        filter: state.filter,
        limit: pageSize,
      );
      if (_stale(gen) || view != _viewSeq) return;
      _lastLoadedAt = clock();
      state = state.copyWith(
        tasks: page.tasks,
        summary: page.summary,
        hasMore: page.hasMore,
        loading: false,
        loaded: true,
        loadFailed: false,
        clearError: true,
        summaryKnown: true,
      );
    } catch (e) {
      if (_stale(gen) || view != _viewSeq) return;
      state = state.copyWith(
        loading: false,
        loadFailed: true,
        loadError: taskErrorMessage(e),
      );
    }
  }

  Future<void> loadMore() async {
    if (!_active || !state.hasMore || state.loadingMore || state.loading) {
      return;
    }
    final gen = _generation;
    final view = _viewSeq;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _repo.list(
        box: state.box,
        filter: state.filter,
        limit: pageSize,
        offset: state.tasks.length,
      );
      if (_stale(gen) || view != _viewSeq) return;
      final seen = state.tasks.map((t) => t.id).toSet();
      state = state.copyWith(
        tasks: [
          ...state.tasks,
          ...page.tasks.where((t) => !seen.contains(t.id)),
        ],
        summary: page.summary,
        hasMore: page.hasMore,
        loadingMore: false,
        summaryKnown: true,
      );
    } catch (_) {
      if (_stale(gen) || view != _viewSeq) return;
      // Keep what is already on screen; the user can scroll again to retry.
      state = state.copyWith(loadingMore: false);
    }
  }

  // ─── Actions ───────────────────────────────────────────────────────────────
  //
  // Each returns the task as the server now has it, and THROWS on failure so
  // the screen can say exactly what went wrong. The list is then re-read from
  // the server rather than patched locally: order, counts and the `can*` flags
  // all change with a task's state, and the server is the one that knows them.

  Future<TeamTask> create(NewTaskDraft draft) =>
      _act(() => _repo.create(draft));

  Future<TeamTask> start(int id) => _act(() => _repo.start(id));

  Future<TeamTask> complete(
    int id, {
    String? note,
    List<String> photos = const [],
  }) => _act(() => _repo.complete(id, note: note, photos: photos));

  Future<TeamTask> reopen(int id, String note) =>
      _act(() => _repo.reopen(id, note));

  Future<TeamTask> cancel(int id, {String? note}) =>
      _act(() => _repo.cancel(id, note: note));

  Future<TeamTask> comment(int id, String note) =>
      _act(() => _repo.comment(id, note));

  /// The assignee opened the task. Best-effort: a failure here must never get
  /// in the way of reading the task.
  Future<TeamTask?> markSeen(int id) async {
    try {
      return await _act(() => _repo.markSeen(id));
    } catch (_) {
      return null;
    }
  }

  /// Upload one proof photo; null if it did not go through.
  Future<String?> uploadPhoto(File photo) => _repo.uploadPhoto(photo);

  Future<TeamTask> _act(Future<TeamTask> Function() call) async {
    final gen = _generation;
    final task = await call();
    // The account changed while this was in the air: the result belongs to
    // the previous user, so it must not touch the new user's list.
    if (!_stale(gen)) unawaited(_load());
    return task;
  }
}

final teamTasksNotifierProvider =
    NotifierProvider<TeamTasksNotifier, TeamTasksState>(TeamTasksNotifier.new);

/// One task with its full history, for the detail screen. Re-fetched whenever
/// it is invalidated (after an action, or when a live update arrives).
final teamTaskDetailProvider = FutureProvider.autoDispose.family<TeamTask, int>(
  (ref, id) async {
    // Rebuild — and so refetch — if the signed-in account changes.
    ref.watch(authNotifierProvider.select((s) => s.managerEmail));
    return ref.watch(teamTasksRepositoryProvider).detail(id);
  },
);

/// Everyone the signed-in user can give a task to.
final taskPeopleProvider = FutureProvider.autoDispose<List<TaskPerson>>((
  ref,
) async {
  ref.watch(authNotifierProvider.select((s) => s.managerEmail));
  return ref.watch(teamTasksRepositoryProvider).people();
});
