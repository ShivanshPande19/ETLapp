// lib/features/tasks/presentation/task_detail_screen.dart
//
// One task: who, what, by when, its proof and its whole history — plus the
// actions the signed-in person is allowed to take on it. Which buttons appear
// is decided entirely by the `can*` flags the server sent.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui/motion.dart';
import '../../../core/widgets/app_network_image.dart';
import '../data/team_task_models.dart';
import '../data/team_tasks_repository.dart';
import '../domain/team_tasks_notifier.dart';
import 'task_widgets.dart';

const kMaxProofPhotos = 6;

/// Picks one photo from the camera or gallery. A provider so tests can supply
/// a file without the platform plugin.
typedef TaskPhotoPicker = Future<File?> Function(ImageSource source);

final taskPhotoPickerProvider = Provider<TaskPhotoPicker>((ref) {
  return (source) async {
    final x = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1280,
    );
    return x == null ? null : File(x.path);
  };
});

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final int taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final _comment = TextEditingController();

  /// The freshest copy of the task: the answer to the last action. Shown at
  /// once, without waiting for the re-fetch that follows.
  TeamTask? _latest;
  bool _busy = false;
  bool _sendingComment = false;
  bool _seenSent = false;

  /// True once the opening cascade has played. After that, rows scrolled out
  /// and back in appear at once instead of animating again.
  bool _entered = false;
  Timer? _enterTimer;

  @override
  void initState() {
    super.initState();
    _comment.addListener(() => setState(() {}));
  }

  /// One step of the opening cascade.
  Widget _in(int index, Widget child) =>
      StaggerIn(index: index, enabled: !_entered, child: child);

  void _markEntered() {
    if (_entered || _enterTimer != null) return;
    // A Timer we own (not Future.delayed), so leaving the screen cancels it.
    _enterTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  void dispose() {
    _enterTimer?.cancel();
    _comment.dispose();
    super.dispose();
  }

  TeamTasksNotifier get _tasks => ref.read(teamTasksNotifierProvider.notifier);

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      // Opened straight from a notification: nothing underneath to return to.
      context.go('/tasks');
    }
  }

  void _accept(TeamTask t) {
    if (!mounted) return;
    setState(() => _latest = t);
    ref.invalidate(teamTaskDetailProvider(widget.taskId));
  }

  /// Tell the giver the task has been opened — once, and only by the doer.
  void _maybeMarkSeen(TeamTask t) {
    if (_seenSent || !t.iAmAssignee || t.seenAt != null || !t.isOpen) return;
    _seenSent = true;
    _tasks.markSeen(t.id).then((seen) {
      if (seen != null) _accept(seen);
    });
  }

  Future<void> _run(Future<TeamTask> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final t = await action();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _accept(t);
      if (done != null) showTaskSnack(context, done);
    } catch (e) {
      if (!mounted) return;
      showTaskSnack(context, taskErrorMessage(e), error: true);
      // The task may have moved on under us (409) — show its real state.
      ref.invalidate(teamTaskDetailProvider(widget.taskId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(TeamTask t) async {
    final done = await showModalBottomSheet<TeamTask>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: kTaskWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => CompleteTaskSheet(task: t),
    );
    if (done == null || !mounted) return;
    HapticFeedback.mediumImpact();
    _accept(done);
    showTaskSnack(context, 'Marked as done');
  }

  Future<void> _reopen(TeamTask t) async {
    final note = await _askNote(
      title: 'Send it back',
      message: 'Tell ${t.assignee.firstName} what still needs doing.',
      hint: 'What needs fixing?',
      action: 'Send back',
      required: true,
    );
    if (note == null) return;
    await _run(
      () => _tasks.reopen(t.id, note),
      done: 'Sent back to ${t.assignee.firstName}',
    );
  }

  Future<void> _cancel(TeamTask t) async {
    final note = await _askNote(
      title: 'Cancel this task?',
      message: '${t.assignee.firstName} will be told it is no longer needed.',
      hint: 'Reason (optional)',
      action: 'Cancel task',
      required: false,
      destructive: true,
    );
    if (note == null) return;
    await _run(
      () => _tasks.cancel(t.id, note: note.isEmpty ? null : note),
      done: 'Task cancelled',
    );
  }

  /// A small sheet that collects one note. Returns null if dismissed.
  Future<String?> _askNote({
    required String title,
    required String message,
    required String hint,
    required String action,
    required bool required,
    bool destructive = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: kTaskWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _NoteSheet(
        title: title,
        message: message,
        hint: hint,
        action: action,
        required: required,
        destructive: destructive,
      ),
    );
  }

  Future<void> _sendComment(TeamTask t) async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      final updated = await _tasks.comment(t.id, text);
      if (!mounted) return;
      _comment.clear();
      FocusScope.of(context).unfocus();
      _accept(updated);
    } catch (e) {
      if (!mounted) return;
      showTaskSnack(context, taskErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  void _viewPhoto(String url) {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: AppNetworkImage(
                url: url,
                fit: BoxFit.contain,
                background: Colors.transparent,
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(ctx).padding.top + 8,
            right: 12,
            child: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(ctx).pop(),
              icon: const Icon(
                Icons.close_rounded,
                color: kTaskWhite,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamTaskDetailProvider(widget.taskId));
    // A fresh fetch supersedes the copy held from the last action.
    ref.listen(teamTaskDetailProvider(widget.taskId), (_, next) {
      if (next.hasValue && !next.isLoading && _latest != null) {
        setState(() => _latest = null);
      }
    });

    final task = _latest ?? async.value;
    if (task != null) {
      _maybeMarkSeen(task);
      _markEntered();
    }

    return Scaffold(
      backgroundColor: kTaskBg,
      body: SafeArea(
        bottom: false,
        // Loading dissolves into the task rather than being replaced by it.
        child: MotionSwitcher(
          alignment: Alignment.center,
          child: task == null
              ? KeyedSubtree(
                  key: const ValueKey('wait'),
                  child: _unavailable(async),
                )
              : Column(
                  key: const ValueKey('task'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(task),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: kTaskWhite,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Expanded(
                              child: RefreshIndicator(
                                color: kTaskBlack,
                                onRefresh: () async {
                                  ref.invalidate(
                                    teamTaskDetailProvider(widget.taskId),
                                  );
                                  await ref
                                      .read(
                                        teamTaskDetailProvider(
                                          widget.taskId,
                                        ).future,
                                      )
                                      .catchError((_) => task);
                                },
                                child: _content(task),
                              ),
                            ),
                            // The bar changes with the task's state (Start
                            // disappears once started, everything goes when it
                            // is done): resize and crossfade, never jump.
                            AnimatedSize(
                              duration: Motion.base,
                              curve: Motion.inOut,
                              alignment: Alignment.bottomCenter,
                              child: AnimatedSwitcher(
                                duration: Motion.quick,
                                child: KeyedSubtree(
                                  key: ValueKey(
                                    '${task.canStart}${task.canComplete}'
                                    '${task.canReopen}${task.canCancel}',
                                  ),
                                  child: _actions(task),
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
      ),
    );
  }

  /// Loading, or the task could not be opened at all.
  Widget _unavailable(AsyncValue<TeamTask> async) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: TaskBackPill(onTap: _back),
        ),
        Expanded(
          child: Center(
            child: async.hasError
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 34,
                          color: kTaskWhite.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          "Couldn't open this task",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kTaskWhite,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          taskErrorMessage(async.error!),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.4,
                            color: kTaskWhite.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: () => ref.invalidate(
                            teamTaskDetailProvider(widget.taskId),
                          ),
                          child: Text(
                            'Try again',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: kTaskWhite,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kTaskWhite,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _header(TeamTask t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TaskBackPill(onTap: _back),
              const Spacer(),
              TaskStatusPill(task: t, onDark: true),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            t.title,
            style: GoogleFonts.inter(
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: kTaskWhite,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.iAmAssignee
                ? 'From ${t.assigner.name}  ·  ${taskAgo(t.createdAt)}'
                : 'You gave this to ${t.assignee.name}  ·  ${taskAgo(t.createdAt)}',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: kTaskWhite.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(TeamTask t) {
    final chips = taskMetaChips(t);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        _in(0, _PeopleCard(task: t)),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 16),
          _in(
            1,
            Wrap(
              spacing: 14,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            ),
          ),
        ],
        if (t.description != null && t.description!.isNotEmpty) ...[
          _in(2, const _Section('Details')),
          _in(
            2,
            Text(
              t.description!,
              style: GoogleFonts.inter(
                fontSize: 14.5,
                height: 1.5,
                color: kTaskBlack,
              ),
            ),
          ),
        ],
        if (t.status == TaskStatus.done) ...[
          _in(3, const _Section('Proof of work')),
          // Keyed, so a task that has just been finished gets its proof card
          // rising in — the payoff of the "Mark as done" tap.
          StaggerIn(
            key: const ValueKey('proof'),
            index: _entered ? 0 : 3,
            child: _ProofBlock(task: t, onOpen: _viewPhoto),
          ),
        ],
        _in(4, const _Section('Activity')),
        for (var i = 0; i < t.events.length; i++)
          // Keyed by event: a new line of history (a comment, a status
          // change) rises in on its own while the rest stay put.
          StaggerIn(
            key: ValueKey('event-${t.events[i].id}'),
            index: _entered ? 0 : 4 + i,
            child: _EventRow(
              event: t.events[i],
              last: i == t.events.length - 1,
              onOpen: _viewPhoto,
            ),
          ),
        if (t.canComment) ...[
          const SizedBox(height: 10),
          _in(
            6,
            _CommentBox(
              controller: _comment,
              sending: _sendingComment,
              onSend: () => _sendComment(t),
            ),
          ),
        ],
      ],
    );
  }

  /// The bottom bar. Empty (and takes no space) when the viewer has nothing
  /// they are allowed to do.
  Widget _actions(TeamTask t) {
    final buttons = <Widget>[];

    if (t.canStart) {
      buttons.add(
        Expanded(
          child: _OutlineAction(
            key: const Key('task-start'),
            label: 'Start',
            icon: Icons.play_arrow_rounded,
            onPressed: _busy ? null : () => _run(() => _tasks.start(t.id)),
          ),
        ),
      );
    }
    if (t.canComplete) {
      buttons.add(
        Expanded(
          flex: 2,
          child: TaskPrimaryButton(
            key: const Key('task-complete'),
            label: 'Mark as done',
            icon: Icons.check_rounded,
            onPressed: _busy ? null : () => _complete(t),
          ),
        ),
      );
    }
    if (t.canReopen) {
      buttons.add(
        Expanded(
          child: _OutlineAction(
            key: const Key('task-reopen'),
            label: 'Not done — send back',
            icon: Icons.undo_rounded,
            onPressed: _busy ? null : () => _reopen(t),
          ),
        ),
      );
    }
    if (t.canCancel) {
      buttons.add(
        Expanded(
          child: _OutlineAction(
            key: const Key('task-cancel'),
            label: 'Cancel task',
            icon: Icons.close_rounded,
            color: kTaskRed,
            onPressed: _busy ? null : () => _cancel(t),
          ),
        ),
      );
    }
    if (buttons.isEmpty) return const SizedBox.shrink();

    final spaced = <Widget>[];
    for (final b in buttons) {
      if (spaced.isNotEmpty) spaced.add(const SizedBox(width: 10));
      spaced.add(b);
    }
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: const BoxDecoration(
        color: kTaskWhite,
        border: Border(top: BorderSide(color: kTaskLine)),
      ),
      child: Row(children: spaced),
    );
  }
}

// ─── Pieces ──────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: kTaskGrey,
        ),
      ),
    );
  }
}

class _PeopleCard extends StatelessWidget {
  const _PeopleCard({required this.task});

  final TeamTask task;

  @override
  Widget build(BuildContext context) {
    Widget row(String tag, TaskPerson p, bool me) {
      return Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              tag,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kTaskGrey,
              ),
            ),
          ),
          TaskAvatar(person: p, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me ? '${p.name} (you)' : p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: kTaskBlack,
                  ),
                ),
                if (p.roleLabel.isNotEmpty)
                  Text(
                    p.roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12.5, color: kTaskGrey),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kTaskSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          row('From', task.assigner, task.iAmAssigner),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: kTaskLine),
          ),
          row('To', task.assignee, task.iAmAssignee),
        ],
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.onOpen,
    this.size = 84,
  });

  final List<String> photos;
  final ValueChanged<String> onOpen;
  final double size;

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.of(context).devicePixelRatio).round();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final url in photos)
          Semantics(
            button: true,
            label: 'Open photo',
            child: GestureDetector(
              onTap: () => onOpen(url),
              child: AppNetworkImage(
                url: url,
                width: size,
                height: size,
                borderRadius: BorderRadius.circular(12),
                background: kTaskSoft,
                accent: kTaskGrey,
                memCacheWidth: px,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProofBlock extends StatelessWidget {
  const _ProofBlock({required this.task, required this.onOpen});

  final TeamTask task;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final hasNote = t.completionNote != null && t.completionNote!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kTaskGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: kTaskGreen.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: kTaskGreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Done by ${t.assignee.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: kTaskBlack,
                      ),
                    ),
                    if (t.completedAt != null)
                      Text(
                        taskDayTime(t.completedAt!),
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: kTaskGrey,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (t.proofPhotos.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PhotoStrip(photos: t.proofPhotos, onOpen: onOpen),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              t.proofRequired
                  ? 'No photo attached.'
                  : 'No photo was required for this task.',
              style: GoogleFonts.inter(fontSize: 12.5, color: kTaskGrey),
            ),
          ],
          if (hasNote) ...[
            const SizedBox(height: 12),
            Text(
              t.completionNote!,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                color: kTaskBlack,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.last,
    required this.onOpen,
  });

  final TaskEvent event;
  final bool last;
  final ValueChanged<String> onOpen;

  ({IconData icon, Color color, String text}) get _style {
    final who = event.mine ? 'You' : event.actorName;
    switch (event.kind) {
      case 'created':
        return (
          icon: Icons.add_task_rounded,
          color: kTaskBlack,
          text: '$who gave this task',
        );
      case 'seen':
        return (
          icon: Icons.visibility_outlined,
          color: kTaskGrey,
          text: '$who saw it',
        );
      case 'started':
        return (
          icon: Icons.play_arrow_rounded,
          color: kTaskBlack,
          text: '$who started',
        );
      case 'completed':
        return (
          icon: Icons.check_rounded,
          color: kTaskGreen,
          text: '$who marked it done',
        );
      case 'reopened':
        return (
          icon: Icons.undo_rounded,
          color: kTaskAmber,
          text: '$who sent it back',
        );
      case 'cancelled':
        return (
          icon: Icons.close_rounded,
          color: kTaskRed,
          text: '$who cancelled it',
        );
      case 'comment':
        return (
          icon: Icons.chat_bubble_outline_rounded,
          color: kTaskBlack,
          text: who,
        );
      default:
        return (icon: Icons.circle_outlined, color: kTaskGrey, text: who);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final hasNote = event.note != null && event.note!.isNotEmpty;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: 0.09),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(s.icon, size: 15, color: s.color),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: kTaskLine,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 5, bottom: last ? 4 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          s.text,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: kTaskBlack,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        taskAgo(event.createdAt),
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: kTaskGrey,
                        ),
                      ),
                    ],
                  ),
                  if (hasNote) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: kTaskSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        event.note!,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          height: 1.45,
                          color: kTaskBlack,
                        ),
                      ),
                    ),
                  ],
                  if (event.photos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _PhotoStrip(photos: event.photos, onOpen: onOpen, size: 56),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBox extends StatelessWidget {
  const _CommentBox({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty && !sending;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        color: kTaskSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('task-comment'),
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: kTaskBlack,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.4,
                color: kTaskBlack,
              ),
              decoration: InputDecoration(
                hintText: 'Add a comment…',
                hintStyle: GoogleFonts.inter(fontSize: 14, color: kTaskGrey),
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          IconButton(
            key: const Key('task-comment-send'),
            tooltip: 'Send comment',
            onPressed: canSend ? onSend : null,
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kTaskBlack,
                    ),
                  )
                : Icon(
                    Icons.arrow_upward_rounded,
                    color: canSend ? kTaskWhite : kTaskGrey,
                    size: 18,
                  ),
            style: IconButton.styleFrom(
              backgroundColor: canSend ? kTaskBlack : kTaskLine,
              disabledBackgroundColor: kTaskLine,
              minimumSize: const Size(36, 36),
              fixedSize: const Size(36, 36),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color = kTaskBlack,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: color.withValues(alpha: 0.4),
          side: BorderSide(color: color.withValues(alpha: 0.35), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collects a single note (the reopen reason, or an optional cancel reason).
class _NoteSheet extends StatefulWidget {
  const _NoteSheet({
    required this.title,
    required this.message,
    required this.hint,
    required this.action,
    required this.required,
    required this.destructive,
  });

  final String title;
  final String message;
  final String hint;
  final String action;
  final bool required;
  final bool destructive;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final ok = !widget.required || _note.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        media.viewInsets.bottom + media.padding.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kTaskBlack,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.message,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              height: 1.4,
              color: kTaskGrey,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('note-field'),
            controller: _note,
            autofocus: widget.required,
            minLines: 2,
            maxLines: 5,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: kTaskBlack,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              height: 1.4,
              color: kTaskBlack,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: GoogleFonts.inter(fontSize: 14.5, color: kTaskGrey),
              counterText: '',
              filled: true,
              fillColor: kTaskSoft,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kTaskBlack, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TaskPrimaryButton(
            key: const Key('note-submit'),
            label: widget.action,
            color: widget.destructive ? kTaskRed : kTaskBlack,
            onPressed: ok
                ? () => Navigator.of(context).pop(_note.text.trim())
                : null,
          ),
          if (widget.destructive) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Keep the task',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: kTaskBlack,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Finish a task: attach the proof (when required), add a note, send.
class CompleteTaskSheet extends ConsumerStatefulWidget {
  const CompleteTaskSheet({super.key, required this.task});

  final TeamTask task;

  @override
  ConsumerState<CompleteTaskSheet> createState() => _CompleteTaskSheetState();
}

class _CompleteTaskSheetState extends ConsumerState<CompleteTaskSheet> {
  final _note = TextEditingController();
  final List<File> _photos = [];

  /// Server paths of the photos already uploaded, by local path — so a retry
  /// after a failed submit does not upload the same photo twice.
  final Map<String, String> _uploaded = {};
  bool _busy = false;
  String? _progress;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _needsPhoto => widget.task.proofRequired && _photos.isEmpty;

  Future<void> _add(ImageSource source) async {
    if (_busy || _photos.length >= kMaxProofPhotos) return;
    try {
      final file = await ref.read(taskPhotoPickerProvider)(source);
      if (file == null || !mounted) return;
      setState(() {
        _photos.add(file);
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = source == ImageSource.camera
            ? "Couldn't open the camera. Allow camera access and try again."
            : "Couldn't open your photos. Allow photo access and try again.",
      );
    }
  }

  Future<void> _submit() async {
    if (_busy || _needsPhoto) return;
    FocusScope.of(context).unfocus();
    final tasks = ref.read(teamTasksNotifierProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final paths = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        final file = _photos[i];
        var path = _uploaded[file.path];
        if (path == null) {
          setState(
            () => _progress = 'Uploading photo ${i + 1} of ${_photos.length}…',
          );
          path = await tasks.uploadPhoto(file);
          if (path == null) {
            throw const _UploadFailed();
          }
          _uploaded[file.path] = path;
        }
        paths.add(path);
      }
      if (!mounted) return;
      setState(() => _progress = 'Finishing…');
      final done = await tasks.complete(
        widget.task.id,
        note: _note.text,
        photos: paths,
      );
      if (!mounted) return;
      Navigator.of(context).pop(done);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = e is _UploadFailed
            ? "A photo didn't upload. Check your internet and try again."
            : taskErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final t = widget.task;
    final full = _photos.length >= kMaxProofPhotos;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        media.viewInsets.bottom + media.padding.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark as done',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kTaskBlack,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.proofRequired
                  ? '${t.assigner.firstName} asked for a photo as proof.'
                  : 'A photo is optional for this task.',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                height: 1.4,
                color: kTaskGrey,
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSize(
              duration: Motion.base,
              curve: Motion.inOut,
              alignment: Alignment.topLeft,
              child: _photos.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final f in _photos)
                              _PopIn(
                                key: ValueKey(
                                  f.path + identityHashCode(f).toString(),
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      // The grey tile sits behind the picture, so the
                                      // photo's place is visible the moment it is picked
                                      // — not a blank gap until the image has decoded.
                                      child: Container(
                                        width: 76,
                                        height: 76,
                                        color: kTaskSoft,
                                        alignment: Alignment.center,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            const Icon(
                                              Icons.image_outlined,
                                              color: kTaskGrey,
                                            ),
                                            Image.file(
                                              f,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (!_busy)
                                      Positioned(
                                        top: -6,
                                        right: -6,
                                        child: Semantics(
                                          button: true,
                                          label: 'Remove photo',
                                          child: GestureDetector(
                                            onTap: () => setState(() {
                                              _photos.remove(f);
                                              _uploaded.remove(f.path);
                                            }),
                                            child: Container(
                                              width: 24,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                color: kTaskBlack,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: kTaskWhite,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                size: 13,
                                                color: kTaskWhite,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
            ),
            if (!full)
              Row(
                children: [
                  Expanded(
                    child: _OutlineAction(
                      key: const Key('complete-camera'),
                      label: 'Take photo',
                      icon: Icons.photo_camera_outlined,
                      onPressed: _busy ? null : () => _add(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OutlineAction(
                      key: const Key('complete-gallery'),
                      label: 'Gallery',
                      icon: Icons.photo_library_outlined,
                      onPressed: _busy ? null : () => _add(ImageSource.gallery),
                    ),
                  ),
                ],
              )
            else
              Text(
                'That is the most photos a task can carry ($kMaxProofPhotos).',
                style: GoogleFonts.inter(fontSize: 12.5, color: kTaskGrey),
              ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('complete-note'),
              controller: _note,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: kTaskBlack,
              style: GoogleFonts.inter(
                fontSize: 14.5,
                height: 1.4,
                color: kTaskBlack,
              ),
              decoration: InputDecoration(
                hintText: 'Add a note (optional)',
                hintStyle: GoogleFonts.inter(fontSize: 14.5, color: kTaskGrey),
                counterText: '',
                filled: true,
                fillColor: kTaskSoft,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kTaskBlack, width: 1.5),
                ),
              ),
            ),
            AnimatedSize(
              duration: Motion.quick,
              curve: Motion.inOut,
              alignment: Alignment.topLeft,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: kTaskRed,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _error!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: kTaskRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            TaskPrimaryButton(
              key: const Key('complete-submit'),
              label: _needsPhoto ? 'Add a photo to finish' : 'Mark as done',
              busy: _busy,
              busyLabel: _progress ?? 'Finishing…',
              icon: _needsPhoto
                  ? Icons.photo_camera_outlined
                  : Icons.check_rounded,
              color: kTaskGreen,
              onPressed: _needsPhoto ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Scales + fades its child in once, when it first appears.
class _PopIn extends StatelessWidget {
  const _PopIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Motion.base,
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
      ),
      child: child,
    );
  }
}

class _UploadFailed implements Exception {
  const _UploadFailed();
}
