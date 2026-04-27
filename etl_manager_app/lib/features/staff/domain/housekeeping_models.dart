// lib/features/staff/domain/housekeeping_models.dart
// Single source of truth for ALL housekeeping types.

import 'package:flutter/material.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum Shift { morning, day, night }

enum TaskCat { cleaning, pest, laundry, audit }

enum TaskFreq { daily, weekly, monthly }

enum TaskSt { pending, done, overdue }

// ─── UI Task Definition ───────────────────────────────────────────────────────

class HkTask {
  final String id;
  final String title;
  final TaskCat category;
  final IconData icon;
  final TaskFreq frequency;

  const HkTask({
    required this.id,
    required this.title,
    required this.category,
    required this.icon,
    this.frequency = TaskFreq.daily,
  });
}

// ─── UI Display Record ────────────────────────────────────────────────────────

class CourtTaskRecord {
  final HkTask task;
  final TaskSt status;
  final String? doneBy;
  final DateTime? doneAt;
  final bool hasPhoto;
  final String? photoUrl;

  const CourtTaskRecord({
    required this.task,
    required this.status,
    this.doneBy,
    this.doneAt,
    this.hasPhoto = false,
    this.photoUrl,
  });
}

// ─── Task Definitions ─────────────────────────────────────────────────────────

const kDailyTasks = [
  HkTask(
    id: 'floorclean',
    title: 'Floor Cleaning',
    category: TaskCat.cleaning,
    icon: Icons.cleaning_services_rounded,
  ),
  HkTask(
    id: 'tablechairclean',
    title: 'Table & Chair Clean',
    category: TaskCat.cleaning,
    icon: Icons.chair_rounded,
  ),
  HkTask(
    id: 'binclean',
    title: 'Bins Cleaning (outside)',
    category: TaskCat.cleaning,
    icon: Icons.delete_forever_rounded,
  ),
  HkTask(
    id: 'trayclean',
    title: 'Tray Cleaning',
    category: TaskCat.cleaning,
    icon: Icons.restaurant_rounded,
  ),
  HkTask(
    id: 'binempty',
    title: 'Garbage Bin Empty',
    category: TaskCat.cleaning,
    icon: Icons.delete_outline_rounded,
  ),
  HkTask(
    id: 'pestspray',
    title: 'Pest Spray',
    category: TaskCat.pest,
    icon: Icons.pest_control_rounded,
  ),
];

const kFlags = HkTask(
  id: 'flagswash',
  title: 'Flags Washing',
  category: TaskCat.laundry,
  icon: Icons.flag_rounded,
  frequency: TaskFreq.weekly,
);
const kFire = HkTask(
  id: 'fireaudit',
  title: 'Fire Safety Audit',
  category: TaskCat.audit,
  icon: Icons.fire_extinguisher_rounded,
  frequency: TaskFreq.monthly,
);

// ─── Color Helpers ────────────────────────────────────────────────────────────

Color catColor(TaskCat c) => switch (c) {
  TaskCat.cleaning => const Color(0xFF60A5FA),
  TaskCat.pest => const Color(0xFFE5A000),
  TaskCat.laundry => const Color(0xFFA855F7),
  TaskCat.audit => const Color(0xFFFF4444),
};

Color stColor(TaskSt s) => switch (s) {
  TaskSt.done => const Color(0xFF22C55E),
  TaskSt.pending => const Color(0xFFE5A000),
  TaskSt.overdue => const Color(0xFFFF4444),
};

String stLabel(TaskSt s) => switch (s) {
  TaskSt.done => 'Done',
  TaskSt.pending => 'Pending',
  TaskSt.overdue => 'Overdue',
};

// ─── Submit Request Models ────────────────────────────────────────────────────

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
  final Shift shift;
  final String date;
  final List<TaskSubmitItem> tasks;
  final int? submittedBy;

  const ShiftSubmitRequest({
    required this.courtId,
    required this.shift,
    required this.date,
    required this.tasks,
    this.submittedBy,
  });

  Map<String, dynamic> toJson() => {
    'court_id': courtId,
    'shift': shift.name,
    'date': date,
    'tasks': tasks.map((t) => t.toJson()).toList(),
    'submitted_by': submittedBy,
  };
}

// ─── API Response Models ──────────────────────────────────────────────────────

