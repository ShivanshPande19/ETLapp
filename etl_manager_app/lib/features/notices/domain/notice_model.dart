class NoticeModel {
  final int id;
  final String audience; // "manager" | "staff"
  final String type; // "early_logout" | "shift_changed"
  final int? courtId;
  final int? staffId;
  final String title;
  final String? body;

  /// Where tapping this notice leads, e.g. "/tasks/42". Null for notices that
  /// have no screen of their own.
  final String? route;
  final bool isRead;
  final DateTime? createdAt;

  const NoticeModel({
    required this.id,
    required this.audience,
    required this.type,
    this.courtId,
    this.staffId,
    required this.title,
    this.body,
    this.route,
    required this.isRead,
    this.createdAt,
  });

  /// The in-app location this notice may open, or null. Only locations this
  /// app knows how to open from the inbox are honoured — anything else in
  /// `route` is ignored rather than navigated to.
  String? get openableRoute {
    final r = route;
    if (r == null) return null;
    return RegExp(r'^/tasks/\d+$').hasMatch(r) ? r : null;
  }

  factory NoticeModel.fromJson(Map<String, dynamic> j) {
    DateTime? parse(String? s) {
      if (s == null || s.isEmpty) return null;
      try {
        return DateTime.parse(s).toLocal();
      } catch (_) {
        return null;
      }
    }

    return NoticeModel(
      id: j['id'],
      audience: j['audience'] ?? 'manager',
      type: j['type'] ?? '',
      courtId: j['court_id'],
      staffId: j['staff_id'],
      title: j['title'] ?? '',
      body: j['body'],
      route: j['route']?.toString(),
      isRead: j['is_read'] ?? false,
      createdAt: parse(j['created_at']?.toString()),
    );
  }
}
