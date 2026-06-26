// lib/features/staff/domain/housekeeping_models.dart
//
// Config-driven housekeeping models (Phase 3b).
//
// A court's checklist is no longer hardcoded (morning/day/night + fixed tasks).
// Every shift, its timings, its tasks, and the weekly/monthly recurring tasks
// are defined per-court by the manager in the checklist builder and returned by
// the backend (GET /housekeeping/status & /housekeeping/config). These models
// parse that dynamic config + completion status.

import 'package:flutter/material.dart';

// ─── Icon registry ─────────────────────────────────────────────────────────
// Backend stores an icon *name* string (chosen in the builder). We map it to a
// Material IconData here. Mirrors kHkIcons in the checklist builder.

const Map<String, IconData> kHkIconMap = {
  'cleaning_services': Icons.cleaning_services_rounded,
  'chair': Icons.chair_rounded,
  'delete_forever': Icons.delete_forever_rounded,
  'restaurant': Icons.restaurant_rounded,
  'delete_outline': Icons.delete_outline_rounded,
  'pest_control': Icons.pest_control_rounded,
  'flag': Icons.flag_rounded,
  'fire_extinguisher': Icons.fire_extinguisher_rounded,
  'water_drop': Icons.water_drop_rounded,
  'soap': Icons.soap_rounded,
  'wash': Icons.wash_rounded,
  'sanitizer': Icons.sanitizer_rounded,
  'kitchen': Icons.kitchen_rounded,
  'countertops': Icons.countertops_rounded,
  'window': Icons.window_rounded,
  'light': Icons.light_rounded,
  'ac_unit': Icons.ac_unit_rounded,
  'checklist': Icons.checklist_rounded,
  'inventory': Icons.inventory_2_rounded,
  'plumbing': Icons.plumbing_rounded,
};

IconData hkIconFor(String? name) => kHkIconMap[name] ?? Icons.task_alt_rounded;

// ─── Accent palette (per-task colour, derived from icon) ─────────────────────

const Color hkAccentBlue = Color(0xFF60A5FA);
const Color hkAccentWarn = Color(0xFFE5A000);
const Color hkAccentPurple = Color(0xFFA78BFA);
const Color hkAccentDanger = Color(0xFFFF4444);
const Color hkAccentGreen = Color(0xFF22C55E);

const Map<String, Color> _hkColorMap = {
  'pest_control': hkAccentWarn,
  'delete_outline': hkAccentWarn,
  'delete_forever': hkAccentBlue,
  'flag': hkAccentPurple,
  'water_drop': hkAccentPurple,
  'wash': hkAccentPurple,
  'soap': hkAccentPurple,
  'sanitizer': hkAccentPurple,
  'fire_extinguisher': hkAccentDanger,
  'ac_unit': hkAccentBlue,
};

Color hkAccentFor(String? icon, {Color fallback = hkAccentBlue}) =>
    _hkColorMap[icon] ?? fallback;

// ─── Task kinds ──────────────────────────────────────────────────────────────

enum HkTaskKind { daily, weekly, monthly }

// Legacy fallback — used only as a display default when a shift reports 0 tasks.
const int kTasksPerShift = 6;

// ─── Time helpers (configured "HH:MM" timings) ───────────────────────────────

int? hkHhmmToMin(String? s) {
  if (s == null) return null;
  final parts = s.trim().split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return (h % 24) * 60 + (m % 60);
}

/// Is a shift active *right now* given its configured start/end ("HH:MM")?
/// Handles overnight shifts (end < start). Missing timings → always active.
bool hkShiftActiveNow(String? start, String? end, [DateTime? nowOverride]) {
  final now = nowOverride ?? DateTime.now();
  final cur = now.hour * 60 + now.minute;
  final s = hkHhmmToMin(start);
  final e = hkHhmmToMin(end);
  if (s == null || e == null) return true;
  if (s == e) return true; // 24h shift
  if (s < e) return cur >= s && cur < e;
  return cur >= s || cur < e; // overnight
}

/// "06:00" → "6:00 AM". Falls back to the raw string / "--".
String hkFmt12(String? hhmm) {
  final m = hkHhmmToMin(hhmm);
  if (m == null) return hhmm ?? '--';
  final h24 = m ~/ 60;
  final min = m % 60;
  final ampm = h24 < 12 ? 'AM' : 'PM';
  var h12 = h24 % 12;
  if (h12 == 0) h12 = 12;
  return '$h12:${min.toString().padLeft(2, '0')} $ampm';
}

