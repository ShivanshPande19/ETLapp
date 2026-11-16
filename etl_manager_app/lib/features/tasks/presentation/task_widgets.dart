// lib/features/tasks/presentation/task_widgets.dart
//
// The small shared pieces of the Tasks screens: palette, time formatting,
// avatar, chips, the list card and the snackbar. Kept in one file so the list,
// the detail screen and the assign screen all speak the same visual language.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/ui/motion.dart';
import '../data/team_task_models.dart';

// ─── Palette (matches the notices / checklist screens) ───────────────────────
const kTaskBg = Color(0xFF080808);
const kTaskWhite = Color(0xFFFFFFFF);
const kTaskBlack = Color(0xFF0A0A0A);
const kTaskGrey = Color(0xFF888888);
const kTaskLine = Color(0xFFE5E5E5);
const kTaskSoft = Color(0xFFF5F5F5);
const kTaskRed = Color(0xFFD02128);
const kTaskGreen = Color(0xFF16A34A);
const kTaskAmber = Color(0xFFD97706);

// ─── Time ────────────────────────────────────────────────────────────────────

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "5:30 PM"
String taskClock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Today, 5:30 PM" · "Tomorrow, 10:00 AM" · "16 Nov, 5:30 PM"
String taskDayTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = DateTime(
    t.year,
    t.month,
    t.day,
  ).difference(DateTime(n.year, n.month, n.day)).inDays;
  final String day;
  if (days == 0) {
    day = 'Today';
  } else if (days == 1) {
    day = 'Tomorrow';
  } else if (days == -1) {
    day = 'Yesterday';
  } else {
    day =
        '${t.day} ${_months[t.month - 1]}'
        '${t.year == n.year ? '' : ' ${t.year}'}';
  }
  return '$day, ${taskClock(t)}';
}

/// "Just now" · "12m ago" · "3h ago" · "2d ago" · "16 Nov"
String taskAgo(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day} ${_months[t.month - 1]}';
}

// ─── Labels and colours ──────────────────────────────────────────────────────

String priorityLabel(TaskPriority p) {
  switch (p) {
    case TaskPriority.low:
      return 'Low';
    case TaskPriority.normal:
      return 'Normal';
    case TaskPriority.high:
      return 'High';
    case TaskPriority.urgent:
      return 'Urgent';
  }
}

Color priorityColor(TaskPriority p) {
  switch (p) {
    case TaskPriority.low:
      return kTaskGrey;
    case TaskPriority.normal:
      return kTaskBlack;
    case TaskPriority.high:
      return kTaskAmber;
    case TaskPriority.urgent:
      return kTaskRed;
  }
}

