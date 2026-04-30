// lib/features/maintenance/domain/maintenance_model.dart

class MaintenanceIssue {
  final int id;
  final int courtId;
  final String courtName;
  final String cartId;
  final String cartName;
  final String staffName;
  final String issueType;
  final String description;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;

  const MaintenanceIssue({
    required this.id,
    required this.courtId,
    required this.courtName,
    required this.cartId,
    required this.cartName,
    required this.staffName,
    required this.issueType,
    required this.description,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.resolvedAt,
  });

  factory MaintenanceIssue.fromJson(Map<String, dynamic> j) => MaintenanceIssue(
    id: j['id'] as int,
    courtId: j['court_id'] as int,
    courtName: j['court_name'] as String? ?? '',
    cartId: j['cart_id'] as String? ?? '',
    cartName: j['cart_name'] as String? ?? '',
    staffName: j['staff_name'] as String? ?? '',
    issueType: j['issue_type'] as String? ?? 'other',
    description: j['description'] as String,
    status: j['status'] as String,
    createdAt: j['created_at'] != null
        ? DateTime.tryParse('${j['created_at']}Z')?.toLocal()
        : null,
    updatedAt: j['updated_at'] != null
        ? DateTime.tryParse('${j['updated_at']}Z')?.toLocal()
        : null,
    resolvedAt: j['resolved_at'] != null
        ? DateTime.tryParse('${j['resolved_at']}Z')?.toLocal()
        : null,
  );

  MaintenanceIssue copyWith({String? status, DateTime? resolvedAt}) =>
      MaintenanceIssue(
        id: id,
        courtId: courtId,
        courtName: courtName,
        cartId: cartId,
        cartName: cartName,
        staffName: staffName,
        issueType: issueType,
        description: description,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
      );
}
