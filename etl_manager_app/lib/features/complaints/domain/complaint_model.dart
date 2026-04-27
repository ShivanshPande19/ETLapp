// lib/features/complaints/domain/complaint_model.dart

class ComplaintModel {
  final int id;
  final int courtId;
  final String category; // food | staff | cleanliness | other
  final String description;
  final String status; // open | in_progress | resolved
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const ComplaintModel({
    required this.id,
    required this.courtId,
    required this.category,
    required this.description,
    required this.status,
    this.createdAt,
    this.resolvedAt,
  });

  factory ComplaintModel.fromJson(Map<String, dynamic> j) => ComplaintModel(
    id: j['id'] as int,
    courtId: j['court_id'] as int,
    category: j['category'] as String,
    description: j['description'] as String,
    status: j['status'] as String,
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'] as String)?.toLocal()
        : null,
    resolvedAt: j['resolved_at'] != null
        ? DateTime.tryParse(j['resolved_at'] as String)?.toLocal()
        : null,
  );

  ComplaintModel copyWith({String? status, DateTime? resolvedAt}) =>
      ComplaintModel(
        id: id,
        courtId: courtId,
        category: category,
        description: description,
        status: status ?? this.status,
        createdAt: createdAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
      );
}
