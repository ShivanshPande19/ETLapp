class NoticeModel {
  final int id;
  final String audience; // "manager" | "staff"
  final String type; // "early_logout" | "shift_changed"
  final int? courtId;
  final int? staffId;
  final String title;
  final String? body;
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
    required this.isRead,
    this.createdAt,
  });

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
      isRead: j['is_read'] ?? false,
      createdAt: parse(j['created_at']?.toString()),
    );
  }
}
