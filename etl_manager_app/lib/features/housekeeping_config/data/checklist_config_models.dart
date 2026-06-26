// Mutable draft models for the per-court housekeeping checklist builder.
import 'package:flutter/material.dart';

// ─── Icon registry ────────────────────────────────────────────────────────────
// Backend stores an icon *name* string; we map it to an IconData here. The
// picker offers this same set.
const Map<String, IconData> kHkIcons = {
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

IconData hkIcon(String? name) =>
    kHkIcons[name] ?? Icons.task_alt_rounded;

// ─── Draft models (editable in the builder) ─────────────────────────────────

class TaskDraft {
  String key; // '' for new — backend generates a stable key on save
  String title;
  String icon;
  int? intervalDays; // weekly/monthly only

  TaskDraft({
    this.key = '',
    required this.title,
    this.icon = 'cleaning_services',
    this.intervalDays,
  });

  TaskDraft copy() => TaskDraft(
        key: '', // copies become NEW tasks (own history)
        title: title,
        icon: icon,
        intervalDays: intervalDays,
      );

  factory TaskDraft.fromJson(Map<String, dynamic> j) => TaskDraft(
        key: (j['key'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        icon: (j['icon'] ?? 'cleaning_services') as String,
        intervalDays: j['interval_days'] as int?,
      );

  Map<String, dynamic> toJson() => {
        if (key.isNotEmpty) 'key': key,
        'title': title,
        'icon': icon,
        if (intervalDays != null) 'interval_days': intervalDays,
      };
}

class ShiftDraft {
  String key;
  String name;
  String? start; // "HH:MM" 24h
  String? end;
  List<TaskDraft> tasks;

  ShiftDraft({
    this.key = '',
    required this.name,
    this.start,
    this.end,
    List<TaskDraft>? tasks,
  }) : tasks = tasks ?? [];

  factory ShiftDraft.fromJson(Map<String, dynamic> j) => ShiftDraft(
        key: (j['key'] ?? '') as String,
        name: (j['name'] ?? 'Shift') as String,
        start: j['start_time'] as String?,
        end: j['end_time'] as String?,
        tasks: (j['tasks'] as List? ?? [])
            .map((t) => TaskDraft.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        if (key.isNotEmpty) 'key': key,
        'name': name,
        'start_time': start,
        'end_time': end,
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };
}

class ChecklistDraft {
  List<ShiftDraft> shifts;
  List<TaskDraft> weekly;
  List<TaskDraft> monthly;

  ChecklistDraft({
    required this.shifts,
    required this.weekly,
    required this.monthly,
  });

  factory ChecklistDraft.fromJson(Map<String, dynamic> j) => ChecklistDraft(
        shifts: (j['shifts'] as List? ?? [])
            .map((s) => ShiftDraft.fromJson(s as Map<String, dynamic>))
            .toList(),
        weekly: (j['weekly'] as List? ?? [])
            .map((t) => TaskDraft.fromJson(t as Map<String, dynamic>))
            .toList(),
        monthly: (j['monthly'] as List? ?? [])
            .map((t) => TaskDraft.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'shifts': shifts.map((s) => s.toJson()).toList(),
        'weekly': weekly.map((t) => t.toJson()).toList(),
        'monthly': monthly.map((t) => t.toJson()).toList(),
      };

  int get totalTasks =>
      shifts.fold<int>(0, (a, s) => a + s.tasks.length) +
      weekly.length +
      monthly.length;
}