/// The one word that says where a task stands, for the signed-in user.
({String label, Color color, bool filled}) taskStatusStyle(TeamTask t) {
  switch (t.status) {
    case TaskStatus.done:
      return (label: 'Done', color: kTaskGreen, filled: true);
    case TaskStatus.cancelled:
      return (label: 'Cancelled', color: kTaskGrey, filled: false);
    case TaskStatus.inProgress:
      if (t.isOverdue) return (label: 'Overdue', color: kTaskRed, filled: true);
      return (label: 'In progress', color: kTaskBlack, filled: true);
    case TaskStatus.assigned:
      if (t.isOverdue) return (label: 'Overdue', color: kTaskRed, filled: true);
      if (t.reopenCount > 0) {
        return (label: 'Sent back', color: kTaskAmber, filled: false);
      }
      if (t.seenAt != null) {
        return (label: 'Seen', color: kTaskBlack, filled: false);
      }
      return (
        label: t.iAmAssignee ? 'New' : 'Sent',
        color: t.iAmAssignee ? kTaskRed : kTaskGrey,
        filled: false,
      );
  }
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class TaskAvatar extends StatelessWidget {
  const TaskAvatar({
    super.key,
    required this.person,
    this.size = 36,
    this.dark = false,
  });

  final TaskPerson person;
  final double size;

  /// On the dark header: light circle. On the white sheet: dark circle.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? kTaskWhite.withValues(alpha: 0.12) : kTaskBlack,
        shape: BoxShape.circle,
      ),
      child: Text(
        person.initials,
        style: GoogleFonts.inter(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: kTaskWhite,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class TaskStatusPill extends StatelessWidget {
  const TaskStatusPill({super.key, required this.task, this.onDark = false});

  final TeamTask task;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final s = taskStatusStyle(task);
    // On the dark header a black pill would vanish, so it inverts to white.
    final base = onDark && s.color == kTaskBlack ? kTaskWhite : s.color;
    final fg = s.filled ? (base == kTaskWhite ? kTaskBlack : kTaskWhite) : base;
    // The pill swaps with a soft scale + fade when the status changes (New →
    // Seen → In progress → Done), so the change is noticed, not missed.
    return AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.enter,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1).animate(anim),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(s.label),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: s.filled ? base : base.withValues(alpha: onDark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          s.label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: fg,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

/// A small icon + text chip used for the deadline, priority, proof and zone.
class TaskChip extends StatelessWidget {
  const TaskChip({
    super.key,
    required this.icon,
    required this.label,
    this.color = kTaskGrey,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final Color color;

  /// Tinted background, for the chips that need to be noticed.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: strong ? 8 : 0,
        vertical: strong ? 4 : 0,
      ),
      decoration: strong
          ? BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The deadline / priority / proof / zone chips of a task, in one wrap.
List<Widget> taskMetaChips(TeamTask t, {DateTime? now}) {
  final chips = <Widget>[];
  if (t.dueAt != null) {
    final late = t.isOverdue;
    chips.add(
      TaskChip(
        icon: late ? Icons.error_outline_rounded : Icons.schedule_rounded,
        label: '${late ? 'Was due' : 'Due'} ${taskDayTime(t.dueAt!, now: now)}',
        color: late ? kTaskRed : kTaskBlack,
        strong: late,
      ),
    );
  }
  if (t.priority == TaskPriority.urgent || t.priority == TaskPriority.high) {
    chips.add(
      TaskChip(
        icon: Icons.flag_rounded,
        label: priorityLabel(t.priority),
        color: priorityColor(t.priority),
        strong: true,
      ),
    );
  }
  if (t.proofRequired && t.isOpen) {
    chips.add(
      const TaskChip(icon: Icons.photo_camera_outlined, label: 'Photo proof'),
    );
  }
  if (t.status == TaskStatus.done && t.proofPhotos.isNotEmpty) {
    chips.add(
      TaskChip(
        icon: Icons.photo_library_outlined,
        label: t.proofPhotos.length == 1
            ? '1 photo'
            : '${t.proofPhotos.length} photos',
        color: kTaskGreen,
      ),
    );
  }
  if (t.courtName != null && t.courtName!.isNotEmpty) {
    chips.add(TaskChip(icon: Icons.place_outlined, label: t.courtName!));
  }
  return chips;
}

/// One task in the list.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.onTap});

  final TeamTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final other = t.counterpart;
    final finished = !t.isOpen;
    final stripe = t.isOverdue
        ? kTaskRed
        : finished
        ? kTaskLine
        : priorityColor(t.priority);
    final chips = taskMetaChips(t);

    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: kTaskWhite,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: t.isOverdue ? kTaskRed.withValues(alpha: 0.35) : kTaskLine,
              width: 1.5,
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: stripe),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                t.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                  color: finished ? kTaskGrey : kTaskBlack,
                                  decoration: t.status == TaskStatus.cancelled
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            TaskStatusPill(task: t),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            TaskAvatar(person: other, size: 26),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: t.iAmAssignee ? 'From ' : 'To ',
                                      style: const TextStyle(color: kTaskGrey),
                                    ),
                                    TextSpan(
                                      text: other.name,
                                      style: const TextStyle(
                                        color: kTaskBlack,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (other.roleLabel.isNotEmpty)
                                      TextSpan(
                                        text: '  ·  ${other.roleLabel}',
                                        style: const TextStyle(
                                          color: kTaskGrey,
                                        ),
                                      ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                        if (chips.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: chips,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A centred icon + title + line, used for the empty and failed states.
class TaskMessage extends StatelessWidget {
  const TaskMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: kTaskSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: kTaskGrey),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kTaskBlack,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.45,
              color: kTaskGrey,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// The app's primary button: black, full, rounded. Shows a spinner and stays
/// visibly in place while [busy].
class TaskPrimaryButton extends StatelessWidget {
  const TaskPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.icon,
    this.color = kTaskBlack,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String? busyLabel;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: kTaskWhite,
          // Explicit, so a disabled button dims instead of falling back to the
          // theme's near-invisible default.
          disabledBackgroundColor: busy
              ? color.withValues(alpha: 0.75)
              : kTaskLine,
          disabledForegroundColor: busy ? kTaskWhite : kTaskGrey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kTaskWhite,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 18),
            if (busy || icon != null) const SizedBox(width: 10),
            Flexible(
              child: Text(
                busy ? (busyLabel ?? label) : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 15,
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

void showTaskSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? kTaskRed : const Color(0xFF1C1C1C),
        duration: Duration(seconds: error ? 4 : 2),
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: kTaskWhite,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
}

/// The pill "Back" button used on the dark headers.
class TaskBackPill extends StatelessWidget {
  const TaskBackPill({super.key, required this.onTap, this.label = 'Back'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: kTaskWhite.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: kTaskWhite.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.west_rounded,
                size: 14,
                color: kTaskWhite.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kTaskWhite.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