String hkRange12(String? start, String? end) {
  if (start == null && end == null) return 'Any time';
  return '${hkFmt12(start)} – ${hkFmt12(end)}';
}

/// A sensible icon for a shift based on its start hour.
IconData hkShiftIcon(String? start) {
  final m = hkHhmmToMin(start);
  if (m == null) return Icons.schedule_rounded;
  final h = m ~/ 60;
  if (h >= 5 && h < 12) return Icons.wb_sunny_rounded;
  if (h >= 12 && h < 17) return Icons.light_mode_rounded;
  if (h >= 17 && h < 21) return Icons.wb_twilight_rounded;
  return Icons.nights_stay_rounded;
}

// ─── Submit request models ────────────────────────────────────────────────────

class TaskSubmitItem {
  final String taskId;
  final String taskTitle;
  final bool isDone;
  final String? photoUrl;
  final DateTime? doneAt;

  const TaskSubmitItem({
    required this.taskId,
    required this.taskTitle,
    required this.isDone,
    this.photoUrl,
    this.doneAt,
  });

  Map<String, dynamic> toJson() => {
    'task_id': taskId,
    'task_title': taskTitle,
    'is_done': isDone,
    'photo_url': photoUrl,
    'done_at': doneAt?.toIso8601String(),
  };
}

class ShiftSubmitRequest {
  final int courtId;
  final String shiftKey; // stable config key (was the Shift enum)
  final String date;
  final List<TaskSubmitItem> tasks;
  final int? submittedBy;

  const ShiftSubmitRequest({
    required this.courtId,
    required this.shiftKey,
    required this.date,
    required this.tasks,
    this.submittedBy,
  });

  Map<String, dynamic> toJson() => {
    'court_id': courtId,
    'shift': shiftKey,
    'date': date,
    'tasks': tasks.map((t) => t.toJson()).toList(),
    'submitted_by': submittedBy,
  };
}

// ─── API response models ──────────────────────────────────────────────────────

class TaskStatusItem {
  final String taskId;
  final String taskTitle;
  final String? icon; // icon name from config
  final bool isDone;
  final String? photoUrl;
  final DateTime? doneAt;
  final String? doneByName;

  const TaskStatusItem({
    required this.taskId,
    required this.taskTitle,
    this.icon,
    required this.isDone,
    this.photoUrl,
    this.doneAt,
    this.doneByName,
  });

  factory TaskStatusItem.fromJson(Map<String, dynamic> j) => TaskStatusItem(
    taskId: j['task_id'] as String? ?? '',
    taskTitle: j['task_title'] as String? ?? '',
    icon: j['icon'] as String?,
    isDone: j['is_done'] as bool? ?? false,
    photoUrl: j['photo_url'] as String?,
    doneByName: j['done_by_name'] as String?,
    doneAt: j['done_at'] != null
        ? DateTime.tryParse(j['done_at'] as String)
        : null,
  );
}

class ShiftStatus {
  final String shiftKey; // stable config key
  final String shiftName; // display name
  final String? startTime; // "HH:MM"
  final String? endTime; // "HH:MM"
  final int total;
  final int done;
  final bool submitted;
  final List<TaskStatusItem> tasks;

  const ShiftStatus({
    required this.shiftKey,
    required this.shiftName,
    this.startTime,
    this.endTime,
    required this.total,
    required this.done,
    required this.submitted,
    required this.tasks,
  });

  double get pct => total == 0 ? 0.0 : done / total;

  bool get isActiveNow => hkShiftActiveNow(startTime, endTime);

  String get timeRange => hkRange12(startTime, endTime);

