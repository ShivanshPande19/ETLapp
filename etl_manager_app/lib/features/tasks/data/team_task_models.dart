// lib/features/tasks/data/team_task_models.dart
//
// Team tasks — one person gives a task to one other person.
//
// The server decides everything that matters: who may see a task, who may act
// on it, and whether it is overdue. These models only carry its answers; the
// `can*` flags in particular are never recomputed here.

enum TaskStatus { assigned, inProgress, done, cancelled }

enum TaskPriority { low, normal, high, urgent }

/// Which side of the task list is being viewed.
enum TaskBox {
  /// Tasks given TO me.
  mine,

  /// Tasks I gave to someone else.
  sent,
}

/// Which tasks of a box to show.
enum TaskFilter { open, done, all }

TaskStatus _status(String? s) {
  switch (s) {
    case 'IN_PROGRESS':
      return TaskStatus.inProgress;
    case 'DONE':
      return TaskStatus.done;
    case 'CANCELLED':
      return TaskStatus.cancelled;
    default:
      return TaskStatus.assigned;
  }
}

TaskPriority _priority(String? s) {
  switch (s) {
    case 'low':
      return TaskPriority.low;
    case 'high':
      return TaskPriority.high;
    case 'urgent':
      return TaskPriority.urgent;
    default:
      return TaskPriority.normal;
  }
}

/// The wire value for a priority.
String priorityValue(TaskPriority p) => p.name;

DateTime? _time(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  // The server always sends explicit UTC ("…Z"); show it in local time.
  return DateTime.tryParse(s)?.toLocal();
}

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const <String>[];

/// Someone on the internal team — either end of a task, or a directory entry.
class TaskPerson {
  /// `"manager:<id>"` or `"staff:<id>"`. Opaque here; only ever sent back.
  final String key;
  final String name;
  final String? role;
  final String roleLabel;

  /// Court name(s) for people tied to a zone; null for company-wide roles.
  final String? zone;

  const TaskPerson({
    required this.key,
    required this.name,
    this.role,
    this.roleLabel = '',
    this.zone,
  });

