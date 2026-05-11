class StaffModel {
  final int id;
  final String name;
  final String email;
  final String role;
  final int? courtId;
  final bool isActive;

  const StaffModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.courtId,
    required this.isActive,
  });

  factory StaffModel.fromJson(Map<String, dynamic> j) => StaffModel(
    id: j['id'],
    name: j['name'],
    email: j['email'],
    role: j['role'],
    courtId: j['court_id'],
    isActive: j['is_active'],
  );
}
