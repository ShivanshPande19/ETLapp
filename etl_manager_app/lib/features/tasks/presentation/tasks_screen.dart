// lib/features/tasks/presentation/tasks_screen.dart
//
// The Tasks home: what is waiting on me, and what I am waiting on.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/ui/motion.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/domain/auth_notifier.dart';
import '../data/team_task_models.dart';
import '../domain/team_tasks_notifier.dart';
import 'assign_task_screen.dart';
import 'task_widgets.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Always open on fresh data — the list may have been loaded hours ago.
    Future.microtask(() {
      if (mounted) ref.read(teamTasksNotifierProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      ref.read(teamTasksNotifierProvider.notifier).loadMore();
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      // Opened by a notification tap: there is no screen underneath.
      context.go(ref.read(authNotifierProvider).landingRoute);
    }
  }

  void _open(TeamTask t) => context.push('/tasks/${t.id}');

  Future<void> _assign() async {
    HapticFeedback.selectionClick();
    final created = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<TeamTask>(motionRoute<TeamTask>(const AssignTaskScreen()));
    if (created == null || !mounted) return;
    showTaskSnack(context, 'Task sent to ${created.assignee.firstName}');
    // Land on the list where the new task now lives.
    ref
        .read(teamTasksNotifierProvider.notifier)
        .show(box: TaskBox.sent, filter: TaskFilter.open);
  }

  String _summaryLine(TeamTasksState st) {
    final s = st.summary;
    // Until the server has answered, the counts are unknown — and "nothing
    // waiting on you" would be a claim the app cannot back. Say nothing.
    if (!st.summaryKnown) return ' ';
    if (st.box == TaskBox.mine) {
      if (s.mineOpen == 0) return 'Nothing waiting on you';
      final late = s.mineOverdue > 0 ? '  ·  ${s.mineOverdue} overdue' : '';
      return '${s.mineOpen} waiting on you$late';
    }
    if (s.sentOpen == 0) return 'Nothing pending from others';
    final late = s.sentOverdue > 0 ? '  ·  ${s.sentOverdue} overdue' : '';
    return '${s.sentOpen} pending from others$late';
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(teamTasksNotifierProvider);
    final notifier = ref.read(teamTasksNotifierProvider.notifier);
    final inset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: kTaskBg,
      floatingActionButton: StaggerIn(
        index: 3,
        child: FloatingActionButton.extended(
          key: const Key('tasks-assign'),
          onPressed: _assign,
          backgroundColor: kTaskBlack,
          foregroundColor: kTaskWhite,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text(
            'Assign task',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TaskBackPill(onTap: _back),
                  const SizedBox(height: 14),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.antonSc(
                        fontSize: 36,
                        height: 0.95,
                        letterSpacing: -0.5,
                      ),
                      children: const [
                        TextSpan(
                          text: 'T',
                          style: TextStyle(color: kTaskRed),
                        ),
                        TextSpan(
                          text: 'ASKS',
                          style: TextStyle(color: kTaskWhite),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: Motion.base,
                    switchInCurve: Motion.enter,
                    switchOutCurve: Motion.enter,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    child: Text(
                      _summaryLine(st),
                      key: ValueKey(_summaryLine(st)),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color:
                            (st.box == TaskBox.mine
                                    ? st.summary.mineOverdue
                                    : st.summary.sentOverdue) >
                                0
                            ? const Color(0xFFFF6B6B)
                            : kTaskWhite.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _BoxSwitch(
                    box: st.box,
                    mineCount: st.summary.mineOpen,
                    sentCount: st.summary.sentOpen,
                    onChanged: (b) {
                      HapticFeedback.selectionClick();
                      notifier.show(box: b);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: kTaskWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                      child: _FilterRow(
                        filter: st.filter,
                        onChanged: (f) {
                          HapticFeedback.selectionClick();
                          notifier.show(filter: f);
                        },
                      ),
                    ),
                    if (st.loadFailed && st.tasks.isNotEmpty)
                      const _StaleBanner(),
                    Expanded(
                      child: RefreshIndicator(
                        color: kTaskBlack,
                        onRefresh: notifier.refresh,
                        // States (loading → list → empty/failed) and views
                        // (for me / by me, open / done) dissolve into each
                        // other instead of snapping.
                        child: MotionSwitcher(
                          child: KeyedSubtree(
                            key: ValueKey(_bodyKey(st)),
                            child: _body(st, inset),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _bodyKey(TeamTasksState st) {
    final kind = st.showSkeleton
        ? 'loading'
        : st.showFailure
        ? 'failed'
        : st.showEmpty
        ? 'empty'
        : 'list';
    return '${st.box.name}-${st.filter.name}-$kind';
  }

  Widget _body(TeamTasksState st, double bottomInset) {
    if (st.showSkeleton) {
      return const SkeletonList(dark: false, count: 5, tileHeight: 96);
    }
    if (st.showFailure) {
      return _pullable(
        TaskMessage(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load tasks",
          subtitle: st.loadError ?? 'Check your internet and try again.',
          action: SizedBox(
            width: 160,
            child: TaskPrimaryButton(
              label: 'Retry',
              busy: st.loading,
              busyLabel: 'Checking…',
              icon: Icons.refresh_rounded,
              onPressed: () =>
                  ref.read(teamTasksNotifierProvider.notifier).refresh(),
            ),
          ),
        ),
      );
    }
    if (st.showEmpty) {
      final (title, subtitle) = _emptyCopy(st);
      return _pullable(
        TaskMessage(
          icon: st.filter == TaskFilter.done
              ? Icons.task_alt_rounded
              : Icons.inbox_outlined,
          title: title,
          subtitle: subtitle,
        ),
      );
    }

    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 96),
      itemCount: st.tasks.length + (st.loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i >= st.tasks.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kTaskBlack,
                ),
              ),
            ),
          );
        }
        final t = st.tasks[i];
        // The first screenful cascades in; rows revealed later by scrolling
        // enter without a delay.
        return StaggerIn(
          key: ValueKey('task-${t.id}'),
          index: i < 8 ? i : 0,
          child: TaskCard(task: t, onTap: () => _open(t)),
        );
      },
    );
  }

  (String, String) _emptyCopy(TeamTasksState st) {
    final mine = st.box == TaskBox.mine;
    switch (st.filter) {
      case TaskFilter.open:
        return mine
            ? ("You're all clear", 'Tasks given to you will show up here.')
            : ('Nothing pending', 'Tap “Assign task” to give someone a task.');
      case TaskFilter.done:
        return mine
            ? ('Nothing completed yet', 'Tasks you finish will be kept here.')
            : (
                'Nothing completed yet',
                'Tasks others finish for you will be kept here.',
              );
      case TaskFilter.all:
        return mine
            ? ('No tasks yet', 'Tasks given to you will show up here.')
            : ('No tasks yet', 'Tap “Assign task” to give someone a task.');
    }
  }

  /// A message that can still be pulled down to refresh.
  Widget _pullable(Widget child) => LayoutBuilder(
    builder: (context, c) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight * 0.78),
          child: Center(child: child),
        ),
      ],
    ),
  );
}

/// "For me" / "By me", each with its open count.
class _BoxSwitch extends StatelessWidget {
  const _BoxSwitch({
    required this.box,
    required this.mineCount,
    required this.sentCount,
    required this.onChanged,
  });

  final TaskBox box;
  final int mineCount;
  final int sentCount;
  final ValueChanged<TaskBox> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kTaskWhite.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          // The white thumb slides between the halves rather than blinking
          // from one to the other.
          AnimatedAlign(
            duration: Motion.base,
            curve: Motion.inOut,
            alignment: box == TaskBox.mine
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kTaskWhite,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _seg(
                'For me',
                mineCount,
                TaskBox.mine,
                const Key('tasks-box-mine'),
              ),
              _seg(
                'By me',
                sentCount,
                TaskBox.sent,
                const Key('tasks-box-sent'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, int count, TaskBox value, Key key) {
    final on = box == value;
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        label: label,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: on ? null : () => onChanged(value),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: Motion.base,
                  curve: Motion.inOut,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: on ? kTaskBlack : kTaskWhite.withValues(alpha: 0.7),
                  ),
                  child: Text(label),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 7),
                  AnimatedContainer(
                    duration: Motion.base,
                    curve: Motion.inOut,
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: on
                          ? kTaskBlack
                          : kTaskWhite.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kTaskWhite,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.filter, required this.onChanged});

  final TaskFilter filter;
  final ValueChanged<TaskFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, TaskFilter value) {
      final on = filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            key: Key('tasks-filter-${value.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: on ? null : () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: on ? kTaskBlack : kTaskWhite,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: on ? kTaskBlack : kTaskLine,
                  width: 1.5,
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? kTaskWhite : kTaskBlack,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip('Open', TaskFilter.open),
          chip('Done', TaskFilter.done),
          chip('All', TaskFilter.all),
        ],
      ),
    );
  }
}

/// Shown above a list that could not be refreshed: what is on screen is the
/// last good answer, and saying so beats silently showing old data.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: kTaskAmber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 15, color: kTaskAmber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Couldn't refresh — pull down to try again.",
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: kTaskAmber,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
