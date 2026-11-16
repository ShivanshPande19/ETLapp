// lib/features/tasks/presentation/assign_task_screen.dart
//
// Give someone a task. Two things are required — what, and who — and the
// rest has a sensible default, so the common case is: type, pick, send.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/motion.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../courts/data/courts_repository.dart';
import '../data/team_task_models.dart';
import '../data/team_tasks_repository.dart';
import '../domain/team_tasks_notifier.dart';
import 'task_widgets.dart';

/// Zones for the optional zone tag. Best-effort: with no zones the picker is
/// simply not shown, and a task can always be given without one.
final _taskCourtsProvider = FutureProvider.autoDispose<List<Court>>((
  ref,
) async {
  ref.watch(authNotifierProvider.select((s) => s.managerEmail));
  return ref.watch(courtsRepositoryProvider).getCourts();
});

enum _Due { none, twoHours, today, tomorrow, custom }

class AssignTaskScreen extends ConsumerStatefulWidget {
  const AssignTaskScreen({super.key});

  @override
  ConsumerState<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends ConsumerState<AssignTaskScreen> {
  final _title = TextEditingController();
  final _details = TextEditingController();

  TaskPerson? _assignee;
  TaskPriority _priority = TaskPriority.normal;
  _Due _due = _Due.none;
  DateTime? _dueAt;
  int? _courtId;

  /// Proof of work is ON unless the assigner switches it off.
  bool _proof = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  bool get _ready => _title.text.trim().isNotEmpty && _assignee != null;

  /// Today's 6 PM is only offered while it is still comfortably ahead.
  bool get _todayAvailable => DateTime.now().hour < 17;

  void _setDue(_Due choice) {
    final now = DateTime.now();
    DateTime? at;
    switch (choice) {
      case _Due.none:
        at = null;
      case _Due.twoHours:
        at = now.add(const Duration(hours: 2));
      case _Due.today:
        at = DateTime(now.year, now.month, now.day, 18);
      case _Due.tomorrow:
        at = DateTime(
          now.year,
          now.month,
          now.day,
          10,
        ).add(const Duration(days: 1));
      case _Due.custom:
        return; // set by _pickCustom
    }
    HapticFeedback.selectionClick();
    setState(() {
      _due = choice;
      _dueAt = at;
    });
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final seed = _dueAt ?? now.add(const Duration(hours: 2));
    final date = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Deadline date',
      builder: AppTheme.datePickerBuilder,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(seed),
      helpText: 'Deadline time',
      builder: AppTheme.datePickerBuilder,
    );
    if (time == null || !mounted) return;
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!at.isAfter(DateTime.now())) {
      showTaskSnack(context, 'Pick a time in the future.', error: true);
      return;
    }
    setState(() {
      _due = _Due.custom;
      _dueAt = at;
    });
  }

  Future<void> _pickPerson() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<TaskPerson>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: kTaskWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _PeopleSheet(selectedKey: _assignee?.key),
    );
    if (picked != null && mounted) setState(() => _assignee = picked);
  }

  Future<void> _send() async {
    if (!_ready || _sending) return;
    // A deadline chosen a while ago ("in 2 hours") may have slipped; the server
    // would reject it, so say so here in plain words instead.
    if (_dueAt != null && !_dueAt!.isAfter(DateTime.now())) {
      showTaskSnack(
        context,
        'That deadline has passed. Pick a new one.',
        error: true,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      final task = await ref
          .read(teamTasksNotifierProvider.notifier)
          .create(
            NewTaskDraft(
              title: _title.text.trim(),
              description: _details.text,
              assigneeKey: _assignee!.key,
              priority: _priority,
              courtId: _courtId,
              dueAt: _dueAt,
              proofRequired: _proof,
            ),
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(task);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showTaskSnack(context, taskErrorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final courts = ref
        .watch(_taskCourtsProvider)
        .maybeWhen(data: (c) => c, orElse: () => const <Court>[]);
    final inset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: kTaskWhite,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: kTaskBlack),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'New task',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: kTaskBlack,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  TextField(
                    key: const Key('assign-title'),
                    controller: _title,
                    maxLength: 120,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    cursorColor: kTaskBlack,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: kTaskBlack,
                    ),
                    decoration: InputDecoration(
                      hintText: 'What needs to be done?',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFBDBDBD),
                      ),
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('assign-details'),
                    controller: _details,
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: kTaskBlack,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      height: 1.45,
                      color: kTaskBlack,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Add details (optional)',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14.5,
                        color: kTaskGrey,
                      ),
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: kTaskLine),

                  const _Label('Assign to'),
                  // The chosen person fades in over the placeholder.
                  AnimatedSwitcher(
                    duration: Motion.base,
                    switchInCurve: Motion.enter,
                    switchOutCurve: Motion.enter,
                    child: _PersonTile(
                      key: ValueKey(_assignee?.key ?? 'nobody'),
                      person: _assignee,
                      onTap: _pickPerson,
                    ),
                  ),

                  const _Label('Deadline'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Choice(
                        label: 'No deadline',
                        selected: _due == _Due.none,
                        onTap: () => _setDue(_Due.none),
                      ),
                      _Choice(
                        label: 'In 2 hours',
                        selected: _due == _Due.twoHours,
                        onTap: () => _setDue(_Due.twoHours),
                      ),
                      if (_todayAvailable)
                        _Choice(
                          label: 'Today 6 PM',
                          selected: _due == _Due.today,
                          onTap: () => _setDue(_Due.today),
                        ),
                      _Choice(
                        label: 'Tomorrow 10 AM',
                        selected: _due == _Due.tomorrow,
                        onTap: () => _setDue(_Due.tomorrow),
                      ),
                      _Choice(
                        key: const Key('assign-due-custom'),
                        icon: Icons.event_rounded,
                        label: _due == _Due.custom && _dueAt != null
                            ? taskDayTime(_dueAt!)
                            : 'Pick date & time',
                        selected: _due == _Due.custom,
                        onTap: _pickCustom,
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: Motion.quick,
                    curve: Motion.inOut,
                    alignment: Alignment.topLeft,
                    child: _dueAt != null && _due != _Due.custom
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Due ${taskDayTime(_dueAt!)}',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: kTaskGrey,
                              ),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),

                  const _Label('Priority'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in TaskPriority.values)
                        _Choice(
                          label: priorityLabel(p),
                          selected: _priority == p,
                          accent:
                              p == TaskPriority.urgent || p == TaskPriority.high
                              ? priorityColor(p)
                              : kTaskBlack,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _priority = p);
                          },
                        ),
                    ],
                  ),

                  if (courts.isNotEmpty) ...[
                    const _Label('Zone', hint: 'optional'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in courts)
                          _Choice(
                            icon: Icons.place_outlined,
                            label: c.name,
                            selected: _courtId == c.id,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(
                                () => _courtId = _courtId == c.id ? null : c.id,
                              );
                            },
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),
                  _ProofSwitch(
                    value: _proof,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _proof = v);
                    },
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(20, 12, 20, inset + 14),
              decoration: const BoxDecoration(
                color: kTaskWhite,
                border: Border(top: BorderSide(color: kTaskLine)),
              ),
              child: TaskPrimaryButton(
                key: const Key('assign-send'),
                label: _assignee == null
                    ? 'Assign task'
                    : 'Assign to ${_assignee!.firstName}',
                busy: _sending,
                busyLabel: 'Sending…',
                icon: Icons.send_rounded,
                onPressed: _ready ? _send : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: kTaskBlack,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(
              hint!,
              style: GoogleFonts.inter(fontSize: 12, color: kTaskGrey),
            ),
          ],
        ],
      ),
    );
  }
}