  factory ShiftStatus.fromJson(Map<String, dynamic> j) {
    final key = j['shift'] as String? ?? '';
    return ShiftStatus(
      shiftKey: key,
      shiftName: (j['shift_name'] as String?) ?? key,
      startTime: j['start_time'] as String?,
      endTime: j['end_time'] as String?,
      total: j['total'] as int? ?? 0,
      done: j['done'] as int? ?? 0,
      submitted: j['submitted'] as bool? ?? false,
      tasks: (j['tasks'] as List? ?? [])
          .map((t) => TaskStatusItem.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CourtDayStatus {
  final int courtId;
  final String courtName;
  final String date;
  final List<ShiftStatus> shifts;

  const CourtDayStatus({
    required this.courtId,
    this.courtName = '',
    required this.date,
    required this.shifts,
  });

  factory CourtDayStatus.fromJson(Map<String, dynamic> j) => CourtDayStatus(
    courtId: j['court_id'] as int? ?? 0,
    courtName: j['court_name'] as String? ?? '',
    date: j['date'] as String? ?? '',
    shifts: (j['shifts'] as List? ?? [])
        .map((s) => ShiftStatus.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

// ─── Recurring (weekly / monthly) task status ────────────────────────────────
// Unified model — weekly and monthly have an identical shape, differing only by
// interval_days (configurable per court).

class RecurringTaskStatus {
  final int courtId;
  final String taskId;
  final String title;
  final String? icon;
  final int intervalDays;
  final DateTime? lastDoneAt;
  final DateTime? nextDueAt;
  final String? photoUrl;
  final String? doneByName;
  final bool isOverdue;

  const RecurringTaskStatus({
    required this.courtId,
    this.taskId = '',
    this.title = '',
    this.icon,
    this.intervalDays = 7,
    this.lastDoneAt,
    this.nextDueAt,
    this.photoUrl,
    this.doneByName,
    required this.isOverdue,
  });

  bool get isCooldownActive =>
      nextDueAt != null && DateTime.now().isBefore(nextDueAt!);

  int get remainingDays {
    if (nextDueAt == null) return 0;
    final diff = nextDueAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inDays + (diff.inHours.remainder(24) > 0 ? 1 : 0);
  }

  factory RecurringTaskStatus.fromJson(
    Map<String, dynamic> j, {
    int defaultInterval = 7,
  }) => RecurringTaskStatus(
    courtId: j['court_id'] as int? ?? 0,
    taskId: j['task_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    icon: j['icon'] as String?,
    intervalDays: j['interval_days'] as int? ?? defaultInterval,
    lastDoneAt: j['last_done_at'] != null
        ? DateTime.tryParse(j['last_done_at'] as String)
        : null,
    nextDueAt: j['next_due_at'] != null
        ? DateTime.tryParse(j['next_due_at'] as String)
        : null,
    photoUrl: j['photo_url'] as String?,
    doneByName: j['done_by_name'] as String?,
    isOverdue: j['is_overdue'] as bool? ?? false,
  );

  RecurringTaskStatus copyWith({
    DateTime? lastDoneAt,
    DateTime? nextDueAt,
    String? photoUrl,
    String? doneByName,
    bool? isOverdue,
  }) => RecurringTaskStatus(
    courtId: courtId,
    taskId: taskId,
    title: title,
    icon: icon,
    intervalDays: intervalDays,
    lastDoneAt: lastDoneAt ?? this.lastDoneAt,
    nextDueAt: nextDueAt ?? this.nextDueAt,
    photoUrl: photoUrl ?? this.photoUrl,
    doneByName: doneByName ?? this.doneByName,
    isOverdue: isOverdue ?? this.isOverdue,
  );
}

// ─── Full status response ─────────────────────────────────────────────────────

class FullStatusResponse {
  final String date;
  final List<CourtDayStatus> courts;
  final List<RecurringTaskStatus> weeklyTasks;
  final List<RecurringTaskStatus> monthlyTasks;

  const FullStatusResponse({
    required this.date,
    required this.courts,
    required this.weeklyTasks,
    required this.monthlyTasks,
  });

  factory FullStatusResponse.fromJson(Map<String, dynamic> j) =>
      FullStatusResponse(
        date: j['date'] as String? ?? '',
        courts: (j['courts'] as List? ?? [])
            .map((c) => CourtDayStatus.fromJson(c as Map<String, dynamic>))
            .toList(),
        weeklyTasks: (j['weekly_tasks'] as List? ?? [])
            .map((w) => RecurringTaskStatus.fromJson(
                  w as Map<String, dynamic>,
                  defaultInterval: 7,
                ))
            .toList(),
        monthlyTasks: (j['monthly_tasks'] as List? ?? [])
            .map((m) => RecurringTaskStatus.fromJson(
                  m as Map<String, dynamic>,
                  defaultInterval: 30,
                ))
            .toList(),
      );

  CourtDayStatus? courtById(int courtId) {
    for (final c in courts) {
      if (c.courtId == courtId) return c;
    }
    return null;
  }

  List<RecurringTaskStatus> weeklyFor(int courtId) =>
      weeklyTasks.where((w) => w.courtId == courtId).toList();

  List<RecurringTaskStatus> monthlyFor(int courtId) =>
      monthlyTasks.where((m) => m.courtId == courtId).toList();
}
