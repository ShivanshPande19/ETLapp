// lib/features/tasks/presentation/tasks_entry.dart
//
// The ways into Tasks from the home screens: a header icon with the number of
// tasks waiting on me, and a card for the management home. Both draw nothing
// for an account that takes no part in team tasks (ETL staff, outlet accounts).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/ui/motion.dart';
import '../../auth/domain/auth_notifier.dart';
import '../domain/team_tasks_notifier.dart';
import 'task_widgets.dart';

void _openTasks(BuildContext context) {
  HapticFeedback.selectionClick();
  context.push('/tasks');
}

/// Header icon. Sits next to the notices bell and matches it.
class TasksBell extends ConsumerWidget {
  const TasksBell({super.key, this.color = Colors.white, this.size = 38});

  /// Icon + ring tint. White over a dark header, black over a light one.
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(
      authNotifierProvider.select((s) => s.canUseTeamTasks),
    );
    if (!allowed) return const SizedBox.shrink();

    final waiting = ref.watch(
      teamTasksNotifierProvider.select((s) => s.summary.mineOpen),
    );
    final late = ref.watch(
      teamTasksNotifierProvider.select((s) => s.summary.mineOverdue),
    );
    final onDark = color.computeLuminance() > 0.5;

    return Semantics(
      button: true,
      label: waiting == 0 ? 'Tasks' : 'Tasks, $waiting waiting on you',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openTasks(context),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.18),
                  width: 1.2,
                ),
              ),
              child: Icon(
                Icons.assignment_turned_in_outlined,
                size: size * 0.5,
                color: color,
              ),
            ),
            if (waiting > 0)
              Positioned(
                right: -3,
                top: -3,
                // Pops when the number changes, so a new task is noticed.
                child: _CountPop(
                  value: waiting,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    decoration: BoxDecoration(
                      color: late > 0
                          ? kTaskRed
                          : (onDark ? kTaskWhite : kTaskBlack),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: onDark ? kTaskBg : kTaskWhite,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        waiting > 9 ? '9+' : '$waiting',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          height: 1.0,
                          fontWeight: FontWeight.w800,
                          color: late > 0
                              ? kTaskWhite
                              : (onDark ? kTaskBlack : kTaskWhite),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Replays a small "pop" whenever [value] changes.
class _CountPop extends StatelessWidget {
  const _CountPop({required this.value, required this.child});

  final int value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(value),
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: Motion.base,
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: child,
    );
  }
}

/// A card for the management home: what is waiting on me, at a glance.
class TasksHomeCard extends ConsumerWidget {
  const TasksHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(
      authNotifierProvider.select((s) => s.canUseTeamTasks),
    );
    if (!allowed) return const SizedBox.shrink();

    final st = ref.watch(teamTasksNotifierProvider);
    final s = st.summary;
    final late = s.mineOverdue > 0;

    // Two short lines rather than one long one, so nothing wraps mid-phrase
    // or gets cut off: what is waiting on me, then what I am waiting on.
    final String line;
    String? second;
    if (!st.summaryKnown) {
      line = st.loadFailed ? 'Tap to open your tasks' : 'Checking your tasks…';
    } else if (s.mineOpen == 0 && s.sentOpen == 0) {
      line = 'Nothing pending — give someone a task';
    } else {
      // Kept short enough to fit beside the count badge on a narrow phone.
      line = s.mineOpen == 0
          ? 'Nothing waiting on you'
          : s.mineOverdue > 0
          ? '${s.mineOpen} for you  ·  ${s.mineOverdue} overdue'
          : '${s.mineOpen} waiting on you';
      if (s.sentOpen > 0) second = '${s.sentOpen} pending from others';
    }

    return Semantics(
      button: true,
      label: 'Team tasks. $line${second == null ? '' : '. $second'}',
      child: Pressable(
        scale: 0.98,
        haptic: false, // _openTasks gives the haptic
        onTap: () => _openTasks(context),
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.inOut,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kTaskWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: late ? kTaskRed.withValues(alpha: 0.4) : kTaskLine,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: (late ? kTaskRed : kTaskBlack).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.assignment_turned_in_rounded,
                  color: late ? kTaskRed : kTaskBlack,
                  size: 23,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Team Tasks',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kTaskBlack,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: late ? FontWeight.w600 : FontWeight.w500,
                        color: late ? kTaskRed : kTaskGrey,
                      ),
                    ),
                    if (second != null)
                      Text(
                        second,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: kTaskGrey,
                        ),
                      ),
                  ],
                ),
              ),
              if (s.mineOpen > 0) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 26),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: late ? kTaskRed : kTaskBlack,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    s.mineOpen > 99 ? '99+' : '${s.mineOpen}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: kTaskWhite,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: kTaskGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