/// A selectable pill. Selected = filled with [accent].
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accent = kTaskBlack,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? kTaskWhite : kTaskBlack;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent : kTaskWhite,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? accent : kTaskLine,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({super.key, required this.person, required this.onTap});

  final TaskPerson? person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = person;
    return Material(
      color: kTaskSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('assign-person'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              if (p == null)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kTaskWhite,
                    shape: BoxShape.circle,
                    border: Border.all(color: kTaskLine, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 18,
                    color: kTaskGrey,
                  ),
                )
              else
                TaskAvatar(person: p, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p?.name ?? 'Choose a person',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p == null ? kTaskGrey : kTaskBlack,
                      ),
                    ),
                    if (p != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          p.roleLabel,
                          if (p.zone != null) p.zone!,
                        ].where((s) => s.isNotEmpty).join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: kTaskGrey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                p == null ? '' : 'Change',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: kTaskGrey,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kTaskGrey),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProofSwitch extends StatelessWidget {
  const _ProofSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: kTaskSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.inOut,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: value ? kTaskBlack : kTaskWhite,
              shape: BoxShape.circle,
              border: Border.all(
                color: value ? kTaskBlack : kTaskLine,
                width: 1.5,
              ),
            ),
            child: Icon(
              value
                  ? Icons.photo_camera_rounded
                  : Icons.no_photography_outlined,
              size: 18,
              color: value ? kTaskWhite : kTaskGrey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Photo proof required',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: kTaskBlack,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: Motion.quick,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    value
                        ? 'They must attach a photo to mark it done.'
                        : 'They can mark it done without a photo.',
                    key: ValueKey(value),
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.35,
                      color: kTaskGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: const Key('assign-proof'),
            value: value,
            onChanged: onChanged,
            activeThumbColor: kTaskWhite,
            activeTrackColor: kTaskBlack,
            inactiveThumbColor: kTaskWhite,
            inactiveTrackColor: const Color(0xFFCFCFCF),
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ],
      ),
    );
  }
}