  factory TaskPerson.fromJson(Map<String, dynamic> j) => TaskPerson(
    key: (j['key'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    role: j['role']?.toString(),
    roleLabel: (j['role_label'] ?? '').toString(),
    zone: j['zone']?.toString(),
  );

  /// Up to two initials for the avatar.
  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String get firstName {
    final t = name.trim();
    if (t.isEmpty) return '';
    return t.split(RegExp(r'\s+')).first;
  }
}

/// One line of a task's history.
class TaskEvent {
  final int id;

  /// created | seen | started | completed | reopened | cancelled | comment
  final String kind;
  final String actorName;
  final String actorRoleLabel;

  /// True when the signed-in user did this.
  final bool mine;
  final String? note;
  final List<String> photos;
  final DateTime? createdAt;

  const TaskEvent({
    required this.id,
    required this.kind,
    required this.actorName,
    this.actorRoleLabel = '',
    this.mine = false,
    this.note,
    this.photos = const [],
    this.createdAt,
  });

  factory TaskEvent.fromJson(Map<String, dynamic> j) => TaskEvent(
    id: j['id'] as int,
    kind: (j['kind'] ?? '').toString(),
    actorName: (j['actor_name'] ?? '').toString(),
    actorRoleLabel: (j['actor_role_label'] ?? '').toString(),
    mine: j['mine'] == true,
    note: j['note']?.toString(),
    photos: _strings(j['photos']),
    createdAt: _time(j['created_at']),
  );
}

class TeamTask {
  final int id;
  final String title;
  final String? description;
  final TaskPriority priority;
  final String? courtName;
  final DateTime? dueAt;
  final bool isOverdue;
  final bool proofRequired;
  final TaskStatus status;
  final TaskPerson assigner;
  final TaskPerson assignee;
  final DateTime? seenAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final String? completionNote;
  final List<String> proofPhotos;
  final int reopenCount;

  final bool iAmAssigner;
  final bool iAmAssignee;
  final bool canStart;
  final bool canComplete;
  final bool canReopen;
  final bool canCancel;
  final bool canComment;

  /// Only present on a detail response.
  final List<TaskEvent> events;

  const TeamTask({
    required this.id,
    required this.title,
    this.description,
    this.priority = TaskPriority.normal,
    this.courtName,
    this.dueAt,
    this.isOverdue = false,
    this.proofRequired = true,
    this.status = TaskStatus.assigned,
    required this.assigner,
    required this.assignee,
    this.seenAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.createdAt,
    this.completionNote,
    this.proofPhotos = const [],
    this.reopenCount = 0,
    this.iAmAssigner = false,
    this.iAmAssignee = false,
    this.canStart = false,
    this.canComplete = false,
    this.canReopen = false,
    this.canCancel = false,
    this.canComment = false,
    this.events = const [],
  });

  bool get isOpen =>
      status == TaskStatus.assigned || status == TaskStatus.inProgress;

  /// The person on the OTHER end of the task from the signed-in user.
  TaskPerson get counterpart => iAmAssignee ? assigner : assignee;

  factory TeamTask.fromJson(Map<String, dynamic> j) => TeamTask(
    id: j['id'] as int,
    title: (j['title'] ?? '').toString(),
    description: j['description']?.toString(),
    priority: _priority(j['priority']?.toString()),
    courtName: j['court_name']?.toString(),
    dueAt: _time(j['due_at']),
    isOverdue: j['is_overdue'] == true,
    proofRequired: j['proof_required'] != false,
    status: _status(j['status']?.toString()),
    assigner: TaskPerson.fromJson(
      Map<String, dynamic>.from(j['assigner'] as Map),
    ),
    assignee: TaskPerson.fromJson(
      Map<String, dynamic>.from(j['assignee'] as Map),
    ),
    seenAt: _time(j['seen_at']),
    startedAt: _time(j['started_at']),
    completedAt: _time(j['completed_at']),
    cancelledAt: _time(j['cancelled_at']),
    createdAt: _time(j['created_at']),
    completionNote: j['completion_note']?.toString(),
    proofPhotos: _strings(j['proof_photos']),
    reopenCount: (j['reopen_count'] as num?)?.toInt() ?? 0,
    iAmAssigner: j['i_am_assigner'] == true,
    iAmAssignee: j['i_am_assignee'] == true,
    canStart: j['can_start'] == true,
    canComplete: j['can_complete'] == true,
    canReopen: j['can_reopen'] == true,
    canCancel: j['can_cancel'] == true,
    canComment: j['can_comment'] == true,
    events: j['events'] is List
        ? (j['events'] as List)
              .map((e) => TaskEvent.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : const [],
  );
}

/// Counts for the badges and the header line.
class TaskSummary {
  final int mineOpen;
  final int mineOverdue;
  final int sentOpen;
  final int sentOverdue;

  const TaskSummary({
    this.mineOpen = 0,
    this.mineOverdue = 0,
    this.sentOpen = 0,
    this.sentOverdue = 0,
  });

  factory TaskSummary.fromJson(Map<String, dynamic> j) => TaskSummary(
    mineOpen: (j['mine_open'] as num?)?.toInt() ?? 0,
    mineOverdue: (j['mine_overdue'] as num?)?.toInt() ?? 0,
    sentOpen: (j['sent_open'] as num?)?.toInt() ?? 0,
    sentOverdue: (j['sent_overdue'] as num?)?.toInt() ?? 0,
  );
}

class TaskPage {
  final List<TeamTask> tasks;
  final bool hasMore;
  final TaskSummary summary;

  const TaskPage({
    required this.tasks,
    required this.hasMore,
    required this.summary,
  });

  factory TaskPage.fromJson(Map<String, dynamic> j) => TaskPage(
    tasks: (j['tasks'] as List? ?? const [])
        .map((e) => TeamTask.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    hasMore: j['has_more'] == true,
    summary: TaskSummary.fromJson(
      Map<String, dynamic>.from(j['summary'] as Map? ?? const {}),
    ),
  );
}

/// What the assign screen collects.
class NewTaskDraft {
  final String title;
  final String? description;
  final String assigneeKey;
  final TaskPriority priority;
  final int? courtId;
  final DateTime? dueAt;
  final bool proofRequired;

  const NewTaskDraft({
    required this.title,
    this.description,
    required this.assigneeKey,
    this.priority = TaskPriority.normal,
    this.courtId,
    this.dueAt,
    this.proofRequired = true,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    if (description != null && description!.trim().isNotEmpty)
      'description': description!.trim(),
    'assignee': assigneeKey,
    'priority': priorityValue(priority),
    if (courtId != null) 'court_id': courtId,
    // Sent as UTC so the server never has to guess the phone's zone.
    if (dueAt != null) 'due_at': dueAt!.toUtc().toIso8601String(),
    'proof_required': proofRequired,
  };
}