class TaskStatusItem {
  final String taskId;
  final String taskTitle;
  final bool isDone;
  final String? photoUrl;
  final DateTime? doneAt;

  const TaskStatusItem({
    required this.taskId,
    required this.taskTitle,
    required this.isDone,
    this.photoUrl,
    this.doneAt,
  });

  factory TaskStatusItem.fromJson(Map<String, dynamic> j) => TaskStatusItem(
    taskId: j['task_id'],
    taskTitle: j['task_title'],
    isDone: j['is_done'],
    photoUrl: j['photo_url'],
    doneAt: j['done_at'] != null ? DateTime.parse(j['done_at']) : null,
  );
}

class ShiftStatus {
  final Shift shift;
  final int total;
  final int done;
  final bool submitted;
  final List<TaskStatusItem> tasks;

  const ShiftStatus({
    required this.shift,
    required this.total,
    required this.done,
    required this.submitted,
    required this.tasks,
  });

  factory ShiftStatus.fromJson(Map<String, dynamic> j) => ShiftStatus(
    shift: Shift.values.firstWhere((s) => s.name == j['shift']),
    total: j['total'],
    done: j['done'],
    submitted: j['submitted'],
    tasks: (j['tasks'] as List).map((t) => TaskStatusItem.fromJson(t)).toList(),
  );
}

class CourtDayStatus {
  final int courtId;
  final String date;
  final List<ShiftStatus> shifts;

  const CourtDayStatus({
    required this.courtId,
    required this.date,
    required this.shifts,
  });

  factory CourtDayStatus.fromJson(Map<String, dynamic> j) => CourtDayStatus(
    courtId: j['court_id'],
    date: j['date'],
    shifts: (j['shifts'] as List).map((s) => ShiftStatus.fromJson(s)).toList(),
  );
}

class WeeklyTaskStatus {
  final int courtId;
  final DateTime? lastDoneAt;
  final DateTime? nextDueAt;
  final String? photoUrl;
  final bool isOverdue;

  const WeeklyTaskStatus({
    required this.courtId,
    this.lastDoneAt,
    this.nextDueAt,
    this.photoUrl,
    required this.isOverdue,
  });

  factory WeeklyTaskStatus.fromJson(Map<String, dynamic> j) => WeeklyTaskStatus(
    courtId: j['court_id'],
    lastDoneAt: j['last_done_at'] != null
        ? DateTime.parse(j['last_done_at'])
        : null,
    nextDueAt: j['next_due_at'] != null
        ? DateTime.parse(j['next_due_at'])
        : null,
    photoUrl: j['photo_url'],
    isOverdue: j['is_overdue'],
  );
}

class MonthlyTaskStatus {
  final int courtId;
  final DateTime? lastDoneAt;
  final DateTime? nextDueAt;
  final String? photoUrl;
  final bool isOverdue;

  const MonthlyTaskStatus({
    required this.courtId,
    this.lastDoneAt,
    this.nextDueAt,
    this.photoUrl,
    required this.isOverdue,
  });

  factory MonthlyTaskStatus.fromJson(Map<String, dynamic> j) =>
      MonthlyTaskStatus(
        courtId: j['court_id'],
        lastDoneAt: j['last_done_at'] != null
            ? DateTime.parse(j['last_done_at'])
            : null,
        nextDueAt: j['next_due_at'] != null
            ? DateTime.parse(j['next_due_at'])
            : null,
        photoUrl: j['photo_url'],
        isOverdue: j['is_overdue'],
      );
}

class FullStatusResponse {
  final String date;
  final List<CourtDayStatus> courts;
  final List<WeeklyTaskStatus> weeklyTasks;
  final List<MonthlyTaskStatus> monthlyTasks;

  const FullStatusResponse({
    required this.date,
    required this.courts,
    required this.weeklyTasks,
    required this.monthlyTasks,
  });

  factory FullStatusResponse.fromJson(Map<String, dynamic> j) =>
      FullStatusResponse(
        date: j['date'],
        courts: (j['courts'] as List)
            .map((c) => CourtDayStatus.fromJson(c))
            .toList(),
        weeklyTasks: (j['weekly_tasks'] as List)
            .map((w) => WeeklyTaskStatus.fromJson(w))
            .toList(),
        monthlyTasks: (j['monthly_tasks'] as List)
            .map((m) => MonthlyTaskStatus.fromJson(m))
            .toList(),
      );
}