/// Search + pick one person, grouped by team.
class _PeopleSheet extends ConsumerStatefulWidget {
  const _PeopleSheet({this.selectedKey});

  final String? selectedKey;

  @override
  ConsumerState<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends ConsumerState<_PeopleSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(taskPeopleProvider);
    final media = MediaQuery.of(context);

    return Padding(
      // Lift the sheet above the keyboard while searching.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kTaskLine,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Assign to',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kTaskBlack,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                key: const Key('people-search'),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                cursorColor: kTaskBlack,
                textInputAction: TextInputAction.search,
                style: GoogleFonts.inter(fontSize: 14.5, color: kTaskBlack),
                decoration: InputDecoration(
                  hintText: 'Search by name or team',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14.5,
                    color: kTaskGrey,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: kTaskGrey,
                  ),
                  filled: true,
                  fillColor: kTaskSoft,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
            ),
            const SizedBox(height: 6),
            Expanded(
              child: people.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kTaskBlack,
                    ),
                  ),
                ),
                error: (e, _) => Center(
                  child: TaskMessage(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load the team",
                    subtitle: taskErrorMessage(e),
                    action: TextButton(
                      onPressed: () => ref.invalidate(taskPeopleProvider),
                      child: Text(
                        'Try again',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: kTaskBlack,
                        ),
                      ),
                    ),
                  ),
                ),
                data: (all) => _list(all),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<TaskPerson> all) {
    final shown = _query.isEmpty
        ? all
        : all
              .where(
                (p) =>
                    p.name.toLowerCase().contains(_query) ||
                    p.roleLabel.toLowerCase().contains(_query) ||
                    (p.zone ?? '').toLowerCase().contains(_query),
              )
              .toList();

    if (shown.isEmpty) {
      return Center(
        child: TaskMessage(
          icon: Icons.person_search_rounded,
          title: all.isEmpty ? 'No one to assign to yet' : 'No match',
          subtitle: all.isEmpty
              ? 'Team members will appear here once they have an account.'
              : 'Try a different name or team.',
        ),
      );
    }

    // The server already sorts by team (heads first) then name; group in that
    // order so each team appears once, under its own heading.
    final rows = <Widget>[];
    String? team;
    for (final p in shown) {
      if (p.roleLabel != team) {
        team = p.roleLabel;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(
              team.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: kTaskGrey,
              ),
            ),
          ),
        );
      }
      final on = p.key == widget.selectedKey;
      rows.add(
        StaggerIn(
          index: rows.length,
          child: InkWell(
            key: Key('person-${p.key}'),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(p);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  TaskAvatar(person: p, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kTaskBlack,
                          ),
                        ),
                        if (p.zone != null && p.zone!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            p.zone!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: kTaskGrey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (on)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: kTaskBlack,
                      size: 22,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      children: rows,
    );
  }
}
